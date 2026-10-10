package com.srtristesad.addko

import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.RelativeLayout
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import org.xbmc.kodi.AddKoCoreBridge
import org.xbmc.kodi.Main
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * Compatibility hook created by Kodi's patched Main.java once its native surface
 * exists.
 *
 * IMPORTANT: this class no longer embeds Flutter inside Kodi. The real Flutter
 * frontend lives only in MainActivity, in the normal application process. This
 * hook only waits for Kodi JSON-RPC and opens the requested legacy addon.
 */
class AddKoFlutterHost(
    private val activity: Main,
    @Suppress("UNUSED_PARAMETER") layout: RelativeLayout,
) {
    companion object {
        private const val TAG = "AddKoLegacy"
        private val sequence = AtomicInteger(1000)
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var stopped = false
    @Volatile private var rpcReady = false

    init {
        handleIntent(activity.intent)
    }

    private fun handleIntent(intent: Intent) {
        val addonId = intent.getStringExtra("addko.addon_id")?.trim()
            ?.takeIf { it.isNotEmpty() }
        val selfTest = intent.getBooleanExtra("addko.self_test", false)
        if (addonId == null && !selfTest) return

        // Consume extras so lifecycle redelivery does not reopen the same addon.
        intent.removeExtra("addko.addon_id")
        intent.removeExtra("addko.self_test")

        worker.execute {
            try {
                ensureKodiRpc()
                if (stopped) return@execute

                if (selfTest) {
                    runSelfTest()
                }
                if (addonId != null) {
                    openAddon(addonId)
                }
            } catch (error: Throwable) {
                Log.e(TAG, "Falha ao preparar addon legado", error)
                showError(
                    "Kodi iniciou, mas não conseguiu abrir o addon.\n" +
                        (error.message ?: error.javaClass.simpleName),
                )
            }
        }
    }

    private fun ensureKodiRpc() {
        if (rpcReady) return
        var lastError: Throwable? = null
        repeat(120) {
            if (stopped) return
            try {
                val response = rpc("JSONRPC.Version")
                if (response.has("result")) {
                    rpcReady = true
                    Log.i(TAG, "Kodi JSON-RPC pronto")
                    return
                }
            } catch (error: Throwable) {
                lastError = error
            }
            TimeUnit.MILLISECONDS.sleep(500)
        }
        throw IllegalStateException(
            "Kodi JSON-RPC não ficou pronto em 60 segundos.",
            lastError,
        )
    }

    private fun runSelfTest() {
        try {
            rpc(
                "Addons.ExecuteAddon",
                JSONObject()
                    .put("addonid", "script.addko.bridge")
                    .put("params", JSONArray().put("selftest").put("")),
            )
        } catch (error: Throwable) {
            Log.w(TAG, "Self-test bridge indisponível", error)
        }
    }

    private fun openAddon(addonId: String) {
        // The bridge asks Kodi to rescan addons installed by AddKo's Store. It is
        // optional: a normal Kodi startup scan may already have discovered them.
        try {
            rpc(
                "Addons.ExecuteAddon",
                JSONObject()
                    .put("addonid", "script.addko.bridge")
                    .put("params", JSONArray().put("refresh").put("")),
            )
        } catch (error: Throwable) {
            Log.w(TAG, "Refresh bridge não respondeu; continuando com scan do Kodi", error)
        }

        var lastError: Throwable? = null
        repeat(60) {
            if (stopped) return
            try {
                val details = rpc(
                    "Addons.GetAddonDetails",
                    JSONObject()
                        .put("addonid", addonId)
                        .put("properties", JSONArray().put("enabled")),
                )
                if (details.has("result")) {
                    rpc(
                        "Addons.SetAddonEnabled",
                        JSONObject().put("addonid", addonId).put("enabled", true),
                    )
                    val opened = rpc(
                        "GUI.ActivateWindow",
                        JSONObject()
                            .put("window", "videos")
                            .put(
                                "parameters",
                                JSONArray().put("plugin://$addonId/").put("return"),
                            ),
                    )
                    if (opened.has("error")) {
                        throw IllegalStateException(opened.getJSONObject("error").toString())
                    }
                    Log.i(TAG, "Addon legado aberto: $addonId")
                    return
                }
            } catch (error: Throwable) {
                lastError = error
            }
            TimeUnit.MILLISECONDS.sleep(500)
        }

        throw IllegalStateException(
            "O Kodi não encontrou ou não conseguiu habilitar $addonId.",
            lastError,
        )
    }

    private fun rpc(method: String, params: JSONObject? = null): JSONObject {
        val id = sequence.incrementAndGet()
        val request = JSONObject()
            .put("jsonrpc", "2.0")
            .put("id", id)
            .put("method", method)
        if (params != null) request.put("params", params)

        val response = JSONObject(AddKoCoreBridge.requestJSON(request.toString()))
        if (response.optInt("id", id) != id) {
            throw IllegalStateException("Resposta JSON-RPC inválida para $method")
        }
        return response
    }

    private fun showError(message: String) {
        mainHandler.post {
            if (!stopped && !activity.isFinishing) {
                Toast.makeText(activity, message, Toast.LENGTH_LONG).show()
            }
        }
    }

    // Lifecycle callbacks kept because Kodi's Main.java already calls them.
    fun onStart() = Unit
    fun onResume() = Unit
    fun onPause() = Unit
    fun onStop() = Unit
    fun onBackPressed(): Boolean = false

    fun onNewIntent(intent: Intent) {
        handleIntent(intent)
    }

    fun onActivityResult(
        @Suppress("UNUSED_PARAMETER") code: Int,
        @Suppress("UNUSED_PARAMETER") result: Int,
        @Suppress("UNUSED_PARAMETER") data: Intent?,
    ) = Unit

    fun onRequestPermissionsResult(
        @Suppress("UNUSED_PARAMETER") code: Int,
        @Suppress("UNUSED_PARAMETER") permissions: Array<String>,
        @Suppress("UNUSED_PARAMETER") results: IntArray,
    ) = Unit

    fun destroy() {
        if (stopped) return
        stopped = true
        worker.shutdownNow()
    }
}
