import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

int _alarmNotificationId(String alarmId) {
  final hex = alarmId.replaceAll('-', '');
  final part = hex.length >= 8 ? hex.substring(0, 8) : hex.padRight(8, '0');
  return (int.tryParse(part, radix: 16) ?? 1701) & 0x7fffffff;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final source = message.data['source']?.toString();
  final alarmId = message.data['alarm_id']?.toString() ?? '';
  if (alarmId.isEmpty) return;

  final notifications = FlutterLocalNotificationsPlugin();

  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  await notifications.initialize(settings);

  if (source == 'jf_alarm_cancel') {
    await notifications.cancel(_alarmNotificationId(alarmId));
    return;
  }

  if (source != 'jf_alarm') return;

  if (Platform.isAndroid) {
    const channel = AndroidNotificationChannel(
      'jf_alarm_v2',
      'Jugendfeuerwehr Alarm',
      description: 'Dringende Jugendfeuerwehr- und Übungsalarme',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      sound: RawResourceAndroidNotificationSound('jf_alarm'),
    );

    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      'jf_alarm_v2',
      'Jugendfeuerwehr Alarm',
      channelDescription: 'Dringende Jugendfeuerwehr- und Übungsalarme',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('jf_alarm'),
      enableVibration: true,
      ongoing: true,
      autoCancel: false,
      category: AndroidNotificationCategory.alarm,
      additionalFlags: Int32List.fromList(<int>[4]),
      icon: '@mipmap/ic_launcher',
    ),
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'jf_alarm.wav',
      interruptionLevel: InterruptionLevel.timeSensitive,
    ),
  );

  await notifications.show(
    _alarmNotificationId(alarmId),
    message.data['title']?.toString() ?? 'JUGENDFEUERWEHR-ALARM',
    message.data['body']?.toString() ?? 'Alarm öffnen und Rückmeldung geben.',
    details,
    payload: 'jf_alarm',
  );
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
    'jf_alarm_v2',
    'Jugendfeuerwehr Alarm',
    description: 'Dringende Jugendfeuerwehr- und Übungsalarme',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    sound: RawResourceAndroidNotificationSound('jf_alarm'),
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
      provisional: false,
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

  static Future<bool> requestPermissionAndSync() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied ||
        settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      return false;
    }

    await syncToken();
    return true;
  }

  static Future<void> syncToken() async {
    try {
      if (Platform.isIOS) {
        // On iOS the APNs token can take a moment after permission is granted.
        for (var i = 0; i < 10; i++) {
          final apnsToken = await _messaging.getAPNSToken();
          if (apnsToken != null && apnsToken.isNotEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

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

    await client.rpc(
      'claim_device_token',
      params: {
        'p_token': token,
        'p_platform': Platform.isIOS ? 'ios' : 'android',
      },
    );
  }

  static Future<void> _showForegroundNotification(
    RemoteMessage message,
  ) async {
    final source = message.data['source']?.toString();
    final alarmId = message.data['alarm_id']?.toString() ?? '';

    if (source == 'jf_alarm_cancel' && alarmId.isNotEmpty) {
      await _localNotifications.cancel(_alarmNotificationId(alarmId));
      return;
    }

    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();

    if (title == null && body == null) return;

    final isAlarm = source == 'jf_alarm';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        isAlarm ? 'jf_alarm_v2' : 'jf_general',
        isAlarm
            ? 'Jugendfeuerwehr Alarm'
            : 'Jugendfeuerwehr Benachrichtigungen',
        channelDescription: isAlarm
            ? 'Dringende Jugendfeuerwehr- und Übungsalarme'
            : 'Wichtige Benachrichtigungen der Jugendfeuerwehr',
        importance: isAlarm ? Importance.max : Importance.high,
        priority: isAlarm ? Priority.max : Priority.high,
        playSound: true,
        sound: isAlarm
            ? const RawResourceAndroidNotificationSound('jf_alarm')
            : null,
        enableVibration: true,
        ongoing: isAlarm,
        autoCancel: !isAlarm,
        category: isAlarm ? AndroidNotificationCategory.alarm : null,
        additionalFlags: isAlarm ? Int32List.fromList(<int>[4]) : null,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: isAlarm ? 'jf_alarm.wav' : null,
        interruptionLevel: isAlarm
            ? InterruptionLevel.timeSensitive
            : InterruptionLevel.active,
      ),
    );

    final id = isAlarm && alarmId.isNotEmpty
        ? _alarmNotificationId(alarmId)
        : message.messageId?.hashCode ??
            DateTime.now().millisecondsSinceEpoch.remainder(2147483647);

    await _localNotifications.show(
      id,
      title ?? 'Jugendfeuerwehr',
      body ?? '',
      details,
      payload: isAlarm ? 'jf_alarm' : 'jf_general',
    );
  }

  static Future<void> unregisterCurrentDevice() async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;

      await Supabase.instance.client.rpc(
        'release_device_token',
        params: {'p_token': token},
      );
    } catch (error) {
      debugPrint(
        'Geräte-Token konnte beim Abmelden nicht entfernt werden: $error',
      );
    }
  }

  static Future<bool> sendTestNotification() async {
    try {
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
    } catch (error) {
      debugPrint('Test-Benachrichtigung fehlgeschlagen: $error');
      return false;
    }
  }

  static Future<void> cancelAlarmNotification(String alarmId) async {
    if (alarmId.isEmpty) return;
    await _localNotifications.cancel(_alarmNotificationId(alarmId));
  }
}
