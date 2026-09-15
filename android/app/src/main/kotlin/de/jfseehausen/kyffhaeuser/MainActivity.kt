package de.jfseehausen.kyffhaeuser

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val alarmChannel = "de.jfseehausen.kyffhaeuser/alarm_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            alarmChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "stopAlarmService" -> {
                    AlarmForegroundService.stop(applicationContext)
                    result.success(true)
                }

                "startAlarmService" -> {
                    val alarmId = call.argument<String>("alarmId") ?: ""
                    val title = call.argument<String>("title")
                        ?: "JUGENDFEUERWEHR-ALARM"
                    val body = call.argument<String>("body")
                        ?: "Alarm öffnen und Rückmeldung geben."

                    AlarmForegroundService.start(
                        applicationContext,
                        alarmId,
                        title,
                        body,
                    )
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }
}
