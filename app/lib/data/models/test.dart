class Question {
  const Question({
    required this.id,
    required this.subject,
    required this.prompt,
    required this.options,
    required this.correctIndex,
    this.explanation,
  }) : assert(correctIndex >= 0);

  final String id;
  final String subject;
  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String? explanation;
}

/// How a test is marked. Negative marking is stored as a positive number
/// that is subtracted for each wrong answer.
class MarkingScheme {
  const MarkingScheme({this.correct = 2, this.wrong = 0});

  final double correct;
  final double wrong;
}

/// The shape of an official paper.
class ExamBlueprint {
  const ExamBlueprint({
    required this.name,
    required this.questionCount,
    required this.totalMarks,
    required this.durationMinutes,
    required this.source,
  });

  final String name;
  final int questionCount;
  final int totalMarks;
  final int durationMinutes;

  /// Where the numbers come from, shown to cadets so they can check them.
  final String source;
}

/// B Certificate written paper, as published for 2026-27. Re-check against
/// the current SNCCO before every exam season.
const bCertificateBlueprint = ExamBlueprint(
  name: 'B Certificate written',
  questionCount: 175,
  totalMarks: 350,
  durationMinutes: 150,
  source: 'SNCCO 2026 (as reported for 2026-27; verify with your unit)',
);

class TestDefinition {
  const TestDefinition({
    required this.id,
    required this.title,
    required this.durationMinutes,
    required this.marking,
    required this.questionIds,
    this.opensAt,
  });

  final String id;
  final String title;
  final int durationMinutes;
  final MarkingScheme marking;
  final List<String> questionIds;
  final DateTime? opensAt;
}

class SubjectScore {
  const SubjectScore({required this.subject, required this.correct, required this.total});

  final String subject;
  final int correct;
  final int total;

  double get accuracy => total == 0 ? 0 : correct / total;
}

class TestResult {
  const TestResult({
    required this.score,
    required this.maxScore,
    required this.correct,
    required this.wrong,
    required this.skipped,
    required this.bySubject,
  });

  final double score;
  final double maxScore;
  final int correct;
  final int wrong;
  final int skipped;
  final List<SubjectScore> bySubject;

  double get percentage => maxScore == 0 ? 0 : score / maxScore * 100;

  /// Subjects below 60% accuracy, weakest first.
  List<SubjectScore> get weakSubjects =>
      bySubject.where((s) => s.accuracy < 0.6).toList()
        ..sort((a, b) => a.accuracy.compareTo(b.accuracy));
}

/// Marks a set of answers. [answers] maps question id to the chosen option;
/// a missing entry means the question was skipped.
TestResult scoreTest({
  required List<Question> questions,
  required Map<String, int> answers,
  required MarkingScheme marking,
}) {
  var correct = 0;
  var wrong = 0;
  var skipped = 0;
  final perSubject = <String, (int correct, int total)>{};

  for (final q in questions) {
    final chosen = answers[q.id];
    final (c, t) = perSubject[q.subject] ?? (0, 0);
    if (chosen == null) {
      skipped++;
      perSubject[q.subject] = (c, t + 1);
    } else if (chosen == q.correctIndex) {
      correct++;
      perSubject[q.subject] = (c + 1, t + 1);
    } else {
      wrong++;
      perSubject[q.subject] = (c, t + 1);
    }
  }

  return TestResult(
    score: correct * marking.correct - wrong * marking.wrong,
    maxScore: questions.length * marking.correct,
    correct: correct,
    wrong: wrong,
    skipped: skipped,
    bySubject: [
      for (final e in perSubject.entries)
        SubjectScore(subject: e.key, correct: e.value.$1, total: e.value.$2),
    ],
  );
}

/// A précis question waiting for the ANO to set its answer and approve it.
class ReviewItem {
  const ReviewItem({
    required this.id,
    required this.prompt,
    required this.options,
    required this.source,
    this.page,
  });

  final String id;
  final String prompt;
  final List<String> options;

  /// Where it comes from, e.g. "Special Subject (Army) JD/JW (2025) · AF I · Q3".
  final String source;
  final int? page;
}
