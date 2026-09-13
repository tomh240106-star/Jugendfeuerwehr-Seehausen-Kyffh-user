import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class AppService {
  static SupabaseClient get db => Supabase.instance.client;

  static Future<Profile?> myProfile() async {
    final id = db.auth.currentUser?.id;
    if (id == null) return null;

    final row = await db.from('profiles').select().eq('id', id).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  static Future<List<Profile>> allProfiles() async {
    final rows = await db.from('profiles').select().order('last_name');
    return rows.map<Profile>((r) => Profile.fromMap(r)).toList();
  }

  static Future<List<JfEvent>> events() async {
    final rows = await db.from('events').select().order('starts_at');
    return rows.map<JfEvent>((r) => JfEvent.fromMap(r)).toList();
  }

  static Future<void> createEvent({
    required String title,
    required String type,
    required DateTime startsAt,
    DateTime? endsAt,
    String? description,
    String? location,
    String? meetingPoint,
    String? equipment,
  }) async {
    await db.from('events').insert({
      'title': title,
      'event_type': type,
      'starts_at': startsAt.toIso8601String(),
      'ends_at': endsAt?.toIso8601String(),
      'description': description,
      'location': location,
      'meeting_point': meetingPoint,
      'required_equipment': equipment,
      'created_by': db.auth.currentUser!.id,
    });
  }

  static Future<void> setAttendance(String eventId, String status, {String? note}) async {
    await db.from('event_attendance').upsert({
      'event_id': eventId,
      'user_id': db.auth.currentUser!.id,
      'status': status,
      'note': note,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<TrainingPlan>> trainingPlans() async {
    final rows = await db
        .from('training_plans')
        .select('*, training_units(*)')
        .order('valid_from');
    return rows.map<TrainingPlan>((r) => TrainingPlan.fromMap(r)).toList();
  }

  static Future<void> createTrainingPlan({
    required String title,
    String? description,
    DateTime? validFrom,
    DateTime? validUntil,
  }) async {
    await db.from('training_plans').insert({
      'title': title,
      'description': description,
      'valid_from': validFrom?.toIso8601String().split('T').first,
      'valid_until': validUntil?.toIso8601String().split('T').first,
      'created_by': db.auth.currentUser!.id,
    });
  }

  static Future<List<Map<String, dynamic>>> conversations() async {
    final uid = db.auth.currentUser!.id;
    final memberships =
        await db.from('conversation_members').select('conversation_id').eq('user_id', uid);

    final ids = memberships.map((x) => x['conversation_id']).toList();
    if (ids.isEmpty) return [];

    return await db.from('conversations').select().inFilter('id', ids).order('created_at', ascending: false);
  }

  static Future<List<Map<String, dynamic>>> messages(String conversationId) async {
    return await db
        .from('messages')
        .select('*, sender:profiles(first_name,last_name)')
        .eq('conversation_id', conversationId)
        .order('created_at');
  }

  static Future<void> sendMessage(String conversationId, String body) async {
    await db.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': db.auth.currentUser!.id,
      'body': body.trim(),
    });
  }

  static Future<void> createConversation({
    required List<String> memberIds,
    required String title,
    String scope = 'einzelperson',
  }) async {
    final uid = db.auth.currentUser!.id;

    final conversation = await db.from('conversations').insert({
      'title': title,
      'scope': scope,
      'created_by': uid,
    }).select().single();

    final rows = {...memberIds, uid}
        .map((id) => {
              'conversation_id': conversation['id'],
              'user_id': id,
            })
        .toList();

    await db.from('conversation_members').insert(rows);
  }

  static Future<List<Map<String, dynamic>>> notifications() async {
    return await db
        .from('notifications')
        .select()
        .eq('user_id', db.auth.currentUser!.id)
        .order('created_at', ascending: false);
  }

  static Future<List<Profile>> linkedChildren() async {
    final uid = db.auth.currentUser!.id;

    final links = await db.from('parent_child').select('child_id').eq('parent_id', uid);
    final ids = links.map((x) => x['child_id']).toList();
    if (ids.isEmpty) return [];

    final rows = await db.from('profiles').select().inFilter('id', ids);
    return rows.map<Profile>((r) => Profile.fromMap(r)).toList();
  }

  static Future<List<Map<String, dynamic>>> attendanceForEvent(String eventId) async {
    return await db
        .from('event_attendance')
        .select('status,note,user_id,profiles!event_attendance_user_id_fkey(first_name,last_name,role)')
        .eq('event_id', eventId);
  }

  static Future<void> updateAttendanceForUser({
    required String eventId,
    required String userId,
    required String status,
    String? note,
  }) async {
    await db.from('event_attendance').upsert({
      'event_id': eventId,
      'user_id': userId,
      'status': status,
      'note': note,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> deleteEvent(String eventId) async {
    await db.from('events').delete().eq('id', eventId);
  }

  static Future<void> updateEvent({
    required String id,
    required String title,
    required String type,
    required DateTime startsAt,
    DateTime? endsAt,
    String? description,
    String? location,
    String? meetingPoint,
    String? equipment,
  }) async {
    await db.from('events').update({
      'title': title,
      'event_type': type,
      'starts_at': startsAt.toIso8601String(),
      'ends_at': endsAt?.toIso8601String(),
      'description': description,
      'location': location,
      'meeting_point': meetingPoint,
      'required_equipment': equipment,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  static Future<void> createTrainingUnit({
    required String planId,
    required String title,
    String? topic,
    String? objectives,
    String? equipment,
    String? content,
    int sortOrder = 0,
  }) async {
    await db.from('training_units').insert({
      'training_plan_id': planId,
      'title': title,
      'topic': topic,
      'objectives': objectives,
      'equipment': equipment,
      'content': content,
      'sort_order': sortOrder,
    });
  }

  static Future<void> deleteTrainingPlan(String planId) async {
    await db.from('training_plans').delete().eq('id', planId);
  }

  static Future<void> linkParentChild({
    required String parentId,
    required String childId,
  }) async {
    await db.from('parent_child').upsert({
      'parent_id': parentId,
      'child_id': childId,
    });
  }

  static Future<void> unlinkParentChild({
    required String parentId,
    required String childId,
  }) async {
    await db
        .from('parent_child')
        .delete()
        .eq('parent_id', parentId)
        .eq('child_id', childId);
  }

  static Future<List<Map<String, dynamic>>> allParentChildLinks() async {
    return await db.from('parent_child').select(
      'parent_id,child_id,parent:profiles!parent_child_parent_id_fkey(first_name,last_name,role),child:profiles!parent_child_child_id_fkey(first_name,last_name,role)',
    );
  }

  static Future<void> setUserRole(String userId, String role) async {
    await db.from('profiles').update({'role': role}).eq('id', userId);
  }

}
