package de.jfseehausen.kyffhaeuser

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class AlarmForegroundService : Service() {

    companion object {
        const val ACTION_START = "de.jfseehausen.kyffhaeuser.ALARM_START"
        const val ACTION_STOP = "de.jfseehausen.kyffhaeuser.ALARM_STOP"

        const val EXTRA_ALARM_ID = "alarm_id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"

        private const val TAG = "JFAlarmService"
        private const val CHANNEL_ID = "jf_alarm_service_v2"
        private const val NOTIFICATION_ID = 1702

        fun start(
            context: Context,
            alarmId: String,
            title: String,
            body: String,
        ) {
            val intent = Intent(context, AlarmForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_ALARM_ID, alarmId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
            }

            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, AlarmForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }

    private var mediaPlayer: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        Log.i(TAG, "Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopAlarm()
                return START_NOT_STICKY
            }

            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE)
                    ?: "JUGENDFEUERWEHR-ALARM"
                val body = intent.getStringExtra(EXTRA_BODY)
                    ?: "Alarm öffnen und Rückmeldung geben."

                startForeground(
                    NOTIFICATION_ID,
                    buildNotification(title, body),
                )

                startAlarmSound()
                acquireWakeLock()

                return START_STICKY
            }
        }

        return START_NOT_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Jugendfeuerwehr Daueralarm",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Daueralarm bis zur Rückmeldung"
            setSound(null, null)
            enableVibration(true)
            setShowBadge(true)
        }

        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(title: String, body: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                    android.app.PendingIntent.FLAG_IMMUTABLE
            } else {
                android.app.PendingIntent.FLAG_UPDATE_CURRENT
            }

            android.app.PendingIntent.getActivity(
                this,
                1702,
                it,
                flags,
            )
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun startAlarmSound() {
        try {
            stopPlayerOnly()

            val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
            val alarmVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
            val alarmMax = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)

            Log.i(TAG, "Alarm volume: $alarmVolume / $alarmMax")

            val player = MediaPlayer.create(this, R.raw.jf_alarm)
                ?: throw IllegalStateException("MediaPlayer.create returned null")

            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            player.isLooping = true

            player.setOnErrorListener { _, what, extra ->
                Log.e(TAG, "MediaPlayer error: what=$what extra=$extra")
                true
            }

            player.setOnCompletionListener {
                Log.w(TAG, "Alarm sound completed although looping=true")
            }

            mediaPlayer = player
            player.start()

            Log.i(TAG, "Alarm sound started, isPlaying=${player.isPlaying}")
        } catch (e: Exception) {
            Log.e(TAG, "Could not start alarm sound", e)
        }
    }

    private fun stopPlayerOnly() {
        val player = mediaPlayer ?: return
        try {
            if (player.isPlaying) player.stop()
        } catch (_: Exception) {
        }
        player.release()
        mediaPlayer = null
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return

        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "JFSeehausen:AlarmWakeLock",
        ).apply {
            setReferenceCounted(false)
            acquire(15 * 60 * 1000L)
        }
    }

    private fun stopAlarm() {
        stopPlayerOnly()

        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        wakeLock = null

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        stopPlayerOnly()

        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        wakeLock = null

        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
