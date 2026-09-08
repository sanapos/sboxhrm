content = """plugins {
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

    flavorDimensions += "android_version"

    productFlavors {
        create("android12") {
            dimension = "android_version"
            applicationIdSuffix = ".android12"
            versionNameSuffix = "-a12"
            minSdk = 24
        }
        create("android6") {
            dimension = "android_version"
            applicationIdSuffix = ".android6"
            versionNameSuffix = "-a6"
            minSdk = 21
            targetSdk = 23
        }
    }

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
"""
with open(r'e:\SBOX CURSOR\ZKTecoADMS-master\flutter_client\android\app\build.gradle.kts', 'w', encoding='utf-8') as f:
    f.write(content)
print("Done")
