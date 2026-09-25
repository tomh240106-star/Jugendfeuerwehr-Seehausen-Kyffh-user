import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeveloperErrorLogger {
  DeveloperErrorLogger._();

  static bool _installed = false;
  static bool _writing = false;

  static void installGlobalHandlers() {
    if (_installed) return;
    _installed = true;

    final previousFlutterHandler = FlutterError.onError;

    FlutterError.onError = (details) {
      if (previousFlutterHandler != null) {
        previousFlutterHandler(details);
      } else {
        FlutterError.presentError(details);
      }

      unawaited(
        logError(
          details.exception,
          details.stack,
          source: 'FlutterError',
          severity: 'error',
          context: {
            if (details.library != null) 'library': details.library,
            'silent': details.silent,
          },
        ),
      );
    };

    final previousPlatformHandler =
        PlatformDispatcher.instance.onError;

    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        logError(
          error,
          stack,
          source: 'PlatformDispatcher',
          severity: 'fatal',
        ),
      );

      if (previousPlatformHandler != null) {
        return previousPlatformHandler(error, stack);
      }

      return false;
    };
  }

  static Future<void> logError(
    Object error,
    StackTrace? stack, {
    String source = 'app',
    String severity = 'error',
    Map<String, dynamic>? context,
  }) async {
    if (_writing) return;

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;

      if (user == null) return;

      _writing = true;

      await client.from('app_error_logs').insert({
        'user_id': user.id,
        'severity': _normalizeSeverity(severity),
        'source': _trim(_scrub(source), 200),
        'message': _trim(_scrub(error.toString()), 5000),
        'stack_trace': stack == null
            ? null
            : _trim(_scrub(stack.toString()), 16000),
        'platform': _platformName(),
        'context': _scrubContext(context ?? const <String, dynamic>{}),
      });
    } catch (_) {
      // Fehlerlogging darf niemals selbst die App blockieren.
    } finally {
      _writing = false;
    }
  }

  static String _normalizeSeverity(String value) {
    switch (value) {
      case 'info':
      case 'warning':
      case 'fatal':
        return value;
      default:
        return 'error';
    }
  }

  static String _platformName() {
    if (kIsWeb) return 'web';

    return defaultTargetPlatform.name;
  }

  static String _trim(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength)}…';
  }

  static dynamic _scrubContext(dynamic value) {
    if (value is String) return _trim(_scrub(value), 2000);

    if (value is List) {
      return value
          .take(30)
          .map(_scrubContext)
          .toList(growable: false);
    }

    if (value is Map) {
      final cleaned = <String, dynamic>{};

      for (final entry in value.entries.take(30)) {
        cleaned[_trim(entry.key.toString(), 120)] =
            _scrubContext(entry.value);
      }

      return cleaned;
    }

    if (value is num || value is bool || value == null) {
      return value;
    }

    return _trim(_scrub(value.toString()), 2000);
  }

  static String _scrub(String input) {
    var value = input;

    value = value.replaceAll(
      RegExp(
        r'Bearer\s+[A-Za-z0-9\-._~+/]+=*',
        caseSensitive: false,
      ),
      'Bearer [REDACTED]',
    );

    value = value.replaceAll(
      RegExp(
        r'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}',
      ),
      '[JWT REDACTED]',
    );

    value = value.replaceAllMapped(
      RegExp(
        r'((?:access_token|refresh_token|apikey|api_key|token)\s*[=:]\s*)[^,\s&}]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1) ?? ''}[REDACTED]',
    );

    return value;
  }
}
