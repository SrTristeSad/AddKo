package com.srtristesad.addko

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.widget.TextView
import java.io.File
import java.util.zip.ZipFile

/**
 * Prepares the complete Kodi runtime before the isolated native process starts.
 *
 * This Activity is intentionally separate from the Flutter launcher. When Kodi
 * closes (normally or because its native process dies), this bootstrap finishes
 * and Android reveals the still-running Flutter AddKo underneath.
 */
open class KodiBootstrapActivity : Activity() {
    private lateinit var status: TextView
    private var coreStarted = false
    private var coreStartedAt = 0L

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        status = TextView(this).apply {
            text = "Preparando Kodi legado…"
            textSize = 22f
            setPadding(40, 40, 40, 40)
        }
        setContentView(status)

        val requestedAddon = intent.getStringExtra("addonId")
        val selfTest = intent.getBooleanExtra("selfTest", false)

        Thread {
            try {
                KodiProfile.prepare(applicationContext)
                prepareAssets()

                // These Java properties are process-local, so Main.java repeats
                // them inside :kodi before NativeActivity/JNI initialization.
                System.setProperty("xbmc.proploaded", "yes")
                System.setProperty("xbmc.data", KodiProfile.home(applicationContext).absolutePath)
                System.setProperty("xbmc.home", File(cacheDir, "apk").absolutePath)
                System.setProperty(
                    "xbmc.temp",
                    File(cacheDir, "kodi-temp").apply { mkdirs() }.absolutePath,
                )

                runOnUiThread {
                    status.text = if (requestedAddon == null) {
                        "Iniciando Kodi legado…"
                    } else {
                        "Abrindo addon no Kodi…"
                    }
                    val next = Intent(this, org.xbmc.kodi.Main::class.java)
                    requestedAddon?.let { next.putExtra("addko.addon_id", it) }
                    next.putExtra("addko.self_test", selfTest)
                    coreStarted = true
                    coreStartedAt = SystemClock.elapsedRealtime()
                    startActivity(next)
                }
            } catch (error: Throwable) {
                runOnUiThread {
                    status.text =
                        "Não foi possível preparar o Kodi legado:\n${error.javaClass.simpleName}: ${error.message}\n\n" +
                        "Pressione Voltar para continuar usando o AddKo."
                }
            }
        }.start()
    }

    override fun onResume() {
        super.onResume()
        if (!coreStarted) return

        val elapsed = SystemClock.elapsedRealtime() - coreStartedAt
        // onResume is called once before startActivity. A later resume means the
        // isolated Kodi Activity/process returned. Do not strand the user on an
        // error/bootstrap screen: restore the Flutter app that is still alive.
        if (elapsed > 750L) {
            finish()
        }
    }

    private fun prepareAssets() {
        val destination = File(cacheDir, "apk")
        val marker = File(destination, ".addko-core-complete")
        val version =
            "21.3-addko-isolated-1:${packageManager.getPackageInfo(packageName, 0).lastUpdateTime}"
        if (
            marker.isFile &&
                marker.readText() == version &&
                File(destination, "assets/system/addon-manifest.xml").isFile &&
                File(destination, "assets/python3.11/lib/python3.11/os.py").isFile
        ) {
            return
        }

        val pending = File(cacheDir, "kodi-extract-pending")
        pending.deleteRecursively()
        check(pending.mkdirs() || pending.isDirectory)
        val allowedRoot = pending.canonicalPath + File.separator

        ZipFile(applicationInfo.sourceDir).use { apk ->
            val entries = apk.entries()
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                // Flutter assets belong to the launcher, not the Kodi runtime.
                if (
                    !entry.name.startsWith("assets/") ||
                        entry.name.startsWith("assets/flutter_assets/")
                ) {
                    continue
                }
                val target = File(pending, entry.name).canonicalFile
                check(target.path.startsWith(allowedRoot)) { "Entrada de runtime inválida" }
                if (entry.isDirectory) {
                    target.mkdirs()
                } else {
                    target.parentFile!!.mkdirs()
                    apk.getInputStream(entry).use { input ->
                        target.outputStream().use { input.copyTo(it) }
                    }
                }
            }
        }

        check(File(pending, "assets/system/addon-manifest.xml").isFile)
        check(File(pending, "assets/python3.11/lib/python3.11/os.py").isFile)
        File(pending, ".addko-core-complete").writeText(version)
        check(!destination.exists() || destination.deleteRecursively())
        check(pending.renameTo(destination)) { "Falha ao concluir extração do Kodi" }
    }
}
