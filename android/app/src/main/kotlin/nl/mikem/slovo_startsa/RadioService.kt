package nl.mikem.slovo_startsa

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Прямой эфир «Радио ВЕРА». Играет в фоне (в том числе с выключенным
 * экраном) и показывает уведомление с кнопкой «Стоп».
 */
class RadioService : Service() {

    companion object {
        /** stopped | buffering | playing | error — опрашивается из Dart. */
        @Volatile
        var state: String = "stopped"

        private const val ACTION_PLAY = "nl.mikem.slovo_startsa.RADIO_PLAY"
        private const val ACTION_STOP = "nl.mikem.slovo_startsa.RADIO_STOP"
        private const val CHANNEL = "radio"
        private const val NOTIFICATION_ID = 2002

        fun play(ctx: Context, url: String, title: String) {
            state = "buffering"
            val i = Intent(ctx, RadioService::class.java)
                .setAction(ACTION_PLAY)
                .putExtra("url", url)
                .putExtra("title", title)
            try {
                if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i)
                else ctx.startService(i)
            } catch (_: Exception) {
                state = "error"
            }
        }

        fun stop(ctx: Context) {
            state = "stopped"
            ctx.stopService(Intent(ctx, RadioService::class.java))
        }
    }

    private var player: MediaPlayer? = null
    private var title = "Радио ВЕРА"
    private var focusRequest: AudioFocusRequest? = null
    private var noisyRegistered = false

    private val audioManager by lazy { getSystemService(Context.AUDIO_SERVICE) as AudioManager }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> stopAll()
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> player?.setVolume(0f, 0f)
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> player?.setVolume(0.25f, 0.25f)
            AudioManager.AUDIOFOCUS_GAIN -> player?.setVolume(1f, 1f)
        }
    }

    /** Наушники выдернули — выключаем, чтобы не заиграло в динамик. */
    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) stopAll()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopAll()
                return START_NOT_STICKY
            }
            ACTION_PLAY -> {
                title = intent.getStringExtra("title") ?: title
                val url = intent.getStringExtra("url") ?: ""
                goForeground("Подключаюсь…")
                startPlayer(url)
            }
            else -> {
                // Перезапуск системой без команды — не играем.
                goForeground("")
                stopAll()
            }
        }
        return START_NOT_STICKY
    }

    private fun startPlayer(url: String) {
        releasePlayer()
        if (url.isBlank()) {
            fail()
            return
        }
        requestFocus()
        registerNoisy()
        state = "buffering"
        try {
            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            mp.setWakeMode(applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
            mp.setOnPreparedListener {
                it.start()
                state = "playing"
                updateNotification("В эфире")
            }
            mp.setOnInfoListener { _, what, _ ->
                when (what) {
                    MediaPlayer.MEDIA_INFO_BUFFERING_START -> {
                        state = "buffering"
                        updateNotification("Подключаюсь…")
                    }
                    MediaPlayer.MEDIA_INFO_BUFFERING_END -> {
                        state = "playing"
                        updateNotification("В эфире")
                    }
                }
                false
            }
            mp.setOnErrorListener { _, _, _ ->
                fail()
                true
            }
            mp.setOnCompletionListener { fail() }
            mp.setDataSource(url)
            player = mp
            mp.prepareAsync()
        } catch (_: Exception) {
            fail()
        }
    }

    private fun fail() {
        releasePlayer()
        abandonFocus()
        unregisterNoisy()
        state = "error"
        stopForegroundCompat()
        stopSelf()
    }

    private fun stopAll() {
        releasePlayer()
        abandonFocus()
        unregisterNoisy()
        state = "stopped"
        stopForegroundCompat()
        stopSelf()
    }

    private fun releasePlayer() {
        player?.let {
            try {
                it.stop()
            } catch (_: Exception) {
            }
            it.release()
        }
        player = null
    }

    @Suppress("DEPRECATION")
    private fun requestFocus() {
        if (Build.VERSION.SDK_INT >= 26) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setOnAudioFocusChangeListener(focusListener)
                .build()
            focusRequest = req
            audioManager.requestAudioFocus(req)
        } else {
            audioManager.requestAudioFocus(
                focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN
            )
        }
    }

    @Suppress("DEPRECATION")
    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= 26) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            focusRequest = null
        } else {
            audioManager.abandonAudioFocus(focusListener)
        }
    }

    private fun registerNoisy() {
        if (noisyRegistered) return
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(noisyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(noisyReceiver, filter)
        }
        noisyRegistered = true
    }

    private fun unregisterNoisy() {
        if (!noisyRegistered) return
        try {
            unregisterReceiver(noisyReceiver)
        } catch (_: Exception) {
        }
        noisyRegistered = false
    }

    private fun buildNotification(status: String): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(CHANNEL, "Радио", NotificationManager.IMPORTANCE_LOW)
            ch.description = "Радио ВЕРА в фоне"
            ch.setSound(null, null)
            nm.createNotificationChannel(ch)
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, RadioService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        @Suppress("DEPRECATION")
        val stopAction = Notification.Action.Builder(
            android.R.drawable.ic_media_pause, "Стоп", stop
        ).build()
        val b = Reminders.newBuilder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_cross)
            .setContentTitle(title)
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(stopAction)
            .setStyle(Notification.MediaStyle().setShowActionsInCompactView(0))
            .setColor(0xFF8E2A22.toInt())
        if (status.isNotEmpty()) b.setContentText(status)
        return b.build()
    }

    private fun goForeground(status: String) {
        val n = buildNotification(status)
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(
                    NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                )
            } else {
                startForeground(NOTIFICATION_ID, n)
            }
        } catch (_: Exception) {
        }
    }

    private fun updateNotification(status: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        try {
            nm.notify(NOTIFICATION_ID, buildNotification(status))
        } catch (_: SecurityException) {
        }
    }

    @Suppress("DEPRECATION")
    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= 24) stopForeground(Service.STOP_FOREGROUND_REMOVE)
        else stopForeground(true)
    }

    override fun onDestroy() {
        releasePlayer()
        abandonFocus()
        unregisterNoisy()
        if (state != "error") state = "stopped"
        super.onDestroy()
    }
}
