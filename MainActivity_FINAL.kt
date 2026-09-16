package de.jfseehausen.kyffhaeuser

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val alarmChannel =
        "de.jfseehausen.kyffhaeuser/alarm_service"

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine,
    ) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            alarmChannel,
        ).setMethodCallHandler { call, result ->

            try {
                when (call.method) {
                    "startAlarmService" -> {
                        val alarmId =
                            call.argument<String>("alarmId") ?: ""

                        val title =
                            call.argument<String>("title")
                                ?: "JUGENDFEUERWEHR-ALARM"

                        val body =
                            call.argument<String>("body")
                                ?: "Alarm öffnen und Rückmeldung geben."

                        AlarmForegroundService.start(
                            applicationContext,
                            alarmId,
                            title,
                            body,
                        )

                        result.success(true)
                    }

                    "stopAlarmService" -> {
                        AlarmForegroundService.stop(
                            applicationContext,
                        )

                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error(
                    "ALARM_SERVICE_ERROR",
                    e.message ?: e.toString(),
                    null,
                )
            }
        }
    }
}
