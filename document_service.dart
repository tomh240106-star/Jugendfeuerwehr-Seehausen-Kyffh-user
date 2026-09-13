
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DocumentService {
  static SupabaseClient get db => Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> listDocuments() async {
    return await db.from('documents').select().order('created_at', ascending: false);
  }

  static Future<void> pickAndUpload({
    required String title,
    String? category,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      throw Exception('Die Datei konnte nicht gelesen werden.');
    }

    final uid = db.auth.currentUser!.id;
    final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final objectPath = '$uid/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    await db.storage.from('documents').uploadBinary(
      objectPath,
      Uint8List.fromList(bytes),
      fileOptions: const FileOptions(upsert: false),
    );

    await db.from('documents').insert({
      'title': title,
      'category': category ?? 'Allgemein',
      'file_name': file.name,
      'storage_path': objectPath,
      'mime_type': file.extension,
      'uploaded_by': uid,
    });
  }

  static Future<String> signedUrl(String storagePath) async {
    return await db.storage.from('documents').createSignedUrl(storagePath, 600);
  }

  static Future<void> deleteDocument(String id, String storagePath) async {
    await db.storage.from('documents').remove([storagePath]);
    await db.from('documents').delete().eq('id', id);
  }
}
