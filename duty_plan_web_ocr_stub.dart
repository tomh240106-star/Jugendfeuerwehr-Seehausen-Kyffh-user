import 'dart:typed_data';

import 'duty_plan_row.dart';

class DutyPlanWebOcr {
  static bool get isSupported => false;

  static Future<List<DutyPlanRow>> extractFromImageBytes(
    Uint8List bytes,
    String fileName,
  ) async {
    return const <DutyPlanRow>[];
  }
}
