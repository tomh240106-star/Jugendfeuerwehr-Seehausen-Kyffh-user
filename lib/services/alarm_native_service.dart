import 'package:flutter/services.dart';

class AlarmNativeService {
  static const MethodChannel _channel = MethodChannel(
    'de.jfseehausen.kyffhaeuser/alarm_service',
  );

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stopAlarmService');
    } catch (_) {}
  }

  static Future<void> start({
    required String alarmId,
    required String title,
    required String body,
  }) async {
    try {
      await _channel.invokeMethod<void>(
        'startAlarmService',
        {
          'alarmId': alarmId,
          'title': title,
          'body': body,
        },
      );
    } catch (_) {}
  }
}
