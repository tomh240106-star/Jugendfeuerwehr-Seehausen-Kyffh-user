import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushService {
  PushService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel =
      AndroidNotificationChannel(
    'jf_general',
    'Jugendfeuerwehr Benachrichtigungen',
    description: 'Wichtige Benachrichtigungen der Jugendfeuerwehr',
    importance: Importance.high,
  );

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await Firebase.initializeApp();

    FirebaseMessaging.onBackgroundMessage(
      firebaseMessagingBackgroundHandler,
    );

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _localNotifications.initialize(settings);

    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    }

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    _messaging.onTokenRefresh.listen((token) async {
      await _saveToken(token);
    });

    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      if (data.session != null) {
        await syncToken();
      }
    });

    if (Supabase.instance.client.auth.currentSession != null) {
      await syncToken();
    }
  }

  static Future<void> syncToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _saveToken(token);
    } catch (error) {
      debugPrint('FCM-Token konnte nicht synchronisiert werden: $error');
    }
  }

  static Future<void> _saveToken(String token) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    await client.from('device_tokens').upsert(
      {
        'user_id': user.id,
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      },
      onConflict: 'token',
    );
  }

  static Future<void> _showForegroundNotification(
    RemoteMessage message,
  ) async {
    final notification = message.notification;
    final title =
        notification?.title ?? message.data['title']?.toString();
    final body =
        notification?.body ?? message.data['body']?.toString();

    if (title == null && body == null) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'jf_general',
        'Jugendfeuerwehr Benachrichtigungen',
        channelDescription:
            'Wichtige Benachrichtigungen der Jugendfeuerwehr',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _localNotifications.show(
      message.messageId?.hashCode ??
          DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      title ?? 'Jugendfeuerwehr',
      body ?? '',
      details,
    );
  }
}
