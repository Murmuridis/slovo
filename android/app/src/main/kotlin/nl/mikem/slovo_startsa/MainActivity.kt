package nl.mikem.slovo_startsa

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Мостик к Android для lib/native.dart:
 *  - «Поделиться» и открытие ссылок;
 *  - ежедневное напоминание (Reminders.kt);
 *  - Радио ВЕРА (RadioService.kt).
 * Сделано без сторонних плагинов, чтобы сборка не зависела от их версий.
 */
class MainActivity : FlutterActivity() {
    private var pendingPermission: MethodChannel.Result? = null

    /** Ожидание ответа от системного окна выбора/сохранения файла. */
    private var pendingActivity: MethodChannel.Result? = null
    private var pendingKind = ""

    private fun startForResult(intent: Intent, code: Int, kind: String, result: MethodChannel.Result) {
        pendingActivity?.success(null)
        pendingActivity = result
        pendingKind = kind
        try {
            startActivityForResult(intent, code)
        } catch (_: Exception) {
            pendingActivity = null
            result.success(null)
        }
    }

    /** Тяжёлую работу с файлами — не в главном потоке. */
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        Thread {
            val r = try {
                work()
            } catch (e: Exception) {
                null
            }
            runOnUiThread { result.success(r) }
        }.start()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "slovo/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "share" -> {
                        val text = call.arguments as? String ?: ""
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                        }
                        try {
                            startActivity(Intent.createChooser(send, "Поделиться цитатой"))
                        } catch (_: Exception) {
                        }
                        result.success(null)
                    }

                    "openUrl" -> {
                        val url = call.arguments as? String ?: ""
                        try {
                            val i = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                            result.success(true)
                        } catch (_: ActivityNotFoundException) {
                            result.success(false)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }

                    "notificationsEnabled" -> result.success(Reminders.notificationsAllowed(this))

                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(PERMISSION) != PackageManager.PERMISSION_GRANTED
                        ) {
                            pendingPermission?.success(false)
                            pendingPermission = result
                            requestPermissions(arrayOf(PERMISSION), REQUEST_CODE)
                        } else {
                            result.success(Reminders.notificationsAllowed(this))
                        }
                    }

                    "scheduleReminder" -> {
                        val hour = call.argument<Int>("hour") ?: 8
                        val minute = call.argument<Int>("minute") ?: 0
                        val quotes = call.argument<String>("quotes") ?: "{}"
                        Reminders.save(this, hour, minute, quotes)
                        Reminders.schedule(this)
                        result.success(null)
                    }

                    "cancelReminder" -> {
                        Reminders.disable(this)
                        result.success(null)
                    }

                    "mediaDir" -> result.success(MediaFiles.dir(this).absolutePath)

                    "pickFiles" -> {
                        val kind = call.arguments as? String ?: "image"
                        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                            if (kind == "audio") {
                                type = "*/*"
                                putExtra(
                                    Intent.EXTRA_MIME_TYPES,
                                    arrayOf("audio/*", "application/ogg")
                                )
                            } else {
                                type = "image/*"
                            }
                        }
                        startForResult(i, REQ_PICK, kind, result)
                    }

                    "createDocument" -> {
                        val i = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = call.argument<String>("mime") ?: "application/zip"
                            putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "backup.zip")
                        }
                        startForResult(i, REQ_DOC, "", result)
                    }

                    "openDocument" -> {
                        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        startForResult(i, REQ_DOC, "", result)
                    }

                    "writeBackup" -> {
                        val uri = call.argument<String>("uri") ?: ""
                        val db = call.argument<String>("db") ?: ""
                        background(result) { Backup.write(this, uri, db) ?: "" }
                    }

                    "checkBackup" -> {
                        val uri = call.arguments as? String ?: ""
                        background(result) { Backup.check(this, uri) }
                    }

                    "restoreBackup" -> {
                        val uri = call.argument<String>("uri") ?: ""
                        val db = call.argument<String>("db") ?: ""
                        PrayerAudio.stop()
                        background(result) { Backup.restore(this, uri, db) ?: "" }
                    }

                    "audioPlay" -> {
                        RadioService.stop(this)
                        PrayerAudio.play(call.arguments as? String ?: "")
                        result.success(null)
                    }

                    "audioPause" -> {
                        PrayerAudio.pause()
                        result.success(null)
                    }

                    "audioSeek" -> {
                        PrayerAudio.seek(call.arguments as? Int ?: 0)
                        result.success(null)
                    }

                    "audioStop" -> {
                        PrayerAudio.stop()
                        result.success(null)
                    }

                    "audioState" -> result.success(PrayerAudio.info())

                    "keepScreenOn" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }

                    "radioPlay" -> {
                        PrayerAudio.stop()
                        val url = call.argument<String>("url") ?: ""
                        val title = call.argument<String>("title") ?: "Радио ВЕРА"
                        RadioService.play(this, url, title)
                        result.success(null)
                    }

                    "radioStop" -> {
                        RadioService.stop(this)
                        result.success(null)
                    }

                    "radioState" -> result.success(RadioService.state)

                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PICK && requestCode != REQ_DOC) return
        val result = pendingActivity ?: return
        pendingActivity = null
        if (resultCode != android.app.Activity.RESULT_OK || data == null) {
            result.success(null)
            return
        }
        if (requestCode == REQ_DOC) {
            result.success(data.data?.toString())
            return
        }
        val uris = mutableListOf<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (k in 0 until clip.itemCount) clip.getItemAt(k).uri?.let { uris.add(it) }
        } else {
            data.data?.let { uris.add(it) }
        }
        val kind = pendingKind
        background(result) { uris.mapNotNull { MediaFiles.import(this, it, kind) } }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermission?.success(granted)
            pendingPermission = null
        }
    }

    companion object {
        private const val PERMISSION = "android.permission.POST_NOTIFICATIONS"
        private const val REQUEST_CODE = 4711
        private const val REQ_PICK = 4801
        private const val REQ_DOC = 4802
    }
}
