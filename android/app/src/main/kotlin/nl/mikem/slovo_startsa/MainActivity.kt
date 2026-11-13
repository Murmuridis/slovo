package nl.mikem.slovo_startsa

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
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

                    "radioPlay" -> {
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
    }
}
