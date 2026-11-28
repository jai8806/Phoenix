import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:phoenix/data/exam/cert_insights.dart';
import 'package:phoenix/data/models/test.dart';
import 'package:phoenix/domain/hosted_tests.dart';

Question q(String id, String subject, {int correct = 0}) =>
    Question(id: id, subject: subject, prompt: '$id?', options: const ['a', 'b', 'c', 'd'], correctIndex: correct);

void main() {
  final bank = [
    for (var i = 0; i < 60; i++) q('pd$i', 'Personality Development'),
    for (var i = 0; i < 60; i++) q('wt$i', 'Weapon Training'),
    for (var i = 0; i < 3; i++) q('adv$i', 'Adventure'),
  ];

  test('exam pattern gives bigger subjects more questions', () {
    final ids = pickTestQuestions(bank: bank, insights: bCertInsights, count: 40, rng: Random(1));
    expect(ids, hasLength(40));
    expect(ids.toSet(), hasLength(40));
    final pd = ids.where((i) => i.startsWith('pd')).length;
    final wt = ids.where((i) => i.startsWith('wt')).length;
    expect(pd, greaterThan(wt)); // 60 marks vs 30 in the paper
    expect(ids.where((i) => i.startsWith('adv')).length, lessThanOrEqualTo(3));
  });

  test('chosen subjects split evenly and top up when one runs short', () {
    final ids = pickTestQuestions(
        bank: bank, insights: bCertInsights, count: 20, subjects: {'Adventure', 'Weapon Training'}, rng: Random(2));
    expect(ids, hasLength(20));
    expect(ids.where((i) => i.startsWith('adv')), hasLength(3));
    expect(ids.where((i) => i.startsWith('wt')), hasLength(17));
    expect(ids.any((i) => i.startsWith('pd')), isFalse);
  });

  test('asking for more than the bank has returns what there is', () {
    final ids = pickTestQuestions(bank: bank, insights: bCertInsights, count: 50, subjects: {'Adventure'});
    expect(ids, hasLength(3));
    expect(pickTestQuestions(bank: bank, insights: bCertInsights, count: 10, subjects: {'Leadership'}), isEmpty);
  });

  test('bank counts per subject', () {
    final counts = bankCountBySubject(bank, bCertInsights);
    expect(counts['Personality Development'], 60);
    expect(counts['Leadership'], 0);
  });

  test('report ranks scores, finds weak subjects and the most missed questions', () {
    final questions = [q('a', 'Drill'), q('b', 'Drill'), q('c', 'Map Reading', correct: 2)];
    final report = summarizeAttempts(
      questions: questions,
      marking: const MarkingScheme(correct: 2, wrong: 0.5),
      attempts: const [
        AttemptRecord(cadetId: '1', cadetName: 'A', score: 4, answers: {'a': 0, 'b': 0, 'c': 1}),
        AttemptRecord(cadetId: '2', cadetName: 'B', score: 6, answers: {'a': 0, 'b': 0, 'c': 2}),
        AttemptRecord(cadetId: '3', cadetName: 'C', score: 1.5, answers: {'a': 0, 'b': 1, 'c': null}),
      ],
    );
    expect(report.attempts.map((a) => a.cadetName), ['B', 'A', 'C']);
    expect(report.average, closeTo(3.83, 0.01));
    expect(report.maxScore, 6);
    expect(report.percent(report.highest), 100);
    expect(report.bySubject.first.subject, 'Map Reading'); // 1 of 3 right
    expect(report.hardest.first.question.id, 'c');
    expect(report.hardest.first.answered, 2);
  });

  test('average percentage per cadet across tests', () {
    const tests = [
      TestDefinition(id: 't1', title: 'A', durationMinutes: 10, marking: MarkingScheme(), questionIds: ['1', '2']),
      TestDefinition(id: 't2', title: 'B', durationMinutes: 10, marking: MarkingScheme(), questionIds: ['1']),
    ];
    final avg = averagePercentByCadet(const [
      ScoreRow(testId: 't1', cadetId: 'x', score: 2), // 50%
      ScoreRow(testId: 't2', cadetId: 'x', score: 2), // 100%
      ScoreRow(testId: 'gone', cadetId: 'y', score: 2),
    ], tests);
    expect(avg, {'x': 75});
  });
}
