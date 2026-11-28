import 'dart:math';

import '../data/exam/insights.dart';
import '../data/models/test.dart';

/// Picks questions for a hosted test from the approved bank.
///
/// With no [subjects], the test follows the exam pattern: each subject gets
/// its share of [count] by marks. Otherwise questions come evenly from the
/// chosen subjects. Shortfalls are topped up from whatever is left.
List<String> pickTestQuestions({
  required List<Question> bank,
  required ExamInsights insights,
  required int count,
  Set<String>? subjects,
  Random? rng,
}) {
  rng ??= Random();
  final pools = {
    for (final s in insights.ranked())
      if (subjects == null || subjects.contains(s.name))
        s.name: bank.where((q) => s.bankSections.contains(q.subject)).toList()..shuffle(rng),
  }..removeWhere((_, pool) => pool.isEmpty);
  // Only subjects with approved questions share out the test.
  final chosen = [for (final s in insights.ranked()) if (pools.containsKey(s.name)) s];
  if (chosen.isEmpty || count <= 0) return const [];

  final totalWeight = subjects == null ? chosen.fold<int>(0, (a, s) => a + s.questions) : chosen.length;
  final picked = <String>{};
  for (final s in chosen) {
    final weight = subjects == null ? s.questions : 1;
    final quota = (count * weight / totalWeight).round();
    picked.addAll(pools[s.name]!.take(quota).map((q) => q.id));
  }
  // Top up (rounding, or subjects with too few approved questions).
  final rest = [for (final p in pools.values) ...p.where((q) => !picked.contains(q.id))]..shuffle(rng);
  for (final q in rest) {
    if (picked.length >= count) break;
    picked.add(q.id);
  }
  return picked.take(count).toList();
}

/// How many approved questions each subject has, for the create-test form.
Map<String, int> bankCountBySubject(List<Question> bank, ExamInsights insights) => {
      for (final s in insights.ranked()) s.name: bank.where((q) => s.bankSections.contains(q.subject)).length,
    };

class QuestionStat {
  const QuestionStat({required this.question, required this.correct, required this.answered, required this.attempts});

  final Question question;
  final int correct;
  final int answered;
  final int attempts;

  double get accuracy => attempts == 0 ? 0 : correct / attempts;
}

/// The unit's results for one test.
class TestReport {
  const TestReport({
    required this.attempts,
    required this.maxScore,
    required this.bySubject,
    required this.hardest,
  });

  /// Highest score first.
  final List<AttemptRecord> attempts;
  final double maxScore;

  /// Subject accuracy across all attempts, weakest first.
  final List<SubjectScore> bySubject;

  /// Questions most cadets got wrong, hardest first.
  final List<QuestionStat> hardest;

  bool get isEmpty => attempts.isEmpty;
  double get average => isEmpty ? 0 : attempts.fold<double>(0, (a, r) => a + r.score) / attempts.length;
  double get highest => isEmpty ? 0 : attempts.first.score;
  double get lowest => isEmpty ? 0 : attempts.last.score;
  double percent(double score) => maxScore == 0 ? 0 : score / maxScore * 100;
}

TestReport summarizeAttempts({
  required List<Question> questions,
  required List<AttemptRecord> attempts,
  required MarkingScheme marking,
}) {
  final sorted = [...attempts]..sort((a, b) => b.score.compareTo(a.score));
  final subj = <String, (int, int)>{};
  final stats = <QuestionStat>[];
  for (final q in questions) {
    var correct = 0, answered = 0;
    for (final a in attempts) {
      final chosen = a.answers[q.id];
      if (chosen == null) continue;
      answered++;
      if (chosen == q.correctIndex) correct++;
    }
    final (c, t) = subj[q.subject] ?? (0, 0);
    subj[q.subject] = (c + correct, t + attempts.length);
    stats.add(QuestionStat(question: q, correct: correct, answered: answered, attempts: attempts.length));
  }
  final bySubject = [
    for (final e in subj.entries) SubjectScore(subject: e.key, correct: e.value.$1, total: e.value.$2),
  ]..sort((a, b) => a.accuracy.compareTo(b.accuracy));
  final hardest = attempts.isEmpty ? <QuestionStat>[] : ([...stats]..sort((a, b) => a.accuracy.compareTo(b.accuracy)));
  return TestReport(
    attempts: sorted,
    maxScore: questions.length * marking.correct,
    bySubject: bySubject,
    hardest: hardest.take(5).toList(),
  );
}

/// Each cadet's average percentage across the tests they took.
Map<String, double> averagePercentByCadet(List<ScoreRow> scores, List<TestDefinition> tests) {
  final maxById = {for (final t in tests) t.id: t.maxScore};
  final sums = <String, (double, int)>{};
  for (final s in scores) {
    final max = maxById[s.testId];
    if (max == null || max == 0) continue;
    final (sum, n) = sums[s.cadetId] ?? (0.0, 0);
    sums[s.cadetId] = (sum + s.score / max * 100, n + 1);
  }
  return {for (final e in sums.entries) e.key: e.value.$1 / e.value.$2};
}
