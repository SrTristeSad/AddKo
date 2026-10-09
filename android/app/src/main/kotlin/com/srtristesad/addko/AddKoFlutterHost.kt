package com.srtristesad.addko

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.util.Log
import android.view.View
import android.widget.RelativeLayout
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import io.flutter.embedding.android.ExclusiveAppComponent
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformPlugin
import org.json.JSONObject
import org.xbmc.kodi.AddKoCoreBridge
import org.xbmc.kodi.Main
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** One activity: Kodi owns the native renderer/player; Flutter owns the frontend. */
class AddKoFlutterHost(private val activity: Main, layout: RelativeLayout) :
    ExclusiveAppComponent<Activity>, LifecycleOwner {
    override val lifecycle = LifecycleRegistry(this)
    private val handler = Handler(Looper.getMainLooper())
    private val engine = FlutterEngine(activity)
    private val texture = FlutterTextureView(activity).apply { isOpaque = false }
    private val view = FlutterView(activity, texture)
    private val platform = PlatformPlugin(activity, engine.platformChannel)
    private val workers = Executors.newFixedThreadPool(3)
    private val monitor = Executors.newSingleThreadScheduledExecutor()
    @Volatile private var ready = false
    @Volatile private var stopped = false
    @Volatile private var lastError: String? = null
    private var nativeDialog = false
    private val channel: KodiCoreChannel

    init {
        lifecycle.currentState = Lifecycle.State.CREATED
        engine.activityControlSurface.attachToActivity(this, lifecycle)
        view.attachToFlutterEngine(engine)
        view.elevation = 20f
        layout.addView(view, RelativeLayout.LayoutParams(-1, -1))
        view.requestFocus()
        // NativeActivity's input queue consumes events before Flutter sees them.
        // The native queue is restored only while an addon dialog is displayed.
        activity.window.takeInputQueue(null)
        channel = KodiCoreChannel(activity, ::request, ::status)
        channel.register(engine)
        engine.renderer.addIsDisplayingFlutterUiListener(object : FlutterUiDisplayListener {
            override fun onFlutterUiDisplayed() { Log.i("AddKo", "Flutter first frame displayed") }
            override fun onFlutterUiNoLongerDisplayed() {}
        })
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        monitor.scheduleWithFixedDelay(::poll, 500, 600, TimeUnit.MILLISECONDS)
    }

    private fun status(): Map<String, Any?> = mapOf(
        "bundled" to File(activity.applicationInfo.nativeLibraryDir, "libkodi.so").isFile,
        "ready" to ready, "version" to "21.3-Omega", "embedded" to true,
        "device" to Build.MODEL, "androidSdk" to Build.VERSION.SDK_INT,
        "abis" to Build.SUPPORTED_ABIS.toList(),
        "error" to lastError,
        "report" to File(KodiProfile.root(activity), "userdata/addko-core-health.json")
            .takeIf { it.isFile }?.readText(),
        "log" to File(activity.cacheDir, "kodi-temp/kodi.log")
            .takeIf { it.isFile }?.let { file ->
                RandomAccessFile(file, "r").use { reader ->
                    val size = minOf(reader.length(), 24000L).toInt()
                    reader.seek(reader.length() - size)
                    val bytes = ByteArray(size)
                    reader.readFully(bytes)
                    String(bytes, Charsets.UTF_8)
                }
            }
    )

    private fun request(raw: String, result: MethodChannel.Result) {
        if (stopped || !ready) {
            result.error("core_not_ready", lastError ?: "O núcleo está inicializando. Aguarde ou consulte o diagnóstico.", null)
            return
        }
        workers.execute {
            try {
                val response = AddKoCoreBridge.requestJSON(raw)
                handler.post { result.success(response) }
            } catch (error: Throwable) {
                handler.post { result.error("native_rpc", error.toString(), null) }
            }
        }
    }

    private fun poll() {
        if (stopped || activity.mMainView?.mIsCreated != true) return
        try {
            if (!ready) {
                val version = JSONObject(AddKoCoreBridge.requestJSON("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"JSONRPC.Version\"}"))
                if (!version.has("result")) return
                ready = true
                lastError = null
                Log.i("AddKo", "Kodi JSON-RPC ready")
            }
            val state = JSONObject(AddKoCoreBridge.requestJSON("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"GUI.GetProperties\",\"params\":{\"properties\":[\"currentwindow\"]}}"))
            val id = state.optJSONObject("result")?.optJSONObject("currentwindow")?.optInt("id", -1) ?: -1
            // Stock Kodi addon dialogs remain native; menus and video controls
            // belong to AddKo. Native WindowXML dialogs are also accessible.
            val show = id >= 10000 && id !in setOf(10000, 10025, 10502, 12005, 12006, 12997, 12999)
            handler.post {
                if (!stopped && show != nativeDialog) {
                    nativeDialog = show
                    view.visibility = if (show) View.INVISIBLE else View.VISIBLE
                    activity.window.takeInputQueue(if (show) activity else null)
                    if (!show) view.requestFocus()
                }
            }
        } catch (error: Throwable) {
            lastError = error.toString()
        }
    }

    override fun getAppComponent(): Activity = activity
    override fun detachFromFlutterEngine() { destroy() }
    fun onStart() { lifecycle.currentState = Lifecycle.State.STARTED }
    fun onResume() {
        lifecycle.currentState = Lifecycle.State.RESUMED
        engine.lifecycleChannel.appIsResumed()
        platform.updateSystemUiOverlays()
    }
    fun onPause() {
        engine.lifecycleChannel.appIsInactive()
        lifecycle.currentState = Lifecycle.State.STARTED
    }
    fun onStop() {
        engine.lifecycleChannel.appIsPaused()
        lifecycle.currentState = Lifecycle.State.CREATED
    }
    fun onBackPressed(): Boolean {
        if (nativeDialog) return false
        engine.navigationChannel.popRoute()
        return true
    }
    fun onNewIntent(intent: Intent) { engine.activityControlSurface.onNewIntent(intent) }
    fun onActivityResult(code: Int, result: Int, data: Intent?) {
        engine.activityControlSurface.onActivityResult(code, result, data)
    }
    fun onRequestPermissionsResult(code: Int, permissions: Array<String>, results: IntArray) {
        engine.activityControlSurface.onRequestPermissionsResult(code, permissions, results)
    }
    fun destroy() {
        if (stopped) return
        stopped = true
        monitor.shutdownNow()
        workers.shutdownNow()
        engine.lifecycleChannel.appIsDetached()
        view.detachFromFlutterEngine()
        engine.activityControlSurface.detachFromActivity()
        platform.destroy()
        lifecycle.currentState = Lifecycle.State.DESTROYED
        engine.destroy()
    }
}
