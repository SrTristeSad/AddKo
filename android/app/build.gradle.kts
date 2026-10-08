plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val addkoPythonRuntimeDir = layout.buildDirectory.dir("addko-python-runtime")
val addkoPythonRuntimeRoot = addkoPythonRuntimeDir.get().asFile
val pythonCommand = System.getenv("PYTHON")?.takeIf { it.isNotBlank() }
    ?: if (System.getProperty("os.name").lowercase().contains("windows")) "python" else "python3"

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
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Python.org currently publishes official Android embeddable packages for
        // these 64-bit ABIs. 32-bit ARM can be added later from a source build.
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
            }
        }
    }

    // Use concrete File paths here. AGP 9 rejects Provider instances passed to
    // the legacy SourceSet API because it cannot classify them as generated or
    // static sources during IDE model construction.
    sourceSets.getByName("main") {
        assets.srcDir(File(addkoPythonRuntimeRoot, "assets"))
        jniLibs.srcDir(File(addkoPythonRuntimeRoot, "jniLibs"))
    }

    externalNativeBuild {
        cmake {
            path = file("../../native/python_host/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

val prepareAddKoPythonRuntime by tasks.registering(Exec::class) {
    group = "addko"
    description = "Downloads, verifies and stages the official CPython Android runtime."

    outputs.dir(addkoPythonRuntimeRoot)
    inputs.file(rootProject.file("../tools/android/fetch_python_runtime.py"))

    workingDir(rootProject.projectDir.parentFile)
    commandLine(
        pythonCommand,
        "tools/android/fetch_python_runtime.py",
        "--output",
        addkoPythonRuntimeRoot.absolutePath,
    )
}

tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(prepareAddKoPythonRuntime)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
