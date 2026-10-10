package com.srtristesad.addko

import android.content.Intent
import android.os.Build
import android.net.Uri
import android.provider.Settings
import android.Manifest
import android.app.Activity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class KodiCoreChannel(
    private val activity: Activity,
    private val rpc: (String, MethodChannel.Result) -> Unit,
    private val status: () -> Map<String, Any?>,
    private val setLegacyGui: (Boolean) -> Unit,
) {
    private val applicationContext get() = activity.applicationContext
    private val packageManager get() = activity.packageManager
    private val packageName get() = activity.packageName
    private fun runOnUiThread(action: () -> Unit) = activity.runOnUiThread(action)
    private fun startActivity(intent: Intent) = activity.startActivity(intent)

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "addko/kodi_core").setMethodCallHandler { call, result ->
            when (call.method) {
                "storage" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 30) {
                            val appSettings = Intent(
                                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            if (appSettings.resolveActivity(packageManager) != null) startActivity(appSettings)
                            else startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                        } else {
                            activity.requestPermissions(
                                arrayOf(
                                    Manifest.permission.READ_EXTERNAL_STORAGE,
                                    Manifest.permission.WRITE_EXTERNAL_STORAGE
                                ),
                                2103
                            )
                        }
                        result.success(null)
                    } catch (error: Exception) {
                        result.error(
                            "storage_settings",
                            "Abra as permissões do AddKo nas configurações do Android: ${error.message}",
                            null
                        )
                    }
                }

                "profile" -> Thread {
                    try {
                        val paths = KodiProfile.prepare(applicationContext)
                        runOnUiThread { result.success(paths) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("profile_failed", error.message, null) }
                    }
                }.start()

                "status" -> result.success(status())

                "rpc" -> {
                    val raw = call.argument<String>("request")
                    if (raw == null) result.error("invalid_rpc", "Comando ausente", null)
                    else rpc(raw, result)
                }

                "legacyGui" -> {
                    val enabled = call.argument<Boolean>("enabled")
                    if (enabled == null) {
                        result.error("invalid_legacy_gui", "Estado da GUI legada ausente", null)
                    } else {
                        setLegacyGui(enabled)
                        result.success(null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
