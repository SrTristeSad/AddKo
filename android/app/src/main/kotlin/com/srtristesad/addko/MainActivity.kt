package com.srtristesad.addko

import android.content.Context
import android.os.Build
import android.system.Os
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipInputStream

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
        private const val RUNTIME_REVISION = "4"
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
        val stdlib = File(prefix, "lib/python3.14")
        val marker = File(runtimeRoot, ".complete")

        val validExistingRuntime = marker.isFile &&
            marker.readText().trim() == runtimeTag &&
            File(stdlib, "zipfile/_path/__init__.py").isFile

        if (!validExistingRuntime) {
            if (runtimeRoot.exists() && !runtimeRoot.deleteRecursively()) {
                throw IllegalStateException("Não foi possível limpar $runtimeRoot")
            }
            if (!runtimeRoot.mkdirs() && !runtimeRoot.isDirectory) {
                throw IllegalStateException("Não foi possível criar $runtimeRoot")
            }

            val stdlibAsset = "addko_python/$VERSION/$abi/stdlib.zip"
            extractZipAsset(stdlibAsset, stdlib)

            val zipfilePath = File(stdlib, "zipfile/_path/__init__.py")
            if (!zipfilePath.isFile) {
                runtimeRoot.deleteRecursively()
                throw IllegalStateException(
                    "Runtime CPython incompleto após extrair stdlib.zip: $zipfilePath"
                )
            }

            marker.writeText(runtimeTag)
            cleanupOldRuntimeRevisions(runtimeTag)
        }

        if (!stdlib.isDirectory) {
            throw IllegalStateException("Biblioteca padrão do Python não foi extraída: $stdlib")
        }

        val zipfilePath = File(stdlib, "zipfile/_path/__init__.py")
        if (!zipfilePath.isFile) {
            throw IllegalStateException(
                "Runtime CPython incompleto: zipfile._path não foi extraído ($zipfilePath)"
            )
        }

        Os.setenv("TMPDIR", context.cacheDir.absolutePath, true)

        return PythonRuntimeInfo(prefix, abi, VERSION)
    }

    private fun extractZipAsset(assetPath: String, destination: File) {
        if (destination.exists() && !destination.deleteRecursively()) {
            throw IllegalStateException("Não foi possível limpar $destination")
        }
        if (!destination.mkdirs() && !destination.isDirectory) {
            throw IllegalStateException("Não foi possível criar $destination")
        }

        val destinationRoot = destination.canonicalFile
        var extractedFiles = 0

        context.assets.open(assetPath).use { input ->
            ZipInputStream(input.buffered()).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    val target = File(destinationRoot, entry.name).canonicalFile
                    val rootPath = destinationRoot.path + File.separator
                    if (target != destinationRoot && !target.path.startsWith(rootPath)) {
                        throw IllegalStateException("Entrada insegura em $assetPath: ${entry.name}")
                    }

                    if (entry.isDirectory) {
                        if (!target.mkdirs() && !target.isDirectory) {
                            throw IllegalStateException("Não foi possível criar $target")
                        }
                    } else {
                        target.parentFile?.let { parent ->
                            if (!parent.mkdirs() && !parent.isDirectory) {
                                throw IllegalStateException("Não foi possível criar $parent")
                            }
                        }
                        FileOutputStream(target).use { output ->
                            zip.copyTo(output)
                        }
                        extractedFiles += 1
                    }
                    zip.closeEntry()
                }
            }
        }

        if (extractedFiles == 0) {
            throw IllegalStateException("Asset CPython vazio ou inválido: $assetPath")
        }
    }

    private fun cleanupOldRuntimeRevisions(currentTag: String) {
        val pythonRoot = File(context.filesDir, "addko-python")
        val current = File(pythonRoot, currentTag).canonicalFile
        pythonRoot.listFiles()?.forEach { candidate ->
            try {
                if (candidate.canonicalFile != current) {
                    candidate.deleteRecursively()
                }
            } catch (_: Throwable) {
                // Cleanup is best-effort and must never invalidate a working runtime.
            }
        }
    }
}
