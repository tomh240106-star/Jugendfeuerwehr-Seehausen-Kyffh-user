class Profile {
  final String id;
  final String firstName;
  final String lastName;
  final String role;
  final String? phone;
  final String? avatarUrl;

  Profile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.phone,
    this.avatarUrl,
  });

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'],
        firstName: m['first_name'] ?? '',
        lastName: m['last_name'] ?? '',
        role: m['role'] ?? 'jugendmitglied',
        phone: m['phone'],
        avatarUrl: m['avatar_url'],
      );

  String get name => '$firstName $lastName'.trim();
}

class JfEvent {
  final String id;
  final String title;
  final String type;
  final String? description;
  final String? location;
  final String? meetingPoint;
  final String? equipment;
  final DateTime startsAt;
  final DateTime? endsAt;

  JfEvent({
    required this.id,
    required this.title,
    required this.type,
    required this.startsAt,
    this.description,
    this.location,
    this.meetingPoint,
    this.equipment,
    this.endsAt,
  });

  factory JfEvent.fromMap(Map<String, dynamic> m) => JfEvent(
        id: m['id'],
        title: m['title'],
        type: m['event_type'] ?? 'dienst',
        description: m['description'],
        location: m['location'],
        meetingPoint: m['meeting_point'],
        equipment: m['required_equipment'],
        startsAt: DateTime.parse(m['starts_at']),
        endsAt: m['ends_at'] == null ? null : DateTime.parse(m['ends_at']),
      );
}

class TrainingPlan {
  final String id;
  final String title;
  final String? description;
  final List<TrainingUnit> units;

  TrainingPlan({
    required this.id,
    required this.title,
    this.description,
    required this.units,
  });

  factory TrainingPlan.fromMap(Map<String, dynamic> m) => TrainingPlan(
        id: m['id'],
        title: m['title'] ?? 'Ausbildungsplan',
        description: m['description'],
        units: ((m['training_units'] ?? []) as List)
            .map((x) => TrainingUnit.fromMap(Map<String, dynamic>.from(x)))
            .toList(),
      );
}

class TrainingUnit {
  final String id;
  final String title;
  final String? topic;
  final String? objectives;
  final String? equipment;
  final String? content;

  TrainingUnit({
    required this.id,
    required this.title,
    this.topic,
    this.objectives,
    this.equipment,
    this.content,
  });

  factory TrainingUnit.fromMap(Map<String, dynamic> m) => TrainingUnit(
        id: m['id'],
        title: m['title'],
        topic: m['topic'],
        objectives: m['objectives'],
        equipment: m['equipment'],
        content: m['content'],
      );
}
