import 'package:shared_preferences/shared_preferences.dart';

class OfflineCacheService {
  const OfflineCacheService._();

  static Future<void> clearSensitiveDataForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();

    final keys = <String>[
      'approval_status_cache_v1_$userId',
      'home_profile_role_v1_$userId',
      'home_profile_first_name_v1_$userId',
      'home_profile_last_name_v1_$userId',
      'more_profile_role_v1_$userId',
      'more_profile_first_name_v1_$userId',
      'more_profile_last_name_v1_$userId',
      'more_profile_phone_v1_$userId',
      'more_profile_notifications_v1_$userId',
      'more_developer_v1_$userId',
      'member_records_cache_v1_${userId}_youth',
      'member_records_cache_v1_${userId}_records',
      'member_records_cache_v1_${userId}_synced_at',
    ];

    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
