pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            // 目录路径含中文（番茄钟）。Properties.load(InputStream) 固定按
            // ISO-8859-1 解码，会把 UTF-8 路径读成乱码导致 includeBuild 找不到
            // SDK；这里改用 UTF-8 Reader 读取。
            file("local.properties").reader(Charsets.UTF_8).use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
