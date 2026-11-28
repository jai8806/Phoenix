import '../data/models/diary.dart';

/// Simple, explainable numbers from a cadet's diary. These feed the Diary
/// header today and give the AI brief (Phase 2) facts it can cite.
class DiaryStats {
  const DiaryStats({
    required this.sessionsLast30Days,
    required this.streakDays,
    required this.shootingSessions,
    this.averageScore,
    this.bestScore,
    this.firstGroupMm,
    this.latestGroupMm,
    this.sessionsByType = const {},
  });

  final int sessionsLast30Days;

  /// Consecutive days with at least one entry, ending today or yesterday.
  final int streakDays;
  final int shootingSessions;
  final double? averageScore;
  final int? bestScore;

  /// Average group size over the first and the latest three shooting sessions.
  final double? firstGroupMm;
  final double? latestGroupMm;
  final Map<SessionType, int> sessionsByType;

  /// Positive when groups are getting tighter.
  double? get groupImprovementMm =>
      firstGroupMm == null || latestGroupMm == null ? null : firstGroupMm! - latestGroupMm!;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

DiaryStats computeDiaryStats(List<DiaryEntry> entries, {required DateTime today}) {
  final t = _day(today);
  final last30 = entries.where((e) => !_day(e.date).isBefore(t.subtract(const Duration(days: 29)))).length;

  final days = entries.map((e) => _day(e.date)).toSet();
  var streak = 0;
  var cursor = days.contains(t) ? t : t.subtract(const Duration(days: 1));
  while (days.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  final shooting = entries.where((e) => e.shooting != null).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  final scores = [for (final e in shooting) if (e.shooting!.score != null) e.shooting!.score!];
  final groups = [for (final e in shooting) if (e.shooting!.groupMm != null) e.shooting!.groupMm!];

  double? avg(Iterable<num> xs) =>
      xs.isEmpty ? null : xs.fold<double>(0, (sum, x) => sum + x) / xs.length;

  final byType = <SessionType, int>{};
  for (final e in entries) {
    byType[e.type] = (byType[e.type] ?? 0) + 1;
  }

  return DiaryStats(
    sessionsLast30Days: last30,
    streakDays: streak,
    shootingSessions: shooting.length,
    averageScore: avg(scores),
    bestScore: scores.isEmpty ? null : scores.reduce((a, b) => a > b ? a : b),
    firstGroupMm: groups.length < 2 ? null : avg(groups.take(3)),
    latestGroupMm: groups.length < 2 ? null : avg(groups.skip(groups.length > 3 ? groups.length - 3 : 0)),
    sessionsByType: byType,
  );
}
