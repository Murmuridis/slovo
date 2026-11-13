package nl.mikem.slovo_startsa

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Ежедневное напоминание со «словом дня».
 *
 * Приложение заранее передаёт сюда цитаты на ближайшие дни (см. Reminder в
 * lib/native.dart), а будильник Android в нужное время показывает
 * уведомление с сегодняшней цитатой и ставит себя на следующий день.
 */
object Reminders {
    private const val PREFS = "slovo_reminder"
    private const val CHANNEL = "daily_word"
    private const val NOTIFICATION_ID = 1001
    const val ACTION_FIRE = "nl.mikem.slovo_startsa.REMINDER"

    fun save(ctx: Context, hour: Int, minute: Int, quotes: String) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean("on", true)
            .putInt("hour", hour)
            .putInt("minute", minute)
            .putString("quotes", quotes)
            .apply()
    }

    fun disable(ctx: Context) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean("on", false).apply()
        alarmManager(ctx).cancel(pendingIntent(ctx))
    }

    private fun alarmManager(ctx: Context) =
        ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun pendingIntent(ctx: Context): PendingIntent {
        val i = Intent(ctx, ReminderReceiver::class.java).setAction(ACTION_FIRE)
        return PendingIntent.getBroadcast(
            ctx, NOTIFICATION_ID, i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** Поставить будильник на ближайшее наступление выбранного времени. */
    fun schedule(ctx: Context) {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("on", false)) return
        val now = Calendar.getInstance()
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, prefs.getInt("hour", 8))
            set(Calendar.MINUTE, prefs.getInt("minute", 0))
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (!after(now)) add(Calendar.DAY_OF_YEAR, 1)
        }
        val am = alarmManager(ctx)
        val pi = pendingIntent(ctx)
        val at = next.timeInMillis
        try {
            when {
                Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms() ->
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
                Build.VERSION.SDK_INT >= 23 ->
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
                else -> am.setExact(AlarmManager.RTC_WAKEUP, at, pi)
            }
        } catch (_: SecurityException) {
            if (Build.VERSION.SDK_INT >= 23) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } else {
                am.set(AlarmManager.RTC_WAKEUP, at, pi)
            }
        }
    }

    fun notificationsAllowed(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            ctx.checkSelfPermission("android.permission.POST_NOTIFICATIONS") !=
            PackageManager.PERMISSION_GRANTED
        ) return false
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return if (Build.VERSION.SDK_INT >= 24) nm.areNotificationsEnabled() else true
    }

    /** Показать уведомление с сегодняшней цитатой. */
    fun show(ctx: Context) {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("on", false)) return
        if (!notificationsAllowed(ctx)) return

        val key = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        var text = "Откройте приложение, чтобы прочитать слово на сегодня."
        var author = ""
        try {
            val all = JSONObject(prefs.getString("quotes", "{}") ?: "{}")
            val q = all.optJSONObject(key)
            if (q != null) {
                text = q.optString("t", text)
                author = q.optString("a", "")
            }
        } catch (_: Exception) {
        }

        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(
                CHANNEL, "Слово дня", NotificationManager.IMPORTANCE_DEFAULT
            )
            ch.description = "Ежедневное напоминание с цитатой"
            nm.createNotificationChannel(ch)
        }
        val open = Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val contentIntent = PendingIntent.getActivity(
            ctx, 0, open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val big = if (author.isEmpty()) text else "$text\n— $author"
        val builder = newBuilder(ctx, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_cross)
            .setContentTitle(if (author.isEmpty()) "Слово на сегодня" else author)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(big))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
        if (Build.VERSION.SDK_INT >= 21) builder.setColor(0xFF8E2A22.toInt())
        try {
            nm.notify(NOTIFICATION_ID, builder.build())
        } catch (_: SecurityException) {
        }
    }

    @Suppress("DEPRECATION")
    fun newBuilder(ctx: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(ctx, channel)
        else Notification.Builder(ctx)
}

/** Срабатывание будильника: показать цитату и завести на завтра. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Reminders.ACTION_FIRE) {
            Reminders.show(context)
        }
        Reminders.schedule(context)
    }
}

/** После перезагрузки, обновления или смены времени будильники надо ставить заново. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Reminders.schedule(context)
    }
}
