
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushService {
  static final _local = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // Firebase config files may not be installed yet.
      return;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();

    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    const channel = AndroidNotificationChannel(
      'jf_general',
      'Jugendfeuerwehr',
      description: 'Termine, Nachrichten und wichtige Hinweise',
      importance: Importance.high,
    );

    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await messaging.getToken();
    if (token != null) {
      await _saveToken(token);
    }

    messaging.onTokenRefresh.listen(_saveToken);

    FirebaseMessaging.onMessage.listen((message) async {
      final n = message.notification;
      if (n == null) return;

      await _local.show(
        n.hashCode,
        n.title ?? 'Jugendfeuerwehr',
        n.body ?? '',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'jf_general',
            'Jugendfeuerwehr',
            channelDescription: 'Termine, Nachrichten und wichtige Hinweise',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    });
  }

  static Future<void> _saveToken(String token) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      await Supabase.instance.client.from('device_tokens').upsert({
        'user_id': user.id,
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      }, onConflict: 'token');
    } catch (_) {}
  }
}
