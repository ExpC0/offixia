import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingPropertiesFile = rootProject.file("key.properties")
val signingProperties = Properties().apply {
    if (signingPropertiesFile.exists()) {
        signingPropertiesFile.inputStream().use(::load)
    }
}
val buildingRelease = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

val signingKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val missingSigningKeys = signingKeys.filter {
    signingProperties.getProperty(it).isNullOrBlank()
}

if (buildingRelease) {
    if (!signingPropertiesFile.exists() || missingSigningKeys.isNotEmpty()) {
        throw GradleException(
            "Release signing is incomplete. Copy android/key.properties.example " +
                "to android/key.properties and provide every required value.",
        )
    }

    val releaseStore = rootProject.file(signingProperties.getProperty("storeFile"))
    val releaseAlias = signingProperties.getProperty("keyAlias")
    if (!releaseStore.isFile) {
        throw GradleException("Release keystore does not exist: $releaseStore")
    }
    if (releaseStore.name == "debug.keystore" || releaseAlias == "androiddebugkey") {
        throw GradleException(
            "Refusing to sign a release with Android's development certificate. " +
                "Configure a private production keystore.",
        )
    }
}

android {
    namespace = "com.rian.offixia"
    // Pinned to 37 rather than flutter.compileSdkVersion (36):
    // permission_handler ships an AAR that refuses to link against anything
    // lower. compileSdk only controls which APIs we compile against -- minSdk
    // still decides which devices can install the app -- so this costs no
    // compatibility. StreamTune hit exactly the same requirement.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications schedules against java.time, which does
        // not exist below API 26. Desugaring back-ports it so the app can keep
        // minSdk 24 instead of dropping Android 7 devices for a notification.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.rian.offixia"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingPropertiesFile.exists()) {
            create("release") {
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
                storeFile = file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Release packages must be signed by an explicitly configured,
            // untracked production key. A debug certificate is intended for
            // local development and has no suitable backup/release lifecycle.
            signingConfig = if (signingPropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
