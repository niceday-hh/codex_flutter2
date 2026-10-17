import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}
val keyProperties = Properties()
val keyFile = rootProject.file("key.properties")
if (keyFile.exists()) keyFile.inputStream().use { keyProperties.load(it) }
val memoAbis = (project.findProperty("target-platform") as? String ?: "android-arm64").split(",").map {
    when (it) { "android-x64" -> "x86_64"; "android-arm" -> "armeabi-v7a"; else -> "arm64-v8a" }
}

android {
    namespace = "com.niceday.memo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }
    defaultConfig {
        applicationId = "com.niceday.memo.stable"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        externalNativeBuild { cmake { cppFlags += "-std=c++17"; arguments += "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON" } }
    }
    if (keyFile.exists()) {
        signingConfigs {
            create("release") {
                storeType = "PKCS12"
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
                storeFile = file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
            }
        }
    }
    buildTypes {
        configureEach { ndk.abiFilters.clear(); ndk.abiFilters.addAll(memoAbis) }
        release {
            signingConfig = if (keyFile.exists()) signingConfigs.getByName("release") else null
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
    externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" } }
    androidResources { noCompress += listOf("onnx", "mnn") }
    testOptions { unitTests.isIncludeAndroidResources = true }
}
flutter { source = "../.." }
dependencies {
    implementation("com.github.houbb:pinyin:0.4.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.14.1")
}
