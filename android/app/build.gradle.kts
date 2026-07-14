// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

import java.util.Properties
import java.util.Base64
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.protocentral.openview"
    compileSdk = flutter.compileSdkVersion
    //ndkVersion = flutter.ndkVersion

    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.protocentral.openview"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                // use Properties.getProperty which returns null if missing (safer than cast)
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                keystoreProperties.getProperty("storeFile")?.let { storeFile = file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            } else if (System.getenv("KEYSTORE_BASE64") != null) {
                // Decode base64 keystore provided via environment (CI secret)
                val keystoreBytes = Base64.getDecoder().decode(System.getenv("KEYSTORE_BASE64"))
                val keystoreOut = rootProject.file("ci_keystore.jks")
                keystoreOut.writeBytes(keystoreBytes)
                storeFile = keystoreOut
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
                storePassword = System.getenv("STORE_PASSWORD")
            } else {
                // Leave release signing empty so CI can build without a keystore present
            }
        }
    }
    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now,
            // so `flutter run --release` works.
            // Use release signing when key.properties exists or CI keystore env var is set
            isMinifyEnabled = false      // Note the 'is' prefix
            isShrinkResources = false    // Note the 'is' prefix

            if (keystorePropertiesFile.exists() || System.getenv("KEYSTORE_BASE64") != null) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }

}

flutter {
    source = "../.."
}

