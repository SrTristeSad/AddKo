package com.srtristesad.addko

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "addko/system"
        private const val PICK_ADDKO_REQUEST = 5101
        private const val MAX_PACKAGE_BYTES = 16L * 1024L * 1024L
        private val BLOCKED_URI_SCHEMES = setOf(
            "file",
            "content",
            "data",
            "javascript",
            "intent",
        )
    }

    private var pendingPickerResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickAddko" -> openAddkoPicker(result)
                    "openUri" -> openExternalUri(call.argument<String>("uri"), result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun openExternalUri(raw: String?, result: MethodChannel.Result) {
        val uri = try {
            raw?.trim()?.takeIf { it.isNotEmpty() }?.let(Uri::parse)
        } catch (_: Throwable) {
            null
        }

        val scheme = uri?.scheme?.lowercase()
        if (uri == null || scheme.isNullOrBlank() || scheme in BLOCKED_URI_SCHEMES) {
            result.error("invalid_uri", "URI externo inválido ou não permitido.", null)
            return
        }

        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
        }

        try {
            startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.success(false)
        } catch (error: Throwable) {
            result.error(
                "open_uri_failed",
                error.message ?: error.javaClass.simpleName,
                null,
            )
        }
    }

    private fun openAddkoPicker(result: MethodChannel.Result) {
        if (pendingPickerResult != null) {
            result.error("picker_busy", "Já existe um seletor de pacote aberto.", null)
            return
        }

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }

        pendingPickerResult = result
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(
                Intent.createChooser(intent, "Escolha um pacote .addko"),
                PICK_ADDKO_REQUEST,
            )
        } catch (error: Throwable) {
            pendingPickerResult = null
            result.error("picker_failed", error.message ?: error.javaClass.simpleName, null)
        }
    }

    @Deprecated("Deprecated in Android; retained for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_ADDKO_REQUEST) return

        val result = pendingPickerResult ?: return
        pendingPickerResult = null

        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            result.error("picker_empty", "Nenhum arquivo foi retornado pelo Android.", null)
            return
        }

        var output: File? = null
        try {
            val displayName = displayName(uri)
            if (displayName != null && !displayName.lowercase().endsWith(".addko")) {
                result.error(
                    "invalid_extension",
                    "O arquivo selecionado não possui a extensão .addko.",
                    null,
                )
                return
            }

            val importDir = File(cacheDir, "addko-imports").apply { mkdirs() }
            output = File(importDir, "selected-${System.nanoTime()}.addko")

            contentResolver.openInputStream(uri).use { input ->
                if (input == null) {
                    throw IllegalStateException("Não foi possível abrir o arquivo selecionado.")
                }

                FileOutputStream(output).use { stream ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_PACKAGE_BYTES) {
                            throw IllegalArgumentException(
                                "Pacote .addko excede o limite de 16 MiB.",
                            )
                        }
                        stream.write(buffer, 0, read)
                    }
                    stream.fd.sync()
                }
            }

            result.success(output.absolutePath)
        } catch (error: Throwable) {
            try {
                output?.takeIf { it.exists() }?.delete()
            } catch (_: Throwable) {
                // Cache cleanup is best-effort; the platform may reclaim it later.
            }
            result.error(
                "picker_read_failed",
                error.message ?: error.javaClass.simpleName,
                null,
            )
        }
    }

    private fun displayName(uri: Uri): String? {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && !cursor.isNull(index)) {
                    return cursor.getString(index)
                }
            }
        }
        return null
    }

    override fun onDestroy() {
        pendingPickerResult?.error(
            "activity_destroyed",
            "A tela foi encerrada antes de concluir a seleção do pacote.",
            null,
        )
        pendingPickerResult = null
        super.onDestroy()
    }
}
