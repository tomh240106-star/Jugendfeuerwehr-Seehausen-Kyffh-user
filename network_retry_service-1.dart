import 'dart:async';

/// Zentrale, vorsichtige Retry-Schicht für reine Lesevorgänge.
///
/// Wichtig:
/// - Nur für idempotente READ-Operationen verwenden.
/// - Keine Inserts/Updates/Deletes, Alarme, Nachrichten oder andere
///   Schreibvorgänge automatisch wiederholen.
class NetworkRetryService {
  NetworkRetryService._();

  static Future<T> read<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 350),
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (maxAttempts < 1) {
      throw ArgumentError.value(
        maxAttempts,
        'maxAttempts',
        'muss mindestens 1 sein',
      );
    }

    Object? lastError;
    StackTrace? lastStack;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await operation().timeout(timeout);
      } catch (error, stack) {
        lastError = error;
        lastStack = stack;

        if (!_isTransient(error) || attempt >= maxAttempts) {
          Error.throwWithStackTrace(error, stack);
        }

        final multiplier = 1 << (attempt - 1);
        await Future<void>.delayed(initialDelay * multiplier);
      }
    }

    Error.throwWithStackTrace(lastError!, lastStack!);
  }

  static bool _isTransient(Object error) {
    if (error is TimeoutException) return true;

    // Kein dart:io: Die Retry-Schicht muss auch im Flutter-Web-Build laufen.
    // Netzwerkfehler werden dort je nach Browser/Supabase-Client als
    // unterschiedliche Exception-Typen gekapselt.
    final message = error.toString().toLowerCase();

    const transientMarkers = <String>[
      'network',
      'socket',
      'connection reset',
      'connection refused',
      'connection closed',
      'failed host lookup',
      'host lookup',
      'timed out',
      'timeout',
      'clientexception',
      'xmlhttprequest',
      'failed to fetch',
      'networkerror',
      'network request failed',
      'connection error',
      'connection terminated',
      'connection aborted',
    ];

    return transientMarkers.any(message.contains);
  }
}
