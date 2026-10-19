import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Podpis wydań (docs/release.md). Plik konfiguracji i keystore leżą POZA
// repozytorium; hasła — w zmiennych środowiskowych procesu (ustawia je
// tool/build_release.ps1 po zapytaniu użytkownika), nigdy w plikach projektu.
// Brak konfiguracji nie przerywa buildów debug, ale build release kończy się
// czytelnym błędem — wydanie nigdy nie jest podpisywane kluczem debug.
val releaseSigningFile: File = System.getenv("SYNERGIA_SIGNING_PROPERTIES")?.let(::File)
    ?: File(System.getProperty("user.home"), ".synergia-lite/release-signing.properties")

val releaseSigningProblem: String? = run {
    if (!releaseSigningFile.isFile) {
        return@run "brak pliku konfiguracji podpisu: $releaseSigningFile"
    }
    val props = Properties().apply { releaseSigningFile.inputStream().use(::load) }
    val storeFile = props.getProperty("storeFile")?.let(::File)
    when {
        storeFile == null || !storeFile.isFile -> "brak pliku keystore wskazanego w $releaseSigningFile"
        props.getProperty("keyAlias").isNullOrBlank() -> "brak keyAlias w $releaseSigningFile"
        System.getenv("SYNERGIA_KEYSTORE_PASSWORD").isNullOrEmpty() ->
            "brak hasła keystore (zmienna SYNERGIA_KEYSTORE_PASSWORD)"
        else -> null
    }
}

android {
    namespace = "pl.synergialite.synergia_lite"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Wymagane przez flutter_local_notifications (java.time na starszych Androidach).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Stały identyfikator nieoficjalnej aplikacji (bez nazwy „librus”);
        // jego zmiana po pierwszym wydaniu oznaczałaby osobną aplikację.
        applicationId = "pl.synergialite.synergia_lite"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Z pubspec.yaml: version: <versionName>+<versionCode>.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningProblem == null) {
            create("release") {
                val props = Properties().apply { releaseSigningFile.inputStream().use(::load) }
                storeFile = File(props.getProperty("storeFile"))
                storePassword = System.getenv("SYNERGIA_KEYSTORE_PASSWORD")
                keyAlias = props.getProperty("keyAlias")
                // Klucz PKCS12 zwykle ma to samo hasło co magazyn.
                keyPassword = System.getenv("SYNERGIA_KEY_PASSWORD")
                    ?.takeIf { it.isNotEmpty() }
                    ?: System.getenv("SYNERGIA_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

// Sprawdzane dopiero przy budowaniu wariantu release (debug działa bez klucza).
tasks.configureEach {
    if (name == "preReleaseBuild") {
        val problem = releaseSigningProblem
        doFirst {
            if (problem != null) {
                throw GradleException(
                    "Build release wymaga klucza wydań Synergia Lite — $problem. " +
                        "Zob. docs/release.md (tool/create_release_keystore.ps1, " +
                        "tool/build_release.ps1). Klucz debug nie jest używany do wydań.",
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // CookieManagerCompat.getCookieInfo — ta sama wersja co w webview_flutter_android.
    implementation("androidx.webkit:webkit:1.15.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
