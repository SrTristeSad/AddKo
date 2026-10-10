package com.srtristesad.addko

import android.content.Context
import java.io.File

object KodiProfile {
    fun home(context: Context) = File(context.filesDir, "kodi-profile")
    fun root(context: Context) = File(home(context), ".kodi")

    @Synchronized fun prepare(context: Context): Map<String, String> {
        val root = root(context)
        val addons = File(root, "addons")
        val data = File(root, "userdata/addon_data")
        addons.mkdirs()
        data.mkdirs()
        val marker = File(root, ".addko-migrated-v1")
        if (!marker.exists()) {
            migrateChildren(File(context.filesDir, "addons"), addons)
            migrateChildren(File(context.filesDir, "addon_data"), data)
            marker.writeText("complete")
        }
        return mapOf("home" to home(context).absolutePath, "addons" to addons.absolutePath,
            "addonData" to data.absolutePath, "userdata" to File(root, "userdata").absolutePath)
    }

    private fun migrateChildren(source: File, destination: File) {
        source.listFiles()?.filter { it.isDirectory }?.forEach { child ->
            val target = File(destination, child.name)
            if (!target.exists()) {
                val staging = File(destination, ".migration-${child.name}")
                if (staging.exists()) staging.deleteRecursively()
                copyTree(child, staging, source.canonicalFile)
                check(staging.renameTo(target)) { "Falha ao migrar ${child.name}" }
            }
        }
    }

    private fun copyTree(source: File, target: File, allowedRoot: File) {
        check(source.canonicalPath.startsWith(allowedRoot.path + File.separator)) { "Caminho de addon fora da origem" }
        if (source.isDirectory) {
            check(target.mkdirs() || target.isDirectory)
            source.listFiles()?.forEach { copyTree(it, File(target, it.name), allowedRoot) }
        } else {
            source.inputStream().use { input -> target.outputStream().use { input.copyTo(it) } }
        }
    }
}
