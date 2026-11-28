import 'package:flutter_test/flutter_test.dart';
import 'package:phoenix/data/models/test.dart';
import 'package:phoenix/domain/omr/exam_pattern.dart';
import 'package:phoenix/domain/omr/progress.dart';

Question q(String id, String subject) => Question(id: id, subject: subject, prompt: '?', options: const ['a', 'b', 'c', 'd'], correctIndex: 0);

AttemptHistory attempt(String cadet, {required int wtRight, required int mrRight, DateTime? at, String? pattern = 'bcert'}) =>
    AttemptHistory(
      testId: 't',
      testTitle: 'Mock',
      cadetId: cadet,
      cadetName: cadet,
      score: 0,
      marking: const MarkingScheme(correct: 2, wrong: 0.5),
      submittedAt: at,
      pattern: pattern,
      answers: [
        for (var i = 0; i < 10; i++) AnsweredQuestion(q('wt$i', 'Weapon Training'), i < wtRight ? 0 : 1),
        for (var i = 0; i < 10; i++) AnsweredQuestion(q('mr$i', 'MR III'), i < mrRight ? 0 : 1), // précis code
      ],
    );

void main() {
  test('précis chapter codes count towards their exam subject', () {
    expect(examSubject(q('x', 'MR III')), 'Map Reading');
    expect(examSubject(q('x', 'FCBC II')), 'Field Craft & Battle Craft');
    expect(examSubject(q('x', 'Health and Hygiene')), 'Health & Hygiene');
    expect(examSubject(q('x', 'Environmental Awareness And Conservation')), 'Environment Awareness'); // C Cert only
  });

  test('subject accuracy is weakest first', () {
    final stats = subjectStats([attempt('a', wtRight: 9, mrRight: 3), attempt('a', wtRight: 7, mrRight: 5)]);
    expect(stats.first.subject, 'Map Reading');
    expect(stats.first.accuracy, closeTo(0.4, 1e-9));
    expect(stats.last.accuracy, closeTo(0.8, 1e-9));
    expect(subjectMarks('Map Reading', bCertPattern), 24);
  });

  test('paper percentages and the at-risk list use each cadet\'s latest mock', () {
    final early = DateTime(2026, 11, 1), late = DateTime(2026, 12, 1);
    final attempts = [
      attempt('ok', wtRight: 2, mrRight: 2, at: early), // failed earlier...
      attempt('ok', wtRight: 9, mrRight: 9, at: late), // ...passes now
      attempt('weak', wtRight: 9, mrRight: 1, at: late), // Paper IV (Map Reading) at -25%
      attempt('app', wtRight: 0, mrRight: 0, at: late, pattern: null), // in-app tests don't count here
    ];
    final risk = cadetsAtRisk(attempts);
    expect(risk.map((r) => r.cadetId), ['weak']);
    expect(risk.single.failing.single.$1.title, contains('SPECIAL SUBJECT'));
    final papers = paperPercents(attempts[2], bCertPattern);
    expect(papers.first.$2, closeTo((9 * 2 - 1 * 0.5) / 20 * 100, 1e-9));
  });

  test('heatmap: cadet by subject', () {
    final map = heatmap([attempt('a', wtRight: 10, mrRight: 0), attempt('b', wtRight: 5, mrRight: 5)]);
    expect(map['a']!['Weapon Training']!.accuracy, 1);
    expect(map['a']!['Map Reading']!.accuracy, 0);
    expect(map['b']!['Map Reading']!.accuracy, 0.5);
  });
}
