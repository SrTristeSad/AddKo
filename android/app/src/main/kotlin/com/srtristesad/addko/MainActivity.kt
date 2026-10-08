package com.srtristesad.addko

import android.content.Context
import android.os.Build
import android.system.Os
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException

class MainActivity : FlutterActivity() {
    companion object {
        private const val PYTHON_CHANNEL = "addko/python_runtime"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PYTHON_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> {
                        Thread {
                            try {
                                val info = PythonRuntimeInstaller(applicationContext).prepare()
                                runOnUiThread {
                                    result.success(
                                        mapOf(
                                            "home" to info.home.absolutePath,
                                            "abi" to info.abi,
                                            "version" to info.version,
                                        )
                                    )
                                }
                            } catch (error: Throwable) {
                                runOnUiThread {
                                    result.error(
                                        "python_runtime_prepare_failed",
                                        error.message ?: error.javaClass.simpleName,
                                        null,
                                    )
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

private data class PythonRuntimeInfo(
    val home: File,
    val abi: String,
    val version: String,
)

private class PythonRuntimeInstaller(private val context: Context) {
    companion object {
        private const val VERSION = "3.14.8"
        // Bump this whenever the stdlib/assets packaged with the same CPython
        // version change. Otherwise an app update would keep using the runtime
        // extracted by an older APK from Android's private files directory.
        private const val RUNTIME_REVISION = "3"
        private val SUPPORTED_ABIS = setOf("arm64-v8a", "x86_64")
    }

    @Synchronized
    fun prepare(): PythonRuntimeInfo {
        val abi = Build.SUPPORTED_ABIS.firstOrNull { it in SUPPORTED_ABIS }
            ?: throw IllegalStateException(
                "ABI Android não suportada pelo CPython embarcado: " +
                    Build.SUPPORTED_ABIS.joinToString()
            )

        val runtimeTag = "$VERSION-r$RUNTIME_REVISION"
        val runtimeRoot = File(context.filesDir, "addko-python/$runtimeTag/$abi")
        val prefix = File(runtimeRoot, "prefix")
        val marker = File(runtimeRoot, ".complete")

        if (!marker.exists() || marker.readText().trim() != runtimeTag) {
            if (runtimeRoot.exists() && !runtimeRoot.deleteRecursively()) {
                throw IllegalStateException("Não foi possível limpar $runtimeRoot")
            }
            runtimeRoot.mkdirs()

            val assetRoot = "addko_python/$VERSION/$abi/prefix"
            extractAssetTree(assetRoot, prefix)
            marker.writeText(runtimeTag)
        }

        val stdlib = File(prefix, "lib/python3.14")
        if (!stdlib.isDirectory) {
            throw IllegalStateException("Biblioteca padrão do Python não foi extraída: $stdlib")
        }

        val zipfilePath = File(stdlib, "zipfile/_path/__init__.py")
        if (!zipfilePath.isFile) {
            throw IllegalStateException(
                "Runtime CPython incompleto: zipfile._path não foi extraído ($zipfilePath)"
            )
        }

        // CPython on Android consults TMPDIR. Android only sets it automatically on
        // recent releases, so provide it on every supported version.
        Os.setenv("TMPDIR", context.cacheDir.absolutePath, true)

        return PythonRuntimeInfo(prefix, abi, VERSION)
    }

    private fun extractAssetTree(path: String, target: File) {
        val children = context.assets.list(path)
            ?: throw IllegalStateException("Não foi possível listar asset $path")

        if (children.isNotEmpty()) {
            if (!target.exists() && !target.mkdirs()) {
                throw IllegalStateException("Não foi possível criar $target")
            }
            for (child in children) {
                extractAssetTree("$path/$child", File(target, restoreName(child)))
            }
            return
        }

        try {
            context.assets.open(path).use { input ->
                target.parentFile?.mkdirs()
                target.outputStream().use { output -> input.copyTo(output) }
            }
        } catch (error: FileNotFoundException) {
            throw IllegalStateException("Asset do CPython ausente: $path", error)
        }
    }

    // The staging script mirrors CPython's official Android workaround: files
    // ending in .gz or '-' receive an extra trailing dash before APK packaging.
    private fun restoreName(name: String): String =
        if (name.endsWith("-")) name.dropLast(1) else name
}
