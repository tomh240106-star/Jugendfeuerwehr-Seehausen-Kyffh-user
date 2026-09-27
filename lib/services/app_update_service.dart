import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'developer_error_logger.dart';

class AppRelease {
  final String id;
  final String versionName;
  final int buildNumber;
  final String channel;
  final String abi;
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
    required this.abi,
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
      abi: map['abi']?.toString() ?? 'universal',
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

  String get abiLabel {
    switch (abi) {
      case 'arm64-v8a':
        return 'ARM64';
      case 'armeabi-v7a':
        return 'ARMv7';
      case 'x86_64':
        return 'x86_64';
      default:
        return 'Universal';
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
    final rawBuildNumber = int.tryParse(info.buildNumber) ?? 0;

    // Flutter's --split-per-abi encodes the ABI into Android's
    // versionCode. Example: pubspec build 14 becomes 2014 for ARM64.
    // The update server stores the logical pubspec build number, so
    // strip the ABI prefix before comparing release numbers.
    if (supportsAutomaticUpdate &&
        rawBuildNumber >= 1000 &&
        rawBuildNumber < 1000000) {
      final logicalBuildNumber = rawBuildNumber % 1000;
      if (logicalBuildNumber > 0) {
        return logicalBuildNumber;
      }
    }

    return rawBuildNumber;
  }

  static String? _normalizeAbi(String value) {
    switch (value.trim().toLowerCase()) {
      case 'arm64-v8a':
        return 'arm64-v8a';
      case 'armeabi-v7a':
        return 'armeabi-v7a';
      case 'x86_64':
        return 'x86_64';
      default:
        return null;
    }
  }

  static Future<List<String>> supportedAndroidAbis() async {
    if (!supportsAutomaticUpdate) {
      return const ['universal'];
    }

    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final values = <String>[];

      for (final raw in info.supportedAbis) {
        final normalized = _normalizeAbi(raw);
        if (normalized != null && !values.contains(normalized)) {
          values.add(normalized);
        }
      }

      if (values.isEmpty) {
        values.add('universal');
      }

      return values;
    } catch (error, stack) {
      await DeveloperErrorLogger.logError(
        error,
        stack,
        source: 'AppUpdateService.supportedAndroidAbis',
        severity: 'warning',
      );
      return const ['universal'];
    }
  }

  static Future<AppRelease?> findLatestAllowedUpdate() async {
    if (!supportsAutomaticUpdate) return null;

    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final currentBuild = await currentBuildNumber();
      final supportedAbis = await supportedAndroidAbis();

      final rows = await _supabase
          .from('app_releases')
          .select(
            'id,version_name,build_number,channel,abi,storage_path,'
            'sha256,notes,force_update,file_size_bytes',
          )
          .eq('platform', 'android')
          .eq('is_active', true)
          .neq('channel', 'non')
          .gt('build_number', currentBuild)
          .order('build_number', ascending: false)
          .limit(50);

      final candidates = List<Map<String, dynamic>>.from(rows)
          .map(AppRelease.fromMap)
          .where(
            (release) =>
                release.storagePath.isNotEmpty &&
                release.sha256.length == 64 &&
                release.buildNumber > currentBuild,
          )
          .toList();

      if (candidates.isEmpty) return null;

      final buildNumbers = candidates
          .map((release) => release.buildNumber)
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));

      for (final buildNumber in buildNumbers) {
        final sameBuild = candidates
            .where(
              (release) => release.buildNumber == buildNumber,
            )
            .toList();

        for (final abi in supportedAbis) {
          for (final release in sameBuild) {
            if (release.abi == abi) {
              return release;
            }
          }
        }

        for (final release in sameBuild) {
          if (release.abi == 'universal') {
            return release;
          }
        }
      }

      return null;
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
          'abi': release.abi,
        },
      );
      rethrow;
    }
  }
}
