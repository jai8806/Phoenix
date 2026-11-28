import '../../data/models/test.dart';
import 'exam_pattern.dart';

/// One answered question in an attempt, with what the question was about.
class AnsweredQuestion {
  const AnsweredQuestion(this.question, this.chosen);
  final Question question;
  final int? chosen; // null skipped, -1 double mark
  bool get correct => chosen == question.correctIndex;
}

/// One submitted attempt, as the progress screens need it.
class AttemptHistory {
  const AttemptHistory({
    required this.testId,
    required this.testTitle,
    required this.cadetId,
    required this.cadetName,
    required this.score,
    required this.marking,
    required this.answers,
    this.submittedAt,
    this.pattern,
  });

  final String testId;
  final String testTitle;
  final String cadetId;
  final String cadetName;
  final double score;
  final MarkingScheme marking;
  final List<AnsweredQuestion> answers;
  final DateTime? submittedAt;
  final String? pattern; // set for OMR mocks

  double get maxScore => answers.length * marking.correct;
  double get percent => maxScore == 0 ? 0 : score / maxScore * 100;
}

/// The exam subject a question counts towards (bank labels and précis
/// chapter codes both map to the paper's subject names).
String examSubject(Question q, {ExamPattern pattern = bCertPattern}) {
  for (final p in pattern.papers) {
    for (final s in p.sections) {
      if (s.matches(q)) return s.subject;
    }
  }
  // Subjects only in the other certificate's paper.
  final other = pattern.id == 'bcert' ? cCertPattern : bCertPattern;
  for (final p in other.papers) {
    for (final s in p.sections) {
      if (s.matches(q)) return s.subject;
    }
  }
  return q.subject;
}

class SubjectStat {
  SubjectStat(this.subject);
  final String subject;
  int correct = 0;
  int total = 0;
  double get accuracy => total == 0 ? 0 : correct / total;
}

/// Accuracy per exam subject over [attempts], weakest first.
List<SubjectStat> subjectStats(Iterable<AttemptHistory> attempts, {ExamPattern pattern = bCertPattern}) {
  final stats = <String, SubjectStat>{};
  for (final a in attempts) {
    for (final x in a.answers) {
      final s = stats.putIfAbsent(examSubject(x.question, pattern: pattern), () => SubjectStat(examSubject(x.question, pattern: pattern)));
      s.total++;
      if (x.correct) s.correct++;
    }
  }
  return stats.values.toList()..sort((a, b) => a.accuracy.compareTo(b.accuracy));
}

/// Marks a subject carries in [pattern] (0 when not in that paper).
double subjectMarks(String subject, ExamPattern pattern) {
  for (final p in pattern.papers) {
    for (final s in p.sections) {
      if (s.subject == subject) return s.count * pattern.marking.correct;
    }
  }
  return 0;
}

/// Each paper's percentage in an attempt, by the subjects its questions belong to.
List<(PatternPaper, double)> paperPercents(AttemptHistory a, ExamPattern pattern) {
  final out = <(PatternPaper, double)>[];
  for (final p in pattern.papers) {
    final subjects = {for (final s in p.sections) s.subject};
    var score = 0.0, max = 0.0;
    for (final x in a.answers) {
      if (!subjects.contains(examSubject(x.question, pattern: pattern))) continue;
      max += a.marking.correct;
      if (x.chosen == null) continue;
      score += x.correct ? a.marking.correct : -a.marking.wrong;
    }
    if (max > 0) out.add((p, score / max * 100));
  }
  return out;
}

/// A cadet whose latest mock would fail at least one paper.
class AtRisk {
  const AtRisk(this.cadetId, this.cadetName, this.testTitle, this.failing);
  final String cadetId;
  final String cadetName;
  final String testTitle;
  final List<(PatternPaper, double)> failing;
}

List<AtRisk> cadetsAtRisk(List<AttemptHistory> attempts) {
  final latest = <String, AttemptHistory>{};
  for (final a in attempts.where((a) => a.pattern != null)) {
    final prev = latest[a.cadetId];
    if (prev == null || (a.submittedAt ?? DateTime(0)).isAfter(prev.submittedAt ?? DateTime(0))) latest[a.cadetId] = a;
  }
  final out = <AtRisk>[];
  for (final a in latest.values) {
    final pattern = ExamPattern.byId(a.pattern!);
    final failing = [for (final p in paperPercents(a, pattern)) if (p.$2 < pattern.passPercent) p];
    if (failing.isNotEmpty) out.add(AtRisk(a.cadetId, a.cadetName, a.testTitle, failing));
  }
  out.sort((a, b) => a.failing.map((f) => f.$2).reduce((x, y) => x < y ? x : y).compareTo(b.failing.map((f) => f.$2).reduce((x, y) => x < y ? x : y)));
  return out;
}

/// Cadet -> subject -> accuracy, for the unit heatmap.
Map<String, Map<String, SubjectStat>> heatmap(List<AttemptHistory> attempts, {ExamPattern pattern = bCertPattern}) {
  final out = <String, Map<String, SubjectStat>>{};
  for (final a in attempts) {
    final row = out.putIfAbsent(a.cadetId, () => {});
    for (final x in a.answers) {
      final subject = examSubject(x.question, pattern: pattern);
      final s = row.putIfAbsent(subject, () => SubjectStat(subject));
      s.total++;
      if (x.correct) s.correct++;
    }
  }
  return out;
}
