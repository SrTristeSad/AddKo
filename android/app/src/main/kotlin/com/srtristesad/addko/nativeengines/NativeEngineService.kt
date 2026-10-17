package com.srtristesad.addko.nativeengines

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/** Uses a separate Android process to keep native crashes away from Flutter. */
class NativeEngineService : Service() {
    private var worker: Thread? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Motores nativos do AddKo",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.getStringExtra(EXTRA_ENGINE) != "elementum") {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        if (intent.action == ACTION_STOP) {
            thread(name = "AddKoEngine-Stop") {
                requestShutdown()
                try {
                    worker?.join(5000)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                }
                stopSelf(startId)
            }
        } else {
            startNative()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        requestShutdown()
        super.onDestroy()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        requestShutdown(500, 1000)
        stopSelf(startId)
    }

    private fun startNative() {
        if (worker?.isAlive == true) return
        if (!NativeEngineRegistry.available(this, "elementum")) {
            stopSelf()
            return
        }
        val runtime = try {
            ElementumConfig.prepare(this)
        } catch (error: Throwable) {
            error.printStackTrace()
            stopSelf()
            return
        }

        val notification = notification("Iniciando motor…")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        worker = thread(name = "AddKo-Elementum", isDaemon = false) {
            val code = try {
                NativeEngineBridge.start(runtime.log.absolutePath, runtime.args())
            } catch (error: Throwable) {
                error.printStackTrace()
                -999L
            }
            android.util.Log.i("AddKoEngine", "Engine returned $code")
            stopSelf()
        }
        getSystemService(NotificationManager::class.java).notify(
            NOTIFICATION_ID,
            notification("Motor nativo em execução"),
        )
    }

    private fun requestShutdown(connectMs: Int = 1000, readMs: Int = 1500) {
        try {
            val connection = URL("http://127.0.0.1:65220/shutdown")
                .openConnection() as HttpURLConnection
            try {
                connection.requestMethod = "GET"
                connection.instanceFollowRedirects = false
                connection.connectTimeout = connectMs
                connection.readTimeout = readMs
                connection.inputStream.use { it.readBytes() }
            } finally {
                connection.disconnect()
            }
        } catch (_: Throwable) {
            // Engine may still be starting or already offline.
        }
    }

    private fun notification(message: String): Notification {
        val stop = Intent(this, NativeEngineService::class.java).apply {
            action = ACTION_STOP
            putExtra(EXTRA_ENGINE, "elementum")
        }
        val stopAction = PendingIntent.getService(
            this, 1, stop,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val open = launch?.let {
            PendingIntent.getActivity(
                this, 2, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("AddKo — motor nativo")
            .setContentText(message)
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Parar", stopAction).build())
            .build()
    }

    companion object {
        const val ACTION_START = "com.srtristesad.addko.nativeengine.START"
        const val ACTION_STOP = "com.srtristesad.addko.nativeengine.STOP"
        const val EXTRA_ENGINE = "engine"
        private const val CHANNEL_ID = "addko_native_engine"
        private const val NOTIFICATION_ID = 65220
    }
}
