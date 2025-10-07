plugins {
    id("com.android.application")
    id("kotlin-android")
<<<<<<< HEAD
    id("dev.flutter.flutter-gradle-plugin") // Flutter plugin after Android/Kotlin
=======
    id("dev.flutter.flutter-gradle-plugin")
>>>>>>> 9bd1e0779a8086af31ef5090d4d9b29499623a2e
}

android {
    namespace = "com.example.camme"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.example.camme"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = 1
<<<<<<< HEAD
        versionName = "1.0"
    }

=======
        versionName = "1.0.0"
        multiDexEnabled = true
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            isShrinkResources = false // <-- Add this line
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }


>>>>>>> 9bd1e0779a8086af31ef5090d4d9b29499623a2e
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
<<<<<<< HEAD
        jvmTarget = "11"
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false // prevent the shrinkResources error
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        getByName("debug") {
            isMinifyEnabled = false
            isShrinkResources = false
        }
=======
        jvmTarget = JavaVersion.VERSION_11.toString()
>>>>>>> 9bd1e0779a8086af31ef5090d4d9b29499623a2e
    }
}

flutter {
    source = "../.."
}
