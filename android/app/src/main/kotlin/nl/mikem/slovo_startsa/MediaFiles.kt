package nl.mikem.slovo_startsa

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.OutputStream
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/** Картинки и аудио молитв лежат в files/media; в базе — только имена файлов. */
object MediaFiles {
    fun dir(ctx: Context): File = File(ctx.filesDir, "media").apply { mkdirs() }

    /** Скопировать выбранный файл к себе. Возвращает {file, name} или null. */
    fun import(ctx: Context, uri: Uri, kind: String): Map<String, String>? {
        return try {
            val cr = ctx.contentResolver
            var display = ""
            cr.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) display = c.getString(0) ?: ""
            }
            var ext = display.substringAfterLast('.', "").lowercase()
            if (ext.isEmpty() || ext.length > 5) {
                ext = MimeTypeMap.getSingleton()
                    .getExtensionFromMimeType(cr.getType(uri) ?: "") ?: ""
            }
            ext = ext.filter { it.isLetterOrDigit() }
            val name = kind + "_" + UUID.randomUUID().toString().replace("-", "") +
                (if (ext.isEmpty()) "" else ".$ext")
            val out = File(dir(ctx), name)
            cr.openInputStream(uri)?.use { input ->
                out.outputStream().use { input.copyTo(it) }
            } ?: return null
            if (display.isEmpty()) display = name
            mapOf("file" to name, "name" to display.substringBeforeLast('.', display))
        } catch (_: Exception) {
            null
        }
    }
}

/** Проигрыватель аудио, прикреплённого к молитве. */
object PrayerAudio {
    private var mp: MediaPlayer? = null
    private var path = ""

    /** stopped | preparing | playing | paused | completed | error */
    private var state = "stopped"

    @Synchronized
    fun play(p: String) {
        val m = mp
        if (p == path && m != null && (state == "paused" || state == "completed")) {
            if (state == "completed") m.seekTo(0)
            m.start()
            state = "playing"
            return
        }
        if (p == path && state == "playing") return
        release()
        path = p
        state = "preparing"
        try {
            val n = MediaPlayer()
            n.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            n.setOnPreparedListener {
                synchronized(this) {
                    if (mp === it) {
                        it.start()
                        state = "playing"
                    }
                }
            }
            n.setOnCompletionListener { synchronized(this) { state = "completed" } }
            n.setOnErrorListener { _, _, _ ->
                synchronized(this) { state = "error" }
                true
            }
            n.setDataSource(p)
            mp = n
            n.prepareAsync()
        } catch (_: Exception) {
            state = "error"
        }
    }

    @Synchronized
    fun pause() {
        if (state == "playing") {
            try {
                mp?.pause()
                state = "paused"
            } catch (_: Exception) {
            }
        }
    }

    @Synchronized
    fun seek(ms: Int) {
        if (state == "playing" || state == "paused" || state == "completed") {
            try {
                mp?.seekTo(ms)
                if (state == "completed") state = "paused"
            } catch (_: Exception) {
            }
        }
    }

    @Synchronized
    fun stop() {
        release()
        path = ""
        state = "stopped"
    }

    private fun release() {
        mp?.let {
            try {
                it.stop()
            } catch (_: Exception) {
            }
            it.release()
        }
        mp = null
    }

    @Synchronized
    fun info(): Map<String, Any> {
        var pos = 0
        var dur = 0
        val m = mp
        if (m != null && (state == "playing" || state == "paused" || state == "completed")) {
            try {
                dur = m.duration
                pos = if (state == "completed") dur else m.currentPosition
            } catch (_: Exception) {
            }
        }
        return mapOf("path" to path, "state" to state, "pos" to pos, "dur" to dur)
    }
}

/**
 * Резервная копия: один .zip с базой (цитаты, избранное, источники,
 * молитвы, настройки) и всеми картинками и аудио.
 */
object Backup {
    private const val DB_ENTRY = "slovo.db"
    private const val INFO_ENTRY = "backup.json"

    private fun openOut(ctx: Context, uri: Uri): OutputStream? =
        try {
            ctx.contentResolver.openOutputStream(uri, "wt")
        } catch (_: Exception) {
            ctx.contentResolver.openOutputStream(uri, "w")
        }

    /** Записать копию. Возвращает текст ошибки или null. */
    fun write(ctx: Context, uriStr: String, dbPath: String): String? {
        val db = File(dbPath)
        if (!db.exists()) return "База не найдена"
        val media = MediaFiles.dir(ctx).listFiles()?.filter { it.isFile } ?: emptyList()
        return try {
            val os = openOut(ctx, Uri.parse(uriStr)) ?: return "Не удалось создать файл"
            ZipOutputStream(BufferedOutputStream(os)).use { zos ->
                val info = JSONObject()
                    .put("app", "slovo_startsa")
                    .put("format", 1)
                    .put("created", System.currentTimeMillis())
                    .put("media", media.size)
                zos.putNextEntry(ZipEntry(INFO_ENTRY))
                zos.write(info.toString().toByteArray())
                zos.closeEntry()
                zos.putNextEntry(ZipEntry(DB_ENTRY))
                db.inputStream().use { it.copyTo(zos) }
                zos.closeEntry()
                for (f in media) {
                    zos.putNextEntry(ZipEntry("media/" + f.name))
                    f.inputStream().use { it.copyTo(zos) }
                    zos.closeEntry()
                }
            }
            null
        } catch (e: Exception) {
            "Ошибка записи: " + (e.message ?: e.javaClass.simpleName)
        }
    }

    private fun safeMediaName(entry: String): String? {
        if (!entry.startsWith("media/")) return null
        val n = entry.removePrefix("media/")
        if (n.isEmpty() || n.contains('/') || n.contains('\\') || n.startsWith(".")) return null
        return n
    }

    /** Проверить файл перед восстановлением. */
    fun check(ctx: Context, uriStr: String): Map<String, Any> {
        var hasDb = false
        var media = 0
        var created = 0L
        try {
            val input = ctx.contentResolver.openInputStream(Uri.parse(uriStr))
                ?: return mapOf("ok" to false, "error" to "Не удалось открыть файл")
            ZipInputStream(BufferedInputStream(input)).use { zis ->
                while (true) {
                    val e = zis.nextEntry ?: break
                    when {
                        e.isDirectory -> {}
                        e.name == DB_ENTRY -> hasDb = true
                        e.name == INFO_ENTRY -> try {
                            created = JSONObject(zis.readBytes().toString(Charsets.UTF_8))
                                .optLong("created", 0)
                        } catch (_: Exception) {
                        }
                        safeMediaName(e.name) != null -> media++
                    }
                }
            }
        } catch (_: Exception) {
            return mapOf("ok" to false, "error" to "Это не резервная копия «Слова старца»")
        }
        if (!hasDb) return mapOf("ok" to false, "error" to "Это не резервная копия «Слова старца»")
        return mapOf("ok" to true, "media" to media, "created" to created)
    }

    /** Восстановить копию. База должна быть закрыта. Возвращает текст ошибки или null. */
    fun restore(ctx: Context, uriStr: String, dbPath: String): String? {
        val tmp = File(ctx.cacheDir, "restore")
        tmp.deleteRecursively()
        val tmpMedia = File(tmp, "media").apply { mkdirs() }
        val tmpDb = File(tmp, DB_ENTRY)
        try {
            val input = ctx.contentResolver.openInputStream(Uri.parse(uriStr))
                ?: return "Не удалось открыть файл"
            ZipInputStream(BufferedInputStream(input)).use { zis ->
                while (true) {
                    val e = zis.nextEntry ?: break
                    if (e.isDirectory) continue
                    val target = when {
                        e.name == DB_ENTRY -> tmpDb
                        else -> safeMediaName(e.name)?.let { File(tmpMedia, it) }
                    } ?: continue
                    target.outputStream().use { zis.copyTo(it) }
                }
            }
            if (!tmpDb.exists()) return "В файле нет базы данных"
            val header = ByteArray(16)
            tmpDb.inputStream().use { it.read(header) }
            if (!String(header, Charsets.US_ASCII).startsWith("SQLite format 3")) {
                return "База в копии повреждена"
            }
            for (suffix in listOf("", "-journal", "-wal", "-shm")) File(dbPath + suffix).delete()
            tmpDb.copyTo(File(dbPath), overwrite = true)
            val media = MediaFiles.dir(ctx)
            media.listFiles()?.forEach { it.delete() }
            tmpMedia.listFiles()?.forEach { it.copyTo(File(media, it.name), overwrite = true) }
            return null
        } catch (e: Exception) {
            return "Ошибка восстановления: " + (e.message ?: e.javaClass.simpleName)
        } finally {
            tmp.deleteRecursively()
        }
    }
}
