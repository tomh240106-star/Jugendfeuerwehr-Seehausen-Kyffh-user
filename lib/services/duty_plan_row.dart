class DutyPlanRow {
  final DateTime date;
  final String startTime;
  final String? endTime;
  final String topic;
  final String location;

  const DutyPlanRow({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.topic,
    required this.location,
  });
}
