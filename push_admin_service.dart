
import 'package:supabase_flutter/supabase_flutter.dart';

class PushAdminService {
  static Future<void> sendPush({
    required String title,
    required String body,
    String? userId,
  }) async {
    final result = await Supabase.instance.client.functions.invoke(
      'send-push',
      body: {
        'title': title,
        'body': body,
        if (userId != null) 'user_id': userId,
      },
    );

    if (result.status < 200 || result.status >= 300) {
      throw Exception('Push-Versand fehlgeschlagen: ${result.data}');
    }
  }
}
