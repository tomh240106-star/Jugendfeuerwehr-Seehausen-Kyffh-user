import 'dart:js_interop';

@JS('jfWebAlarmStart')
external void _jfWebAlarmStart(JSString alarmId, JSString title, JSString body);

@JS('jfWebAlarmStop')
external void _jfWebAlarmStop();

class AlarmNativeService {
  static Future<void> stop() async {
    _jfWebAlarmStop();
  }

  static Future<void> start({
    required String alarmId,
    required String title,
    required String body,
  }) async {
    _jfWebAlarmStart(
      alarmId.toJS,
      title.toJS,
      body.toJS,
    );
  }
}
