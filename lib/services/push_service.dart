import 'dart:async';
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

  static const AndroidNotificationChannel _generalChannel =
      AndroidNotificationChannel(
    'jf_general',
    'Jugendfeuerwehr Benachrichtigungen',
    description: 'Wichtige Benachrichtigungen der Jugendfeuerwehr',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _alarmChannel =
      AndroidNotificationChannel(
    'jf_alarm',
    'Jugendfeuerwehr Alarm',
    description: 'Dringende Jugendfeuerwehr- und Übungsalarme',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static bool _initialized = false;

  static final StreamController<String> _openController =
      StreamController<String>.broadcast();

  static String? _pendingDestination;

  static Stream<String> get openEvents => _openController.stream;

  static String? consumePendingDestination() {
    final value = _pendingDestination;
    _pendingDestination = null;
    return value;
  }

  static void _emitDestination(String destination) {
    _pendingDestination = destination;
    _openController.add(destination);
  }

  static void _handleRemoteOpen(RemoteMessage message) {
    final source = message.data['source']?.toString();
    if (source == 'jf_alarm') {
      _emitDestination('alarm');
    }
  }

  static void _handleLocalOpen(NotificationResponse response) {
    if (response.payload == 'jf_alarm') {
      _emitDestination('alarm');
    }
  }

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

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleLocalOpen,
    );

    final localLaunchDetails =
        await _localNotifications.getNotificationAppLaunchDetails();

    if (localLaunchDetails?.didNotificationLaunchApp == true &&
        localLaunchDetails?.notificationResponse?.payload == 'jf_alarm') {
      _emitDestination('alarm');
    }

    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_generalChannel);

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_alarmChannel);
    }

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteOpen);

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleRemoteOpen(initialMessage);
    }

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

    final isAlarm = message.data['source']?.toString() == 'jf_alarm';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        isAlarm ? 'jf_alarm' : 'jf_general',
        isAlarm
            ? 'Jugendfeuerwehr Alarm'
            : 'Jugendfeuerwehr Benachrichtigungen',
        channelDescription: isAlarm
            ? 'Dringende Jugendfeuerwehr- und Übungsalarme'
            : 'Wichtige Benachrichtigungen der Jugendfeuerwehr',
        importance: isAlarm ? Importance.max : Importance.high,
        priority: isAlarm ? Priority.max : Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotifications.show(
      message.messageId?.hashCode ??
          DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      title ?? 'Jugendfeuerwehr',
      body ?? '',
      details,
      payload: isAlarm ? 'jf_alarm' : 'jf_general',
    );
  }
}
