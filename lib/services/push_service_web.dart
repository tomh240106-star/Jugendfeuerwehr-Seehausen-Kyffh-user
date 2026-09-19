import 'dart:async';
import 'dart:js_interop';

import 'package:supabase_flutter/supabase_flutter.dart';

@JS('jfWebPushRequestToken')
external JSPromise<JSString> _requestWebPushToken();

@JS('jfWebPushGetToken')
external JSPromise<JSString> _getWebPushToken();

class PushService {
  PushService._();

  static final StreamController<String> _openController =
      StreamController<String>.broadcast();

  static Stream<String> get openEvents => _openController.stream;

  static String? consumePendingDestination() => null;

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      if (data.session != null) {
        await syncToken();
      }
    });

    if (Supabase.instance.client.auth.currentSession != null) {
      await syncToken();
    }
  }

  static Future<bool> requestPermissionAndSync() async {
    try {
      final token = (await _requestWebPushToken().toDart).toDart.trim();
      if (token.isEmpty) return false;

      await _saveToken(token);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> syncToken() async {
    try {
      final token = (await _getWebPushToken().toDart).toDart.trim();
      if (token.isEmpty) return;

      await _saveToken(token);
    } catch (_) {}
  }

  static Future<void> _saveToken(String token) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    await client.rpc(
      'claim_device_token',
      params: {
        'p_token': token,
        'p_platform': 'web',
      },
    );
  }

  static Future<void> cancelAlarmNotification(String alarmId) async {}
}
