package de.jfseehausen.kyffhaeuser

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class JfFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val source = remoteMessage.data["source"] ?: ""
        val alarmId = remoteMessage.data["alarm_id"] ?: ""
        val title = remoteMessage.data["title"] ?: "JUGENDFEUERWEHR-ALARM"
        val body = remoteMessage.data["body"]
            ?: "Alarm öffnen und Rückmeldung geben."

        when (source) {
            "jf_alarm" -> {
                AlarmForegroundService.start(
                    applicationContext,
                    alarmId,
                    title,
                    body,
                )
            }

            "jf_alarm_cancel" -> {
                AlarmForegroundService.stop(applicationContext)
            }
        }
    }
}
