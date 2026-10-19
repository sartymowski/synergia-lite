# Jednorazowo tworzy klucz wydań Synergia Lite (docs/release.md).
#
# Uruchamia go właściciel projektu we własnym terminalu — skrypt pyta o hasło
# (niewidoczne podczas wpisywania) i NIGDZIE go nie zapisuje. Keystore oraz
# plik konfiguracji (bez haseł) powstają poza repozytorium:
#   %USERPROFILE%\.synergia-lite\synergia-lite-release.p12
#   %USERPROFILE%\.synergia-lite\release-signing.properties
#
# Istniejącego klucza nie nadpisuje: ten sam klucz musi podpisywać wszystkie
# kolejne wersje, inaczej testerzy nie zainstalują aktualizacji.
#
# Przykład:
#   .\tool\create_release_keystore.ps1

param(
    [string]$Directory = (Join-Path $env:USERPROFILE '.synergia-lite'),
    [string]$Alias = 'synergia-lite-release'
)

$ErrorActionPreference = 'Stop'

$jdk = if ($env:SYNERGIA_JDK) { $env:SYNERGIA_JDK } else { 'C:\Program Files\Android\Android Studio\jbr' }
$keytool = Join-Path $jdk 'bin\keytool.exe'
if (-not (Test-Path $keytool)) { throw "Nie znaleziono keytool: $keytool (ustaw SYNERGIA_JDK)." }

$keystore = Join-Path $Directory 'synergia-lite-release.p12'
$properties = Join-Path $Directory 'release-signing.properties'
if ((Test-Path $keystore) -or (Test-Path $properties)) {
    throw "Klucz wydań już istnieje ($Directory). Nie nadpisuję go — wydania muszą być podpisywane tym samym kluczem."
}
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([IO.Path]::GetFullPath($Directory).StartsWith($repo, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Katalog klucza nie może leżeć w repozytorium.'
}

function Read-Secret([string]$prompt) {
    $secure = Read-Host -AsSecureString $prompt
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

$password = Read-Secret 'Hasło klucza wydań (min. 12 znaków)'
if ($password.Length -lt 12) { throw 'Hasło jest za krótkie (min. 12 znaków).' }
if ($password -ne (Read-Secret 'Powtórz hasło')) { throw 'Hasła różnią się.' }

New-Item -ItemType Directory -Force $Directory | Out-Null
# keytool odczytuje hasło ze zmiennej środowiskowej tego procesu (:env),
# więc nie pojawia się ono w wierszu poleceń ani w historii.
$env:SYNERGIA_NEW_KEY_PASSWORD = $password
$password = $null
$ErrorActionPreference = 'Continue'
try {
    & $keytool -genkeypair -noprompt `
        -keystore $keystore -storetype PKCS12 `
        -storepass:env SYNERGIA_NEW_KEY_PASSWORD -keypass:env SYNERGIA_NEW_KEY_PASSWORD `
        -alias $Alias -keyalg RSA -keysize 4096 -validity 10000 `
        -dname 'CN=Synergia Lite (nieoficjalny klient), O=Synergia Lite' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "keytool zakończył się kodem $LASTEXITCODE" }
    $listing = & $keytool -list -v -keystore $keystore -storetype PKCS12 `
        -storepass:env SYNERGIA_NEW_KEY_PASSWORD -alias $Alias 2>&1
    $fingerprint = ($listing | Select-String 'SHA256:\s*([0-9A-F:]+)').Matches[0].Groups[1].Value
} finally {
    Remove-Item Env:SYNERGIA_NEW_KEY_PASSWORD -ErrorAction SilentlyContinue
}

# Konfiguracja bez haseł (te podaje się przy każdym wydaniu).
@(
    '# Konfiguracja podpisu Synergia Lite (bez haseł). Nie dodawaj do Git.'
    "storeFile=$($keystore.Replace('\', '/'))"
    "keyAlias=$Alias"
) | Set-Content -Encoding ascii $properties

Write-Host ''
Write-Host "Utworzono klucz wydań: $keystore"
Write-Host "Konfiguracja podpisu:  $properties"
Write-Host "Odcisk SHA-256 certyfikatu (publiczny, do docs/beta/installation-android.md):"
Write-Host "  $fingerprint"
Write-Host ''
Write-Host 'TERAZ: zrób kopię zapasową pliku .p12 i hasła (docs/release.md, sekcja „Kopia zapasowa”).'
Write-Host 'Utrata klucza lub hasła = testerzy nie zainstalują kolejnych aktualizacji bez odinstalowania.'
