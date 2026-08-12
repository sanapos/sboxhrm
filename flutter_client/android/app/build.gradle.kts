plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "vn.sana.sbox"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            keyAlias = "sbox"
            keyPassword = "123456"
            storeFile = file("sana-release.jks")
            storePassword = "123456"
        }
    }

    defaultConfig {
        applicationId = "sbox.sana.vn"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Flavors android6/android12 (applicationIdSuffix) temporarily disabled so
    // release APK installs as production package sbox.sana.vn (A7 C20Lite / OTA).
    // Re-enable when dual-package sideload is intentional.

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
