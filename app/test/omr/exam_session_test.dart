import 'package:flutter_test/flutter_test.dart';
import 'package:phoenix/data/models/test.dart';
import 'package:phoenix/domain/omr/exam_pattern.dart';
import 'package:phoenix/domain/omr/exam_session.dart';

Question q(String id, String subject, {int correct = 0}) =>
    Question(id: id, subject: subject, prompt: '$id?', options: const ['a', 'b', 'c', 'd'], correctIndex: correct);

void main() {
  final bank = [
    for (var i = 0; i < 20; i++) q('wt$i', 'Weapon Training'),
    for (var i = 0; i < 40; i++) q('pd$i', 'Personality Development', correct: 1),
    for (var i = 0; i < 15; i++) q('mr$i', 'MR III', correct: 2), // a précis chapter code
  ];

  test('the B Cert pattern has the 2026 paper shape', () {
    expect(bCertPattern.questionCount, 175);
    expect(bCertPattern.totalMarks, 350);
    expect([for (final p in bCertPattern.papers) p.count], [15, 105, 55]);
    expect(cCertPattern.questionCount, 175);
    expect(bCertPattern.slot(1).$2.subject, 'Weapon Training');
    expect(bCertPattern.slot(16).$2.subject, 'NCC General');
    expect(bCertPattern.slot(121).$2.subject, 'Armed Forces');
    expect(bCertPattern.slot(175).$2.subject, 'Communication');
  });

  test('questions go to their own section; short sections are reported', () {
    final pick = pickForPattern(bCertPattern, bank);
    for (var n = 1; n <= 15; n++) {
      expect(pick.byNumber[n], startsWith('wt'));
    }
    // Personality Development is sheet numbers 29-58 (after NCC General 3 and NI 10).
    expect(pick.byNumber[29], startsWith('pd'));
    final mrStart = 121 + 10; // after Armed Forces
    expect(pick.byNumber[mrStart], startsWith('mr'));
    expect(pick.shortfall['Leadership'], 9);
    expect(pick.shortfall.containsKey('Weapon Training'), isFalse);
  });

  test('Set A2 reorders within each paper only, and maps back', () {
    final a2 = setA2Order(bCertPattern, 42);
    expect(a2.keys.toSet(), a2.values.toSet());
    for (final e in a2.entries) {
      expect(bCertPattern.slot(e.key).$1, same(bCertPattern.slot(e.value).$1));
    }
    expect(a2.entries.where((e) => e.key != e.value).length, greaterThan(100));
  });

  test('a cadet on Set A2 is marked against the right questions', () {
    final pick = pickForPattern(bCertPattern, bank);
    final entries = pick.byNumber.entries.toList();
    final t = TestDefinition(
      id: 't', title: 'Mock', durationMinutes: 180, marking: bCertPattern.marking,
      questionIds: [for (final e in entries) e.value], numbers: [for (final e in entries) e.key],
      mode: TestMode.omr, pattern: 'bcert', setSeed: 42,
    );
    final byId = {for (final x in bank) x.id: x};
    final paper = paperFor(t, byId, 'A2');
    // Fill every bubble with the right answer on the A2 sheet.
    final sheet = {for (final item in paper) item.number: item.question.correctIndex};
    final answers = answersByQuestion(paper, sheet);
    expect(answers.length, paper.length);
    for (final e in answers.entries) {
      expect(e.value, byId[e.key]!.correctIndex);
    }
    final results = paperResultsFor(t, paper, sheet);
    expect(results.every((r) => r.passed), isTrue);
    expect(results.first.max, 30);
    // A blank sheet fails every paper; nothing is lost twice.
    final blank = paperResultsFor(t, paper, const {});
    expect(blank.every((r) => !r.passed), isTrue);
    expect(marksLostBySubject(paper, const {}, t.marking).first.$2, 60); // Personality Development, 30 x 2
  });

  test('phases follow the clock and the ANO', () {
    final start = DateTime(2026, 12, 1, 9);
    final t = TestDefinition(id: 't', title: 'Mock', durationMinutes: 180, marking: const MarkingScheme(),
        questionIds: const [], mode: TestMode.omr, uploadMinutes: 20);
    expect(examPhase(t, start), ExamPhase.waiting);
    final live = t.copyWith(startedAt: start, closesAt: start.add(const Duration(minutes: 200)));
    expect(examPhase(live, start.add(const Duration(minutes: 10))), ExamPhase.paper);
    expect(examPhase(live, start.add(const Duration(minutes: 185))), ExamPhase.scanning);
    expect(examPhase(live, start.add(const Duration(minutes: 201))), ExamPhase.closed);
  });

  test('sets are split between cadets and stable', () {
    final sets = [for (var i = 0; i < 200; i++) setFor('cadet$i', 'test1')];
    expect(sets.where((s) => s == 'A1').length, inInclusiveRange(70, 130));
    expect(setFor('cadet7', 'test1'), setFor('cadet7', 'test1'));
  });
}
