package com.srtristesad.addko.nativeengines

import android.content.Context
import android.content.Intent
import android.os.Build
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** Only fixed, signed APK-bundled engines. Addons cannot specify a library path. */
internal object NativeEngineRegistry {
    private const val ELEMENTUM = "elementum"

    fun supports(engine: String): Boolean = engine == ELEMENTUM

    fun available(context: Context, engine: String): Boolean {
        if (!supports(engine)) return false
        val dir = File(context.applicationInfo.nativeLibraryDir)
        return File(dir, "libelementum.so").isFile &&
            File(dir, "libaddko_engine_bridge.so").isFile
    }

    fun start(context: Context, engine: String) {
        require(supports(engine))
        val intent = Intent(context, NativeEngineService::class.java).apply {
            action = NativeEngineService.ACTION_START
            putExtra(NativeEngineService.EXTRA_ENGINE, engine)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    fun stop(context: Context, engine: String) {
        require(supports(engine))
        val intent = Intent(context, NativeEngineService::class.java).apply {
            action = NativeEngineService.ACTION_STOP
            putExtra(NativeEngineService.EXTRA_ENGINE, engine)
        }
        context.startService(intent)
    }

    fun status(engine: String): Map<String, String> {
        if (!supports(engine)) return mapOf("state" to "unsupported")
        val active = try {
            val connection = URL("http://127.0.0.1:65220/torrents/list")
                .openConnection() as HttpURLConnection
            try {
                connection.requestMethod = "GET"
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 1000
                connection.readTimeout = 1000
                connection.responseCode == 200
            } finally {
                connection.disconnect()
            }
        } catch (_: Throwable) {
            false
        }
        return mapOf("state" to if (active) "running" else "stopped")
    }
}
