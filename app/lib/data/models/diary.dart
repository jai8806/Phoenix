import 'package:material_ui/material_ui.dart';

enum SessionType {
  drill('Drill', Icons.directions_walk),
  shooting('Shooting', Icons.adjust),
  pt('PT', Icons.fitness_center),
  mapReading('Map reading', Icons.explore_outlined),
  obstacle('Obstacle', Icons.terrain_outlined),
  cultural('Cultural', Icons.music_note_outlined),
  other('Other', Icons.edit_note);

  const SessionType(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum ShootingPosition {
  prone('Prone'),
  kneeling('Kneeling'),
  standing('Standing');

  const ShootingPosition(this.label);
  final String label;
}

class ShootingMetrics {
  const ShootingMetrics({
    required this.rifle,
    required this.position,
    required this.distanceMetres,
    required this.rounds,
    this.score,
    this.groupMm,
  });

  final String rifle;
  final ShootingPosition position;
  final int distanceMetres;
  final int rounds;
  final int? score;

  /// Diameter of the shot group, in millimetres.
  final double? groupMm;
}

class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.type,
    required this.date,
    this.durationMinutes,
    this.wentWell,
    this.toImprove,
    this.instructorNotes,
    this.mood,
    this.fatigue,
    this.sleepHours,
    this.shooting,
    this.sharedWithUnit = false,
  });

  final String id;
  final SessionType type;
  final DateTime date;
  final int? durationMinutes;
  final String? wentWell;
  final String? toImprove;
  final String? instructorNotes;

  /// 1 (low) to 5 (high).
  final int? mood;
  final int? fatigue;
  final double? sleepHours;
  final ShootingMetrics? shooting;

  /// Private by default. Only shared entries are visible to unit admins.
  final bool sharedWithUnit;
}
