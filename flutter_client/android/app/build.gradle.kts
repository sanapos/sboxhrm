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

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    // hrm = Play listing hiện tại (sbox.sana.vn). pos = listing SBOX POS mới. kds = SBOX KDS. boss = SBOX BOSS (app chủ cửa hàng).
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
        // SBOX KDS (chỉ màn hình bếp) cho Android 7+. Bản Android 6 (Sunmi T1/V2s) vẫn là
        // sbox.sana.vn.kds build từ flutter_pos — hai mã khác nhau, cài song song được.
        create("kds") {
            dimension = "app"
            applicationId = "kds.sboxpos.com"
        }
        create("boss") {
            dimension = "app"
            applicationId = "boss.sboxpos.com"
        }
        // SBOX Nhân Viên: app nhân viên (chấm công, lịch, lương, đơn từ, gọi món) — cài song song HRM.
        create("staff") {
            dimension = "app"
            applicationId = "staff.sboxpos.com"
        }
    }

    // Flavors android6/android12 (applicationIdSuffix) temporarily disabled so
    // release APK installs as production package sbox.sana.vn (A7 C20Lite / OTA).
    // Re-enable when dual-package sideload is intentional.

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
        }
    }
}

flutter {
    source = "../.."
}

// SBOX KDS (kds.sboxpos.com) chưa đăng ký Firebase → bỏ bước google-services (không FCM, xem FcmService).
// SBOX Nhân Viên (staff.sboxpos.com): bật khi google-services.json có gói này (app đã đăng ký trên
// Firebase) — thiếu thì bỏ, app nhận thông báo qua SignalR khi đang mở.
val staffInFirebase = file("google-services.json").let { f ->
    f.exists() && f.readText().contains("\"staff.sboxpos.com\"")
}
// SBOX BOSS (boss.sboxpos.com): tương tự — google-services.json thiếu gói này thì bỏ bước google-services.
val bossInFirebase = listOf(file("google-services.json"), file("src/boss/google-services.json"))
    .any { it.exists() && it.readText().contains("\"boss.sboxpos.com\"") }
tasks.configureEach {
    if (name.startsWith("process") && name.endsWith("GoogleServices") &&
        (name.contains("Kds") || (name.contains("Staff") && !staffInFirebase) ||
            (name.contains("Boss") && !bossInFirebase))) {
        enabled = false
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.activity:activity-ktx:1.10.1")
    implementation("androidx.core:core-ktx:1.16.0")
    // Cân điện tử qua cáp USB-Serial: CH340, PL2303, CP210x, FTDI, CDC-ACM (thuần Java, không .so).
    implementation("com.github.mik3y:usb-serial-for-android:3.8.1")
    // Máy in tích hợp iMin (IminPrinterBridge.kt). Không dùng plugin Flutter imin_printer:
    // plugin khởi tạo SDK ngay khi mở app trên MỌI máy Android ≤ 11 (quét, xin quyền USB).
    // SDK 1.0 (Android ≤ 11, USB/SPI) — jar lấy từ imin_printer 0.7.5 (BSD-3, iminsoftware).
    implementation(files("libs/iminPrinterSDK-V1.3.2.jar"))
    // SDK 2.0 (Android 12L+, dịch vụ com.imin.printerservice).
    implementation("com.github.iminsoftware:IminPrinterLibrary:V2.0.0.18")
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
