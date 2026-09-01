import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release secrets live only in android/key.properties, which Git ignores.
val releaseProperties = Properties()
val releasePropertiesFile = rootProject.file("key.properties")
if (releasePropertiesFile.exists()) {
    releaseProperties.load(FileInputStream(releasePropertiesFile))
}

// A private release key is optional because this student project is installed
// directly for testing. If one is supplied, validate it before Gradle uses it.
if (releasePropertiesFile.exists()) {
    // These four values are the complete Android keystore contract used below.
    val requiredSigningProperties =
        listOf("storePassword", "keyPassword", "keyAlias", "storeFile")
    // Reject empty values and the public example placeholders without printing secrets.
    requiredSigningProperties.forEach { propertyName ->
        val propertyValue = releaseProperties.getProperty(propertyName)?.trim().orEmpty()
        if (propertyValue.isEmpty() || propertyValue.startsWith("replace-with")) {
            throw GradleException("android/key.properties has an invalid $propertyName value.")
        }
    }
    // Refuse a path that does not resolve to a concrete owner-provided keystore file.
    val configuredStoreFile = file(releaseProperties.getProperty("storeFile"))
    if (!configuredStoreFile.isFile) {
        throw GradleException("The release keystore path in android/key.properties does not exist.")
    }
}

android {
    namespace = "ly.edu.limu.peerstudy"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // This stable application ID also identifies the phone deep-link target.
        applicationId = "ly.edu.limu.peerstudy"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releasePropertiesFile.exists()) {
            create("release") {
                keyAlias = releaseProperties.getProperty("keyAlias")
                keyPassword = releaseProperties.getProperty("keyPassword")
                storeFile = file(releaseProperties.getProperty("storeFile"))
                storePassword = releaseProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // A provided private key wins. Otherwise Android's local debug key
            // keeps the optimized APK installable without deployment setup.
            signingConfig = if (releasePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Store-only shrinking is unnecessary for direct classroom tests
            // and makes a first build much slower on a student computer.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
