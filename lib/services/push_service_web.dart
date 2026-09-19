import 'dart:async';

class PushService {
  PushService._();

  static final StreamController<String> _openController =
      StreamController<String>.broadcast();

  static Stream<String> get openEvents => _openController.stream;

  static String? consumePendingDestination() => null;

  static Future<void> initialize() async {}

  static Future<void> syncToken() async {}

  static Future<void> cancelAlarmNotification(String alarmId) async {}
}
