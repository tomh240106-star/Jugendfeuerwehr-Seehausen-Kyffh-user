package de.jfseehausen.kyffhaeuser

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class JfFirebaseMessagingService : FirebaseMessagingService() {

    companion object {
        private const val DIAG_CHANNEL = "jf_alarm_diag"
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val source = remoteMessage.data["source"] ?: ""
        val alarmId = remoteMessage.data["alarm_id"] ?: ""
        val title = remoteMessage.data["title"] ?: "JUGENDFEUERWEHR-ALARM"
        val body = remoteMessage.data["body"]
            ?: "Alarm öffnen und Rückmeldung geben."

        if (source == "jf_alarm") {
            try {
                AlarmForegroundService.start(
                    applicationContext,
                    alarmId,
                    title,
                    body,
                )

                showDiagnostic(
                    "Alarm-Datenpush empfangen",
                    "Priorität: ${priorityName(remoteMessage.priority)} · Daueralarm wurde gestartet.",
                    1801,
                )
            } catch (e: Exception) {
                showDiagnostic(
                    "Alarm empfangen – Dienststart fehlgeschlagen",
                    "${e.javaClass.simpleName}: ${e.message ?: e.toString()}",
                    1802,
                )
            }

            return
        }

        if (source == "jf_alarm_cancel") {
            try {
                AlarmForegroundService.stop(applicationContext)
            } catch (_: Exception) {
            }
            return
        }

        // Diagnose für unerwartete Daten-Pushs.
        if (remoteMessage.data.isNotEmpty()) {
            showDiagnostic(
                "Daten-Push empfangen",
                "source=$source · Priorität: ${priorityName(remoteMessage.priority)}",
                1803,
            )
        }
    }

    private fun priorityName(priority: Int): String {
        return when (priority) {
            RemoteMessage.PRIORITY_HIGH -> "HIGH"
            RemoteMessage.PRIORITY_NORMAL -> "NORMAL"
            else -> priority.toString()
        }
    }

    private fun showDiagnostic(
        title: String,
        body: String,
        id: Int,
    ) {
        val manager = getSystemService(NotificationManager::class.java)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    DIAG_CHANNEL,
                    "Alarm Diagnose",
                    NotificationManager.IMPORTANCE_HIGH,
                ),
            )
        }

        val notification = NotificationCompat.Builder(this, DIAG_CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()

        manager.notify(id, notification)
    }
}
