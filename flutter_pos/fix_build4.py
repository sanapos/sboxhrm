content = """plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

def localProperties = new Properties()
def localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.withReader("UTF-8") { reader ->
        localProperties.load(reader)
    }
}

def flutterVersionCode = localProperties.getProperty("flutter.versionCode")
if (flutterVersionCode == null) {
    flutterVersionCode = "1"
}

def flutterVersionName = localProperties.getProperty("flutter.versionName")
if (flutterVersionName == null) {
    flutterVersionName = "1.0"
}

android {
    namespace = "vn.sana.sbox.sbox_pos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        coreLibraryDesugaringEnabled true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "sbox.sana.vn.pos.flutter"
        minSdkVersion 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutterVersionCode.toInteger()
        versionName = flutterVersionName
        multiDexEnabled true
    }

    flavorDimensions += "android_version"

    productFlavors {
        android12 {
            dimension "android_version"
            applicationIdSuffix ".android12"
            versionNameSuffix "-a12"
            minSdkVersion 24
            targetSdkVersion 34
        }
        android6 {
            dimension "android_version"
            applicationIdSuffix ".android6"
            versionNameSuffix "-a6"
            minSdkVersion 21
            targetSdkVersion 23
            resValue "string", "app_name", "SBOX POS A6"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.debug
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
        debug {
            applicationIdSuffix ".debug"
            versionNameSuffix "-debug"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4'
    implementation files("libs/DS_Lib-1.0.16.aar")
    implementation "com.alibaba:fastjson:1.1.67.android"
    implementation "org.greenrobot:greendao:3.2.2"
}
"""
with open(r'e:\SBOX CURSOR\ZKTecoADMS-master\flutter_pos\android\app\build.gradle', 'w', encoding='utf-8') as f:
    f.write(content)
print("Done")
