plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.srtristesad.addko"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.srtristesad.addko"
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters.clear()
            abiFilters += "arm64-v8a"
        }
    }

    sourceSets.getByName("main") {
        java.srcDir("../../third_party/kodi_21_3/java")
        res.srcDir("../../third_party/kodi_21_3/res")
        assets.srcDir("../../third_party/kodi_21_3/assets")
        jniLibs.srcDir("../../third_party/kodi_21_3/jniLibs")
    }
    androidResources {
        // AAPT's default ignores directories beginning with '_', which drops
        // Python's _vendor/_bundled modules and Kodi's web translations.
        ignoreAssetsPattern = "!.svn:!.git:!.ds_store:!*.scc:!CVS:!thumbs.db:!picasa.ini:!*~"
    }
    packaging {
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols += "**/*.so"
            pickFirsts += "**/libc++_shared.so"
        }
    }

    buildTypes {
        release {
            // Kodi looks up Java classes/methods through JNI at runtime.
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
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
    implementation("androidx.tvprovider:tvprovider:1.1.0-alpha01")
    implementation("com.google.code.gson:gson:2.10.1")
}
