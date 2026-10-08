plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val addkoPythonRuntimeDir = layout.buildDirectory.dir("addko-python-runtime")
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

    sourceSets.getByName("main") {
        assets.srcDir(addkoPythonRuntimeDir.map { it.dir("assets") })
        jniLibs.srcDir(addkoPythonRuntimeDir.map { it.dir("jniLibs") })
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

    val output = addkoPythonRuntimeDir.get().asFile
    outputs.dir(output)
    inputs.file(rootProject.file("../tools/android/fetch_python_runtime.py"))

    workingDir(rootProject.projectDir.parentFile)
    commandLine(
        pythonCommand,
        "tools/android/fetch_python_runtime.py",
        "--output",
        output.absolutePath,
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
