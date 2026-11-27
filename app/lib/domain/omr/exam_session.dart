import '../../data/models/test.dart';
import 'exam_pattern.dart';

/// Where an OMR mock is for a cadet right now.
enum ExamPhase { waiting, paper, scanning, closed }

ExamPhase examPhase(TestDefinition t, DateTime now) {
  if (t.startedAt == null) return ExamPhase.waiting;
  if (now.isBefore(t.paperEndsAt!)) return ExamPhase.paper;
  if (t.closesAt == null || now.isBefore(t.closesAt!)) return ExamPhase.scanning;
  return ExamPhase.closed;
}

/// Half the cadets get Set A1, half A2, the same every time for a cadet and test.
String setFor(String cadetId, String testId) {
  var h = 0x811C9DC5;
  for (final c in '$cadetId|$testId'.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return h.isEven ? 'A1' : 'A2';
}

/// One question as printed on a cadet's paper.
class PaperItem {
  const PaperItem(this.number, this.question, this.paper, this.section);
  final int number; // on this set's sheet
  final Question question;
  final PatternPaper paper;
  final PatternSection section;
}

/// The paper for [set]: questions in that set's order, with the paper and
/// subject each belongs to. Set A2 reorders questions inside each paper.
List<PaperItem> paperFor(TestDefinition t, Map<String, Question> byId, String set) {
  final pattern = ExamPattern.byId(t.pattern ?? 'bcert');
  final a2 = set == 'A2' ? setA2Order(pattern, t.setSeed) : const <int, int>{};
  final items = <PaperItem>[];
  for (var i = 0; i < t.questionIds.length; i++) {
    final q = byId[t.questionIds[i]];
    if (q == null || i >= t.numbers.length) continue;
    final a1Number = t.numbers[i];
    final (paper, section) = pattern.slot(a1Number);
    items.add(PaperItem(a2[a1Number] ?? a1Number, q, paper, section));
  }
  items.sort((a, b) => a.number.compareTo(b.number));
  return items;
}

/// Scanned sheet answers (sheet number -> option, -1 for double marks) as
/// question id -> option for the server. Blank questions are left out.
Map<String, int> answersByQuestion(List<PaperItem> paper, Map<int, int?> sheet) => {
      for (final item in paper)
        if (sheet[item.number] != null) item.question.id: sheet[item.number]!,
    };

/// Marks lost per subject, worst first: (subject, lost, possible).
List<(String, double, double)> marksLostBySubject(List<PaperItem> paper, Map<int, int?> sheet, MarkingScheme m) {
  final lost = <String, double>{};
  final possible = <String, double>{};
  for (final item in paper) {
    final s = item.section.subject;
    possible[s] = (possible[s] ?? 0) + m.correct;
    final a = sheet[item.number];
    final got = a == null ? 0.0 : (a == item.question.correctIndex ? m.correct : -m.wrong);
    lost[s] = (lost[s] ?? 0) + (m.correct - got);
  }
  return [for (final s in possible.keys) (s, lost[s]!, possible[s]!)]..sort((a, b) => b.$2.compareTo(a.$2));
}

/// Each paper's marks and pass/fail for a cadet's sheet.
List<PaperResult> paperResultsFor(TestDefinition t, List<PaperItem> paper, Map<int, int?> sheet) {
  final pattern = ExamPattern.byId(t.pattern ?? 'bcert');
  final out = <PaperResult>[];
  for (final p in pattern.papers) {
    var score = 0.0, max = 0.0;
    for (final item in paper.where((i) => i.paper == p)) {
      max += t.marking.correct;
      final a = sheet[item.number];
      if (a == null) continue;
      score += a == item.question.correctIndex ? t.marking.correct : -t.marking.wrong;
    }
    if (max > 0) out.add(PaperResult(p, score, max, pattern.passPercent));
  }
  return out;
}
