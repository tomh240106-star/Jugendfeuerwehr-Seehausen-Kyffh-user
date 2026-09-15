package de.jfseehausen.kyffhaeuser

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class AlarmForegroundService : Service() {
    companion object {
        const val ACTION_START = "de.jfseehausen.kyffhaeuser.ALARM_START"
        const val ACTION_STOP = "de.jfseehausen.kyffhaeuser.ALARM_STOP"

        const val EXTRA_ALARM_ID = "alarm_id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"

        private const val CHANNEL_ID = "jf_alarm_service_v1"
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

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
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

                // Falls Android den Prozess beendet, darf der Service neu gestartet werden.
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
            setSound(null, null) // Ton wird vom MediaPlayer geloopt.
            enableVibration(true)
            setShowBadge(true)
        }

        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(title: String, body: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = if (launchIntent != null) {
            androidx.core.app.PendingIntentCompat.getActivity(
                this,
                1702,
                launchIntent,
                0,
                false,
            )
        } else {
            null
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
        if (mediaPlayer?.isPlaying == true) return

        mediaPlayer?.release()

        val afd = resources.openRawResourceFd(R.raw.jf_alarm) ?: return
        mediaPlayer = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            setDataSource(
                afd.fileDescriptor,
                afd.startOffset,
                afd.length,
            )
            isLooping = true
            prepare()
            start()
        }
        afd.close()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return

        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "JFSeehausen:AlarmWakeLock",
        ).apply {
            setReferenceCounted(false)
            acquire(15 * 60 * 1000L) // Sicherheitsgrenze: 15 Minuten.
        }
    }

    private fun stopAlarm() {
        mediaPlayer?.let {
            try {
                if (it.isPlaying) it.stop()
            } catch (_: Exception) {
            }
            it.release()
        }
        mediaPlayer = null

        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        wakeLock = null

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        stopAlarm()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
