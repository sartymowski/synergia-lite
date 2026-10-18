# Uruchamia komendę Fluttera dla Androida tak, by JVM (Gradle, Kotlin)
# ufała także rootowi programu antywirusowego, który przechwytuje HTTPS.
#
# Po co: Avast Web Shield podmienia certyfikaty HTTPS własnym rootem
# zainstalowanym w magazynie Windows, którego nie zna `cacerts` JDK — Gradle
# kończy się błędem `PKIX path building failed`.
#
# Co robi: tworzy osobny magazyn PKCS12 = domyślne rooty JDK + ten jeden root
# skopiowany z magazynu Windows (LocalMachine\Root), i wskazuje go JVM tylko
# w tym procesie. Weryfikacja certyfikatów pozostaje pełna; nie jest zmieniany
# ani `cacerts` JDK, ani żadna globalna konfiguracja.
#
# Przykłady:
#   .\tool\flutter_android.ps1 build apk --debug
#   .\tool\flutter_android.ps1 run

$ErrorActionPreference = 'Stop'

$rootSubjectPattern = 'Avast Web/Mail Shield Root'
$jdk = if ($env:SYNERGIA_JDK) { $env:SYNERGIA_JDK } else { 'C:\Program Files\Android\Android Studio\jbr' }
$keytool = Join-Path $jdk 'bin\keytool.exe'
$jdkCacerts = Join-Path $jdk 'lib\security\cacerts'
$dir = Join-Path $env:LOCALAPPDATA 'SynergiaLite'
$store = Join-Path $dir 'gradle-truststore.p12'
# Hasło chroni wyłącznie publiczne certyfikaty — to domyślne hasło cacerts.
$pass = 'changeit'

# keytool pisze komunikaty na stderr — o błędzie decyduje kod wyjścia.
function Invoke-Keytool {
    $ErrorActionPreference = 'Continue'
    & $keytool @args 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "keytool zakończył się kodem $LASTEXITCODE" }
}

$root = Get-ChildItem Cert:\LocalMachine\Root |
    Where-Object { $_.Subject -match [regex]::Escape($rootSubjectPattern) } |
    Sort-Object NotAfter -Descending | Select-Object -First 1

$javaOptions = $null
if ($root) {
    $stale = -not (Test-Path $store) -or
        (Get-Item $store).LastWriteTime -lt (Get-Item $jdkCacerts).LastWriteTime -or
        -not (Test-Path "$store.$($root.Thumbprint)")
    if ($stale) {
        New-Item -ItemType Directory -Force $dir | Out-Null
        Remove-Item "$store*" -Force -ErrorAction SilentlyContinue
        $cer = Join-Path $dir 'intercepting-root.cer'
        [IO.File]::WriteAllBytes($cer, $root.Export('Cert'))
        Invoke-Keytool -importkeystore -noprompt -srckeystore $jdkCacerts -srcstorepass $pass `
            -destkeystore $store -deststoretype PKCS12 -deststorepass $pass
        Invoke-Keytool -importcert -noprompt -alias intercepting-root -file $cer `
            -keystore $store -storetype PKCS12 -storepass $pass
        Remove-Item $cer
        New-Item -ItemType File "$store.$($root.Thumbprint)" | Out-Null
        Write-Host "Utworzono magazyn zaufania: $store (root: $($root.Thumbprint))"
    }
    $javaOptions = "-Djavax.net.ssl.trustStore=$store -Djavax.net.ssl.trustStoreType=PKCS12 -Djavax.net.ssl.trustStorePassword=$pass"
} else {
    Write-Host 'Nie znaleziono rootu przechwytującego HTTPS — używam domyślnych ustawień JDK.'
}

if ($javaOptions) { $env:JAVA_TOOL_OPTIONS = $javaOptions }
# Narzędzia JVM piszą na stderr (np. "Picked up JAVA_TOOL_OPTIONS") — to nie błąd.
$ErrorActionPreference = 'Continue'
try {
    # Demon Gradle mógł wystartować z innymi ustawieniami TLS.
    if ($javaOptions) { & (Join-Path $PSScriptRoot '..\android\gradlew.bat') -p (Join-Path $PSScriptRoot '..\android') --stop | Out-Null }
    & flutter @args
    exit $LASTEXITCODE
} finally {
    Remove-Item Env:JAVA_TOOL_OPTIONS -ErrorAction SilentlyContinue
}
