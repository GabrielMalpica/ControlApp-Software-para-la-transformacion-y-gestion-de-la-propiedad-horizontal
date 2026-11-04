import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de la APK que se publica en /descargas/. `android/key.properties` no
// se sube a git (lo escribe el workflow de GitHub Actions con los secretos):
//   storeFile=controlapp-release.p12   (relativo a android/app/)
//   storePassword=...
//   keyAlias=...
//   keyPassword=...
//   storeType=pkcs12
// Sin ese archivo (desarrollo) la versión release se firma con la llave de
// depuración: sirve para probar, pero no para actualizar la app instalada
// desde /descargas/ (Android exige la misma firma).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val tieneFirmaRelease = keystorePropertiesFile.exists()
if (tieneFirmaRelease) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "co.com.controlsas.controlapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // ota_update usa APIs de Java modernas: hay que "desazucararlas".
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "co.com.controlsas.controlapp"
        // workmanager y ota_update piden Android 6 (API 23) como mínimo.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (tieneFirmaRelease) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeType = keystoreProperties.getProperty("storeType") ?: "pkcs12"
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (tieneFirmaRelease) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
