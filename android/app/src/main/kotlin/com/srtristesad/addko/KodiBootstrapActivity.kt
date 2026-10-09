package com.srtristesad.addko

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.widget.TextView
import java.io.File
import java.util.zip.ZipFile

/**
 * Prepares the complete Kodi runtime before the native process is started.
 *
 * The bootstrap intentionally stays alive underneath the :kodi activity. If the
 * native process dies during early startup, Android can return here instead of
 * killing the whole AddKo task with no useful feedback.
 */
open class KodiBootstrapActivity : Activity() {
    private lateinit var status: TextView
    private var coreStarted = false
    private var coreStartedAt = 0L

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        status = TextView(this).apply {
            text = "Preparando AddKo / Kodi 21.3…"
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
                // Kodi SetupEnv uses these Java properties and its own CPython 3.11.
                System.setProperty("xbmc.proploaded", "yes")
                System.setProperty("xbmc.data", KodiProfile.home(applicationContext).absolutePath)
                System.setProperty("xbmc.home", File(cacheDir, "apk").absolutePath)
                System.setProperty("xbmc.temp", File(cacheDir, "kodi-temp").apply { mkdirs() }.absolutePath)
                runOnUiThread {
                    status.text = "Iniciando o núcleo Kodi…"
                    val next = Intent(this, org.xbmc.kodi.Main::class.java)
                    requestedAddon?.let { next.putExtra("addko.addon_id", it) }
                    next.putExtra("addko.self_test", selfTest)
                    coreStarted = true
                    coreStartedAt = SystemClock.elapsedRealtime()
                    startActivity(next)
                    // Do not finish: this process is the crash-safe parent of :kodi.
                }
            } catch (error: Throwable) {
                runOnUiThread {
                    status.text = "Não foi possível preparar o AddKo:\n${error.javaClass.simpleName}: ${error.message}"
                }
            }
        }.start()
    }

    override fun onResume() {
        super.onResume()
        if (coreStarted) {
            val elapsed = SystemClock.elapsedRealtime() - coreStartedAt
            // onResume is also called once before startActivity; only report a return
            // after the child had time to start.
            if (elapsed > 750L) {
                status.text = "O núcleo Kodi foi encerrado.\n\n" +
                    "Se isso aconteceu sozinho, conecte o aparelho por USB e execute " +
                    "COLETAR_CRASH_ADDKO.bat no PC para gerar o relatório exato.\n\n" +
                    "Você pode fechar o AddKo e tentar novamente."
            }
        }
    }

    private fun prepareAssets() {
        val destination = File(cacheDir, "apk")
        val marker = File(destination, ".addko-core-complete")
        val version = "21.3-addko-embedded-3:${packageManager.getPackageInfo(packageName, 0).lastUpdateTime}"
        if (marker.isFile && marker.readText() == version &&
            File(destination, "assets/system/addon-manifest.xml").isFile &&
            File(destination, "assets/python3.11/lib/python3.11/os.py").isFile) return
        val pending = File(cacheDir, "kodi-extract-pending")
        pending.deleteRecursively()
        check(pending.mkdirs() || pending.isDirectory)
        val allowedRoot = pending.canonicalPath + File.separator
        ZipFile(applicationInfo.sourceDir).use { apk ->
            val entries = apk.entries()
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                // Flutter's assets and the legacy Python shims do not belong in Kodi's runtime.
                if (!entry.name.startsWith("assets/") || entry.name.startsWith("assets/flutter_assets/")) continue
                val target = File(pending, entry.name).canonicalFile
                check(target.path.startsWith(allowedRoot)) { "Entrada de runtime inválida" }
                if (entry.isDirectory) target.mkdirs()
                else {
                    target.parentFile!!.mkdirs()
                    apk.getInputStream(entry).use { input -> target.outputStream().use { input.copyTo(it) } }
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
