plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "vn.sana.sbox"
    compileSdk = flutter.compileSdkVersion
    // Play 16 KB RELRO: NDK r28+ (Flutter 3.44 default is already 28.2.13676358).
    ndkVersion = "28.2.13676358"

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

    // hrm = Play listing hiện tại (sbox.sana.vn). pos = listing SBOX POS mới.
    flavorDimensions += "app"
    productFlavors {
        create("hrm") {
            dimension = "app"
            isDefault = true
            applicationId = "sbox.sana.vn"
        }
        create("pos") {
            dimension = "app"
            applicationId = "sbox.sana.vn.pos"
        }
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
    implementation("androidx.activity:activity-ktx:1.10.1")
    // shared_preferences_android 2.4.20 pulls datastore 1.2.0 whose
    // libdatastore_shared_counter.so fails Play 16 KB RELRO. 1.2.1 rebuilt it.
    implementation("androidx.datastore:datastore:1.2.1")
    implementation("androidx.datastore:datastore-preferences:1.2.1")
}

configurations.configureEach {
    resolutionStrategy {
        force("androidx.datastore:datastore:1.2.1")
        force("androidx.datastore:datastore-android:1.2.1")
        force("androidx.datastore:datastore-core:1.2.1")
        force("androidx.datastore:datastore-core-android:1.2.1")
        force("androidx.datastore:datastore-preferences:1.2.1")
        force("androidx.datastore:datastore-preferences-android:1.2.1")
        force("androidx.datastore:datastore-preferences-core:1.2.1")
    }
}
