# Buduje podpisany APK wydania Synergia Lite (docs/release.md).
#
# Kolejno: narzędzia → konfiguracja podpisu i hasło → czysty stan Git →
# format, analiza, testy → APK release (bez flag eksperymentalnych) →
# kontrola APK (apksigner, aapt2) → dist\: APK, SHA-256, manifest wydania.
#
# Hasło klucza: zmienna SYNERGIA_KEYSTORE_PASSWORD albo pytanie w terminalu
# (niewidoczne). Trafia wyłącznie do zmiennych środowiskowych tego procesu
# i jego procesów potomnych (Gradle); po zakończeniu jest usuwane, a demon
# Gradle zatrzymywany. Skrypt nie zapisuje haseł nigdzie.
#
# Przykłady:
#   .\tool\build_release.ps1
#   .\tool\build_release.ps1 -SigningProperties D:\inny\release-signing.properties

param(
    [string]$SigningProperties = $(if ($env:SYNERGIA_SIGNING_PROPERTIES) { $env:SYNERGIA_SIGNING_PROPERTIES } else { Join-Path $env:USERPROFILE '.synergia-lite\release-signing.properties' }),
    [string]$OutDir = (Join-Path $PSScriptRoot '..\dist'),
    # Tylko do sprawdzenia samego procesu — takiego APK nie wolno rozsyłać.
    [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repo

function Step([string]$text) { Write-Host "`n== $text" -ForegroundColor Cyan }
function Fail([string]$text) { Write-Host "BŁĄD: $text" -ForegroundColor Red; exit 1 }

# Narzędzia zewnętrzne piszą postęp na stderr — o błędzie decyduje kod wyjścia.
function Invoke-Checked([string]$what, [scriptblock]$command) {
    $ErrorActionPreference = 'Continue'
    & $command
    if ($LASTEXITCODE -ne 0) { Fail "$what (kod $LASTEXITCODE)" }
}

# --- 1. Narzędzia ---------------------------------------------------------
Step 'Narzędzia'
$jdk = if ($env:SYNERGIA_JDK) { $env:SYNERGIA_JDK } else { 'C:\Program Files\Android\Android Studio\jbr' }
$keytool = Join-Path $jdk 'bin\keytool.exe'
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
$buildTools = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory -ErrorAction SilentlyContinue |
    Sort-Object { [version]($_.Name -replace '[^0-9.]', '') } -Descending | Select-Object -First 1
$apksigner = if ($buildTools) { Join-Path $buildTools.FullName 'apksigner.bat' }
$aapt2 = if ($buildTools) { Join-Path $buildTools.FullName 'aapt2.exe' }
foreach ($tool in @(
        @{ Name = 'flutter'; Ok = [bool](Get-Command flutter -ErrorAction SilentlyContinue) },
        @{ Name = 'git'; Ok = [bool](Get-Command git -ErrorAction SilentlyContinue) },
        @{ Name = "keytool ($keytool)"; Ok = (Test-Path $keytool) },
        @{ Name = "apksigner ($apksigner)"; Ok = ($apksigner -and (Test-Path $apksigner)) },
        @{ Name = "aapt2 ($aapt2)"; Ok = ($aapt2 -and (Test-Path $aapt2)) })) {
    if (-not $tool.Ok) { Fail "brak narzędzia: $($tool.Name)" }
}
Write-Host "build-tools $($buildTools.Name), JDK $jdk"

# --- 2. Wersja ------------------------------------------------------------
$versionLine = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)\+(\d+)\s*$'
if (-not $versionLine) { Fail 'pubspec.yaml: oczekiwano "version: <nazwa>+<versionCode>"' }
$versionName = $versionLine.Matches[0].Groups[1].Value
$versionCode = [int]$versionLine.Matches[0].Groups[2].Value
$version = "$versionName+$versionCode"
Write-Host "Wersja: $versionName (versionCode $versionCode)"

New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$previous = Get-ChildItem $OutDir -Filter '*.release.json' -ErrorAction SilentlyContinue |
    ForEach-Object { Get-Content -Raw -Encoding utf8 $_.FullName | ConvertFrom-Json } |
    Sort-Object versionCode -Descending | Select-Object -First 1
if ($previous -and $previous.versionCode -ge $versionCode) {
    Fail "versionCode $versionCode nie jest wyższy niż w poprzednim wydaniu ($($previous.versionName), $($previous.versionCode)). Podnieś wersję w pubspec.yaml."
}

# --- 3. Podpis ------------------------------------------------------------
Step 'Konfiguracja podpisu'
if (-not (Test-Path $SigningProperties)) {
    Fail "brak konfiguracji podpisu: $SigningProperties`n  Utwórz klucz: .\tool\create_release_keystore.ps1 (docs/release.md)."
}
$props = @{}
foreach ($line in Get-Content $SigningProperties) {
    if ($line -match '^\s*([A-Za-z]+)\s*=\s*(.+?)\s*$') { $props[$Matches[1]] = $Matches[2] }
}
if ($props.ContainsKey('storePassword') -or $props.ContainsKey('keyPassword')) {
    Fail "$SigningProperties zawiera hasło — usuń je; hasło podaje się przy budowaniu."
}
$keystore = $props['storeFile']
$alias = $props['keyAlias']
if (-not $keystore -or -not (Test-Path $keystore)) { Fail "brak pliku keystore: $keystore" }
if (-not $alias) { Fail "brak keyAlias w $SigningProperties" }
if ((Resolve-Path $keystore).Path.StartsWith($repo, [StringComparison]::OrdinalIgnoreCase)) {
    Fail 'keystore leży w repozytorium — przenieś go poza projekt.'
}

if (-not $env:SYNERGIA_KEYSTORE_PASSWORD) {
    $secure = Read-Host -AsSecureString "Hasło klucza wydań ($alias)"
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $env:SYNERGIA_KEYSTORE_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
$env:SYNERGIA_SIGNING_PROPERTIES = (Resolve-Path $SigningProperties).Path

try {
    # Sprawdzenie hasła i aliasu przed długą kompilacją.
    $ErrorActionPreference = 'Continue'
    $listing = & $keytool -list -v -keystore $keystore -storepass:env SYNERGIA_KEYSTORE_PASSWORD -alias $alias 2>&1
    if ($LASTEXITCODE -ne 0) { Fail 'nie udało się otworzyć klucza (złe hasło albo alias).' }
    $ErrorActionPreference = 'Stop'
    $keyFingerprint = (($listing | Select-String 'SHA256:\s*([0-9A-F:]+)').Matches[0].Groups[1].Value -replace ':', '').ToLower()
    if (($listing | Select-String 'CN=Android Debug')) { Fail 'to jest klucz debug — wydania wymagają klucza release.' }
    Write-Host "Klucz: $alias, certyfikat SHA-256 $keyFingerprint"

    # --- 4. Stan repozytorium ---------------------------------------------
    Step 'Stan Git'
    $commit = (git rev-parse HEAD).Trim()
    $dirty = git status --porcelain
    if ($dirty) {
        if (-not $AllowDirty) { Fail "niezacommitowane zmiany — wydanie musi odpowiadać commitowi.`n$($dirty -join "`n")" }
        Write-Host 'UWAGA: niezacommitowane zmiany (-AllowDirty) — tego APK nie wolno rozsyłać.' -ForegroundColor Yellow
    }
    Write-Host "Commit: $commit"

    # --- 5. Jakość ----------------------------------------------------------
    Step 'Format, analiza, testy'
    Invoke-Checked 'dart format' { dart format --output=none --set-exit-if-changed lib test }
    Invoke-Checked 'flutter analyze' { flutter analyze }
    Invoke-Checked 'flutter test' { flutter test }

    # --- 6. Build -----------------------------------------------------------
    Step 'Build APK release'
    # Jedyna flaga: wersja do ekranu „O aplikacji”. Funkcje eksperymentalne
    # (SYNERGIA_BACKGROUND_SYNC, SYNERGIA_NATIVE_EXCUSE_SUBMIT,
    # SYNERGIA_DIAGNOSTICS) pozostają wyłączone — fail-closed.
    Invoke-Checked 'flutter build apk --release' {
        & (Join-Path $PSScriptRoot 'flutter_android.ps1') build apk --release "--dart-define=SYNERGIA_VERSION=$version"
    }
    $apk = Join-Path $repo 'build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path $apk)) { Fail "brak pliku $apk" }

    # --- 7. Kontrola APK ----------------------------------------------------
    Step 'Kontrola APK'
    # apksigner.bat wymaga JAVA_HOME (tylko dla tego procesu).
    if (-not $env:JAVA_HOME) { $env:JAVA_HOME = $jdk; $javaHomeSet = $true }
    $ErrorActionPreference = 'Continue'
    $verify = & $apksigner verify --verbose --print-certs $apk 2>&1
    $verifyExit = $LASTEXITCODE
    $badging = & $aapt2 dump badging $apk 2>&1
    $ErrorActionPreference = 'Stop'
    if ($verifyExit -ne 0) { Fail "apksigner: podpis niepoprawny`n$($verify -join "`n")" }
    if (-not ($verify | Select-String 'Verified using v2 scheme \(APK Signature Scheme v2\): true')) {
        Fail 'APK nie ma podpisu v2.'
    }
    if (($verify | Select-String '^Number of signers: (\d+)').Matches[0].Groups[1].Value -ne '1') { Fail 'APK musi mieć dokładnie jednego sygnatariusza.' }
    # Etykieta zależy od schematów: „Signer #1” (v1+v2) albo „V2 Signer” (sam v2).
    $apkFingerprint = (($verify | Select-String '(?:Signer #1|V2 Signer): certificate SHA-256 digest:\s*([0-9a-f]+)').Matches[0].Groups[1].Value)
    if ($apkFingerprint -ne $keyFingerprint) { Fail "APK podpisany innym certyfikatem ($apkFingerprint)." }
    if ($verify | Select-String 'CN=Android Debug') { Fail 'APK podpisany kluczem debug.' }

    $package = ($badging | Select-String "^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'").Matches[0]
    if (-not $package) { Fail 'aapt2: nie odczytano nazwy pakietu.' }
    $applicationId = $package.Groups[1].Value
    if ([int]$package.Groups[2].Value -ne $versionCode -or $package.Groups[3].Value -ne $versionName) {
        Fail "wersja w APK ($($package.Groups[3].Value)/$($package.Groups[2].Value)) różni się od pubspec.yaml."
    }
    if ($badging | Select-String '^application-debuggable') { Fail 'APK ma flagę debuggable.' }
    $permissions = @($badging | Select-String "^uses-permission: name='([^']+)'" |
        ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique)
    $minSdk = ($badging | Select-String "^(?:sdkVersion|minSdkVersion):'(\d+)'").Matches[0].Groups[1].Value
    $targetSdk = ($badging | Select-String "^targetSdkVersion:'(\d+)'").Matches[0].Groups[1].Value
    Write-Host "Pakiet $applicationId, podpis v2 OK, certyfikat zgodny z kluczem wydań."
    Write-Host "Uprawnienia: $($permissions -join ', ')"

    # --- 8. dist\ -----------------------------------------------------------
    Step 'Artefakty'
    $baseName = "synergia-lite-$versionName-$versionCode"
    $target = Join-Path $OutDir "$baseName.apk"
    if (Test-Path $target) { Fail "$target już istnieje — nie nadpisuję wydanego pliku." }
    Copy-Item $apk $target
    $sha256 = (Get-FileHash -Algorithm SHA256 $target).Hash.ToLower()
    "$sha256  $baseName.apk" | Set-Content -Encoding ascii (Join-Path $OutDir "$baseName.apk.sha256")
    $manifest = [ordered]@{
        app                    = 'Synergia Lite'
        releaseName            = "Synergia Lite $versionName"
        versionName            = $versionName
        versionCode            = $versionCode
        applicationId          = $applicationId
        file                   = "$baseName.apk"
        sizeBytes              = (Get-Item $target).Length
        sha256                 = $sha256
        signingCertSha256      = $apkFingerprint
        builtAtUtc             = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        gitCommit              = $commit
        gitDirty               = [bool]$dirty
        minSdk                 = [int]$minSdk
        targetSdk              = [int]$targetSdk
        permissions            = $permissions
        experimentalFeatures   = @()
        status                 = 'kandydat — wymaga przejścia docs/beta/release-checklist.md'
    }
    [IO.File]::WriteAllText((Join-Path $OutDir "$baseName.release.json"), ($manifest | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))

    Write-Host ''
    Write-Host "APK:     $target" -ForegroundColor Green
    Write-Host "SHA-256: $sha256" -ForegroundColor Green
    Write-Host "Dalej: docs/beta/release-checklist.md (testy ręczne przed rozesłaniem)."
} finally {
    Remove-Item Env:SYNERGIA_KEYSTORE_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:SYNERGIA_KEY_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:SYNERGIA_SIGNING_PROPERTIES -ErrorAction SilentlyContinue
    if ($javaHomeSet) { Remove-Item Env:JAVA_HOME -ErrorAction SilentlyContinue }
    # Demon Gradle przechowuje środowisko procesu — zatrzymujemy go.
    $ErrorActionPreference = 'Continue'
    & (Join-Path $repo 'android\gradlew.bat') -p (Join-Path $repo 'android') --stop 2>&1 | Out-Null
}
exit 0
