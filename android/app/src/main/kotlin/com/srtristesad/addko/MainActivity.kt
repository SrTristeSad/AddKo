package com.srtristesad.addko

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Stable AddKo shell.
 *
 * Flutter runs in the normal application process. The legacy Kodi runtime is
 * launched only on demand through [KodiBootstrapActivity] and then continues in
 * the isolated :kodi process. A Kodi/native crash must therefore never take the
 * Store, settings or Plugin v2 frontend down with it.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "addko/kodi_core"
        private const val TAG = "AddKo"
        private const val EXTRA_CI_SELF_TEST = "addko.ci_self_test"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        maybeLaunchCiSelfTest(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        maybeLaunchCiSelfTest(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.renderer.addIsDisplayingFlutterUiListener(
            object : FlutterUiDisplayListener {
                override fun onFlutterUiDisplayed() {
                    Log.i(TAG, "Flutter first frame displayed")
                }

                override fun onFlutterUiNoLongerDisplayed() = Unit
            },
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "profile" -> prepareProfile(result)
                    "status" -> result.success(coreStatus())
                    "storage" -> openStorageSettings(result)
                    "openLegacyAddon" -> {
                        val addonId = call.argument<String>("addonId")?.trim()
                        if (addonId.isNullOrEmpty()) {
                            result.error("invalid_addon", "ID do addon ausente.", null)
                        } else {
                            launchKodi(addonId = addonId, selfTest = false, result = result)
                        }
                    }
                    "openKodi" -> {
                        val addonId = call.argument<String>("addonId")?.trim()?.takeIf { it.isNotEmpty() }
                        val selfTest = call.argument<Boolean>("selfTest") ?: false
                        launchKodi(addonId = addonId, selfTest = selfTest, result = result)
                    }
                    // Kept as a compatibility no-op for older Dart code. Renderer
                    // ownership no longer switches inside one Activity.
                    "legacyGui" -> result.success(null)
                    "rpc" -> result.error(
                        "core_isolated",
                        "O Kodi legado roda em um processo isolado. RPC direto não está disponível na interface Flutter.",
                        null,
                    )
                    else -> result.notImplemented()
                }
            }
        Log.i(TAG, "Flutter launcher channel ready")
    }

    private fun maybeLaunchCiSelfTest(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_CI_SELF_TEST, false) != true) return
        // Consume the flag so lifecycle re-entry cannot recursively reopen Kodi.
        intent.removeExtra(EXTRA_CI_SELF_TEST)
        launchKodiInternal(
            addonId = null,
            selfTest = true,
            onSuccess = { Log.i(TAG, "Isolated Kodi self-test launched") },
            onError = { error -> Log.e(TAG, "Failed to launch isolated Kodi self-test", error) },
        )
    }

    private fun prepareProfile(result: MethodChannel.Result) {
        Thread {
            try {
                val paths = KodiProfile.prepare(applicationContext)
                runOnUiThread { result.success(paths) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error("profile_failed", error.message ?: error.toString(), null)
                }
            }
        }.start()
    }

    private fun launchKodi(
        addonId: String?,
        selfTest: Boolean,
        result: MethodChannel.Result,
    ) {
        launchKodiInternal(
            addonId = addonId,
            selfTest = selfTest,
            onSuccess = { result.success(null) },
            onError = { error ->
                result.error("kodi_launch_failed", error.message ?: error.toString(), null)
            },
        )
    }

    private fun launchKodiInternal(
        addonId: String?,
        selfTest: Boolean,
        onSuccess: () -> Unit,
        onError: (Throwable) -> Unit,
    ) {
        Thread {
            try {
                // The Store writes addons directly into this shared app profile.
                // Prepare it before the isolated Kodi process starts so Kodi sees
                // a complete directory tree from its first scan.
                KodiProfile.prepare(applicationContext)
                runOnUiThread {
                    try {
                        val intent = Intent(this, KodiBootstrapActivity::class.java).apply {
                            addonId?.let { putExtra("addonId", it) }
                            putExtra("selfTest", selfTest)
                        }
                        startActivity(intent)
                        onSuccess()
                    } catch (error: Throwable) {
                        onError(error)
                    }
                }
            } catch (error: Throwable) {
                runOnUiThread { onError(error) }
            }
        }.start()
    }

    private fun coreStatus(): Map<String, Any?> = mapOf(
        "bundled" to File(applicationInfo.nativeLibraryDir, "libkodi.so").isFile,
        "ready" to true,
        "version" to "21.3-Omega",
        "embedded" to false,
        "isolated" to true,
        "device" to Build.MODEL,
        "androidSdk" to Build.VERSION.SDK_INT,
        "abis" to Build.SUPPORTED_ABIS.toList(),
        "error" to null,
    )

    private fun openStorageSettings(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                val appSettings = Intent(
                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:$packageName"),
                )
                if (appSettings.resolveActivity(packageManager) != null) {
                    startActivity(appSettings)
                } else {
                    startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                }
            } else {
                requestPermissions(
                    arrayOf(
                        Manifest.permission.READ_EXTERNAL_STORAGE,
                        Manifest.permission.WRITE_EXTERNAL_STORAGE,
                    ),
                    2103,
                )
            }
            result.success(null)
        } catch (error: Throwable) {
            result.error(
                "storage_settings",
                "Abra as permissões do AddKo nas configurações do Android: ${error.message}",
                null,
            )
        }
    }
}
