import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'developer_error_logger.dart';

class AppRelease {
  final String id;
  final String versionName;
  final int buildNumber;
  final String channel;
  final String storagePath;
  final String sha256;
  final String notes;
  final bool forceUpdate;
  final int? fileSizeBytes;

  const AppRelease({
    required this.id,
    required this.versionName,
    required this.buildNumber,
    required this.channel,
    required this.storagePath,
    required this.sha256,
    required this.notes,
    required this.forceUpdate,
    required this.fileSizeBytes,
  });

  factory AppRelease.fromMap(Map<String, dynamic> map) {
    return AppRelease(
      id: map['id']?.toString() ?? '',
      versionName: map['version_name']?.toString() ?? '',
      buildNumber: int.tryParse(
            map['build_number']?.toString() ?? '',
          ) ??
          0,
      channel: map['channel']?.toString() ?? 'forall',
      storagePath: map['storage_path']?.toString() ?? '',
      sha256: map['sha256']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
      forceUpdate: map['force_update'] == true,
      fileSizeBytes: int.tryParse(
        map['file_size_bytes']?.toString() ?? '',
      ),
    );
  }

  String get channelLabel {
    switch (channel) {
      case 'beta':
        return 'BETA';
      case 'forall':
        return 'FOR ALL';
      default:
        return 'NON';
    }
  }
}

class AppUpdateService {
  AppUpdateService._();

  static final SupabaseClient _supabase =
      Supabase.instance.client;

  static bool get supportsAutomaticUpdate {
    return !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android;
  }

  static Future<int> currentBuildNumber() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  static Future<AppRelease?> findLatestAllowedUpdate() async {
    if (!supportsAutomaticUpdate) return null;

    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final currentBuild = await currentBuildNumber();

      final rows = await _supabase
          .from('app_releases')
          .select(
            'id,version_name,build_number,channel,storage_path,'
            'sha256,notes,force_update,file_size_bytes',
          )
          .eq('platform', 'android')
          .eq('is_active', true)
          // NON ist selbst für den Entwickler niemals Teil der
          // automatischen Update-Auslieferung.
          .neq('channel', 'non')
          .gt('build_number', currentBuild)
          .order('build_number', ascending: false)
          .limit(1);

      final list = List<Map<String, dynamic>>.from(rows);
      if (list.isEmpty) return null;

      final release = AppRelease.fromMap(list.first);

      if (release.storagePath.isEmpty ||
          release.sha256.length != 64 ||
          release.buildNumber <= currentBuild) {
        return null;
      }

      return release;
    } catch (error, stack) {
      await DeveloperErrorLogger.logError(
        error,
        stack,
        source: 'AppUpdateService.findLatestAllowedUpdate',
        severity: 'warning',
      );
      return null;
    }
  }

  static Future<String> createDownloadUrl(
    AppRelease release,
  ) async {
    try {
      // Kurze Gültigkeit: Der Download wird direkt danach gestartet.
      // Der Bucket bleibt privat.
      return await _supabase.storage
          .from('app-updates')
          .createSignedUrl(
            release.storagePath,
            15 * 60,
          );
    } catch (error, stack) {
      await DeveloperErrorLogger.logError(
        error,
        stack,
        source: 'AppUpdateService.createDownloadUrl',
        severity: 'error',
        context: {
          'release_id': release.id,
          'build_number': release.buildNumber,
          'channel': release.channel,
        },
      );
      rethrow;
    }
  }
}
