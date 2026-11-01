import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名。
//
// 背景：之前 release 用的是 signingConfigs.debug，而 debug 密钥在 CI 上
// 是每次运行现生成的（~/.android/debug.keystore），所以每构建一次签名都不一样，
// 手机上覆盖安装必报「签名不一致」，只能先卸载——本地数据也跟着没了。
//
// 现在固定用仓库内的 little-footprint.p12。想换密钥又不想写进仓库的话，
// 可以在 android/key.properties 里覆盖（该文件已 gitignore）：
//   storeFile=xxx.jks
//   storePassword=***
//   keyAlias=***
//   keyPassword=***
val keyPropsFile = rootProject.file("key.properties")
val keyProps = Properties().apply {
    if (keyPropsFile.exists()) {
        keyPropsFile.inputStream().use { load(it) }
    }
}

// 提前解析成 File，避免在 SigningConfig 的闭包里调用 file() 造成接收者歧义
val releaseStorePath = keyProps.getProperty("storeFile") ?: "little-footprint.p12"
val releaseStoreFile = file(releaseStorePath)
val releaseStorePassword = keyProps.getProperty("storePassword") ?: "littlefootprint2026"
val releaseKeyAlias = keyProps.getProperty("keyAlias") ?: "littlefootprint"
val releaseKeyPassword = keyProps.getProperty("keyPassword") ?: "littlefootprint2026"

android {
    namespace = "com.yourfamily.little_footprint"
    compileSdk = flutter.compileSdkVersion
    // 跟随当前 Flutter 版本推荐的 NDK，避免在 CI 上强制下载未预装的特定版本
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.yourfamily.little_footprint"
        // record_android 要求 minSdk 23，而 flutter.minSdkVersion 为 21，
        // 不显式抬高会直接构建失败（uses-sdk:minSdkVersion 21 < 23）。
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStoreFile
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            // 固定密钥签名，保证每次构建出来的 APK 可以覆盖安装
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
