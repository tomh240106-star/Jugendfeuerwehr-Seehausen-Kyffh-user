import 'duty_plan_row.dart';

class DutyPlanImportService {
  static bool get isSupported => false;

  static Future<List<DutyPlanRow>> extractFromImage(String filePath) async {
    return const <DutyPlanRow>[];
  }
}
