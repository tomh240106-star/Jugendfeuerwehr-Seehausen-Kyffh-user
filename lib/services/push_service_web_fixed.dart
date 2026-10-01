import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@JS('jfWebPushRequestToken')
external JSPromise<JSString> _requestWebPushToken();

@JS('jfWebPushGetToken')
external JSPromise<JSString> _getWebPushToken();

class PushService {
  PushService._();

  static const String _installationIdKey = 'push_installation_id_v1';

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
      if (token.isEmpty) {
        debugPrint(
          'Web Push: Kein FCM-Token erhalten. '
          'Benachrichtigungsberechtigung oder Browser-Push prüfen.',
        );
        return false;
      }

      await _saveToken(token);
      debugPrint('Web Push: Token erfolgreich registriert.');
      return true;
    } catch (error, stackTrace) {
      debugPrint('Web Push: Token-Anforderung fehlgeschlagen: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  static Future<void> syncToken() async {
    try {
      final token = (await _getWebPushToken().toDart).toDart.trim();
      if (token.isEmpty) {
        debugPrint(
          'Web Push: Kein vorhandener FCM-Token. '
          'Benachrichtigungen müssen ggf. zuerst aktiviert werden.',
        );
        return;
      }

      await _saveToken(token);
      debugPrint('Web Push: Vorhandener Token synchronisiert.');
    } catch (error, stackTrace) {
      debugPrint('Web Push: Token-Synchronisierung fehlgeschlagen: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<String> _getInstallationId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_installationIdKey)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;

    final now = DateTime.now().microsecondsSinceEpoch;
    final seed = Object().hashCode.abs();
    final installationId = 'web_${now}_$seed';

    await preferences.setString(_installationIdKey, installationId);
    return installationId;
  }

  static Future<void> _saveToken(String token) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      debugPrint('Web Push: Kein angemeldeter Benutzer, Token nicht gespeichert.');
      return;
    }

    final installationId = await _getInstallationId();

    await client.rpc(
      'claim_device_token',
      params: {
        'p_token': token,
        'p_platform': 'web',
        'p_installation_id': installationId,
      },
    );
  }

  static Future<void> unregisterCurrentDevice() async {
    try {
      final token = (await _getWebPushToken().toDart).toDart.trim();
      if (token.isEmpty) return;

      await Supabase.instance.client.rpc(
        'release_device_token',
        params: {'p_token': token},
      );
    } catch (error, stackTrace) {
      debugPrint('Web Push: Abmeldung des Tokens fehlgeschlagen: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<bool> sendTestNotification() async {
    try {
      // Vor dem Test den aktuellen Browser-Token nochmals synchronisieren.
      await syncToken();

      final response = await Supabase.instance.client.functions.invoke(
        'send-push',
        body: {
          'title': 'Jugendfeuerwehr Test',
          'body': 'Benachrichtigungen funktionieren auf diesem Gerät.',
          'self_test': true,
        },
      );

      if (response.status >= 400) return false;

      final data = response.data;
      if (data is Map) {
        final sent = data['sent'];
        if (sent is num) return sent > 0;
      }

      return true;
    } catch (error, stackTrace) {
      debugPrint('Web Push: Testbenachrichtigung fehlgeschlagen: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  static Future<void> cancelAlarmNotification(String alarmId) async {}
}
