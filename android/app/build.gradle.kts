import java.net.URL
import java.security.MessageDigest

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

    externalNativeBuild {
        cmake {
            path = file("../../native/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir("src/main/jniLibs")
        }
    }
    packaging {
        jniLibs {
            useLegacyPackaging = true
            // Keep pinned upstream bytes intact; Android NDK strip modifies ELF.
            keepDebugSymbols += setOf(
                "**/libelementum.so",
                "**/libc++_shared.so",
            )
        }
    }

    buildTypes {
        release {
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


// Approved modules are signed into the APK. Addons never supply native .so.
// Build a lightweight AddKo variant with -PaddkoIncludeElementum=false.
val includeElementum = providers.gradleProperty("addkoIncludeElementum")
    .map { it == "true" }.getOrElse(true)
val pinnedCommit = "2bfca0cd91cdf31e94eff121f997b78ff022224c"
val approvedLibDir = file("src/main/jniLibs/arm64-v8a")
val approvedLibraries = mapOf(
    "libelementum.so" to Triple("elementum.so", 28719993L,
        "05ed9b64e4ad3bf882cea73db834316fc8b897d0"),
    "libc++_shared.so" to Triple("libc++_shared.so", 5973872L,
        "8d26b5f72fbfb5c1f16b068705361e818863e265"),
)

fun gitObjectSha1(file: File): String {
    val digest = MessageDigest.getInstance("SHA-1")
    digest.update("blob ${file.length()}\u0000".toByteArray(Charsets.UTF_8))
    file.inputStream().use { input ->
        val buf = ByteArray(65536)
        while (true) {
            val n = input.read(buf)
            if (n < 0) break
            digest.update(buf, 0, n)
        }
    }
    return digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
}

val prepareApprovedNative by tasks.registering {
    doLast {
        approvedLibDir.mkdirs()
        approvedLibraries.forEach { (name, pin) ->
            val destination = File(approvedLibDir, name)
            if (!includeElementum) {
                if (destination.exists()) destination.delete()
                return@forEach
            }
            if (destination.exists() && destination.length() == pin.second &&
                gitObjectSha1(destination) == pin.third) return@forEach
            val temporary = File(approvedLibDir, "$name.download")
            try {
                if (temporary.exists()) temporary.delete()
                val url = "https://raw.githubusercontent.com/elgatito/elementum-binaries/" +
                    "$pinnedCommit/android_arm64/${pin.first}"
                URL(url).openConnection().apply {
                    connectTimeout = 25000
                    readTimeout = 60000
                }.getInputStream().use { input ->
                    temporary.outputStream().use { output -> input.copyTo(output) }
                }
                if (temporary.length() != pin.second ||
                    gitObjectSha1(temporary) != pin.third) {
                    throw GradleException("Integridade nativa inválida: $name")
                }
                if (destination.exists()) destination.delete()
                temporary.copyTo(destination, overwrite = true)
                if (gitObjectSha1(destination) != pin.third) {
                    throw GradleException("Verificação após cópia falhou: $name")
                }
            } finally {
                if (temporary.exists()) temporary.delete()
            }
        }
    }
}

tasks.named("preBuild") {
    dependsOn(prepareApprovedNative)
}
