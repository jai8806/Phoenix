import 'package:flutter_test/flutter_test.dart';
import 'package:phoenix/data/models/diary.dart';
import 'package:phoenix/data/models/test.dart';
import 'package:phoenix/domain/diary_stats.dart';
import 'package:phoenix/domain/eligibility.dart';

void main() {
  group('checkEligibility', () {
    test('cadet below 75% learns exactly how many periods are needed', () {
      // 60/90 = 66.7%. Need x with (60 + x) / (90 + x) >= 0.75 -> x = 30.
      final s = checkEligibility(
          rule: bCertificateRule, periodsAttended: 60, periodsHeld: 90, campDone: true);
      expect(s.periodsNeeded, 30);
      expect(s.isEligible, isFalse);
      expect(s.blockers, ['Attend 30 more training periods']);
      // Attending those 30 lands exactly on 75%.
      expect((60 + 30) / (90 + 30), 0.75);
    });

    test('exactly 75% with a camp is eligible', () {
      final s = checkEligibility(
          rule: bCertificateRule, periodsAttended: 75, periodsHeld: 100, campDone: true);
      expect(s.periodsNeeded, 0);
      expect(s.isEligible, isTrue);
      expect(s.blockers, isEmpty);
    });

    test('missing camp blocks eligibility even with full attendance', () {
      final s = checkEligibility(
          rule: bCertificateRule, periodsAttended: 40, periodsHeld: 40, campDone: false);
      expect(s.isEligible, isFalse);
      expect(s.blockers, ['Attend an Annual Training Camp']);
    });

    test('C certificate needs the B certificate', () {
      final without = checkEligibility(
          rule: cCertificateRule, periodsAttended: 40, periodsHeld: 40, campDone: true);
      expect(without.isEligible, isFalse);
      expect(without.blockers, ['Hold the B certificate']);

      final withB = checkEligibility(
          rule: cCertificateRule,
          periodsAttended: 40,
          periodsHeld: 40,
          campDone: true,
          certificatesHeld: {'B'});
      expect(withB.isEligible, isTrue);
    });

    test('no periods held yet means nothing is owed', () {
      final s = checkEligibility(
          rule: bCertificateRule, periodsAttended: 0, periodsHeld: 0, campDone: false);
      expect(s.periodsNeeded, 0);
      expect(s.attendance, 0);
    });

    test('singular wording for one period', () {
      // 2/3 = 66.7%; (2 + 1) / (3 + 1) = 75%.
      final s = checkEligibility(
          rule: bCertificateRule, periodsAttended: 2, periodsHeld: 3, campDone: true);
      expect(s.blockers, ['Attend 1 more training period']);
    });
  });

  group('scoreTest', () {
    const qs = [
      Question(id: 'a', subject: 'Drill', prompt: '', options: ['x', 'y'], correctIndex: 0),
      Question(id: 'b', subject: 'Drill', prompt: '', options: ['x', 'y'], correctIndex: 1),
      Question(id: 'c', subject: 'Map Reading', prompt: '', options: ['x', 'y'], correctIndex: 0),
      Question(id: 'd', subject: 'Map Reading', prompt: '', options: ['x', 'y'], correctIndex: 0),
    ];

    test('applies positive and negative marking', () {
      final r = scoreTest(
        questions: qs,
        answers: {'a': 0, 'b': 0, 'c': 0}, // right, wrong, right, skipped
        marking: const MarkingScheme(correct: 2, wrong: 0.5),
      );
      expect(r.correct, 2);
      expect(r.wrong, 1);
      expect(r.skipped, 1);
      expect(r.score, 3.5);
      expect(r.maxScore, 8);
    });

    test('reports weak subjects weakest first', () {
      final r = scoreTest(
        questions: qs,
        answers: {'a': 0, 'b': 1, 'c': 1, 'd': 1},
        marking: const MarkingScheme(),
      );
      expect(r.weakSubjects.map((s) => s.subject), ['Map Reading']);
      expect(r.bySubject.firstWhere((s) => s.subject == 'Drill').accuracy, 1);
    });
  });

  group('computeDiaryStats', () {
    final today = DateTime(2026, 11, 26, 18);
    DiaryEntry shot(int daysAgo, int score, double group) => DiaryEntry(
          id: 's$daysAgo',
          type: SessionType.shooting,
          date: today.subtract(Duration(days: daysAgo)),
          shooting: ShootingMetrics(
            rifle: '.22',
            position: ShootingPosition.prone,
            distanceMetres: 25,
            rounds: 5,
            score: score,
            groupMm: group,
          ),
        );

    test('streak counts back from today', () {
      final entries = [
        DiaryEntry(id: '1', type: SessionType.pt, date: today),
        DiaryEntry(id: '2', type: SessionType.drill, date: today.subtract(const Duration(days: 1))),
        DiaryEntry(id: '3', type: SessionType.drill, date: today.subtract(const Duration(days: 2))),
        DiaryEntry(id: '4', type: SessionType.drill, date: today.subtract(const Duration(days: 4))),
      ];
      expect(computeDiaryStats(entries, today: today).streakDays, 3);
    });

    test('streak survives if today is not logged yet', () {
      final entries = [
        DiaryEntry(id: '1', type: SessionType.pt, date: today.subtract(const Duration(days: 1))),
        DiaryEntry(id: '2', type: SessionType.pt, date: today.subtract(const Duration(days: 2))),
      ];
      expect(computeDiaryStats(entries, today: today).streakDays, 2);
    });

    test('shooting trend compares first and latest three sessions', () {
      final entries = [
        shot(20, 30, 20),
        shot(18, 32, 18),
        shot(16, 33, 16),
        shot(6, 40, 12),
        shot(4, 42, 11),
        shot(2, 44, 10),
      ];
      final s = computeDiaryStats(entries, today: today);
      expect(s.shootingSessions, 6);
      expect(s.bestScore, 44);
      expect(s.averageScore, closeTo(36.83, 0.01));
      expect(s.firstGroupMm, 18);
      expect(s.latestGroupMm, 11);
      expect(s.groupImprovementMm, 7);
    });

    test('sessions older than 30 days are not counted as recent', () {
      final entries = [
        DiaryEntry(id: '1', type: SessionType.pt, date: today.subtract(const Duration(days: 29))),
        DiaryEntry(id: '2', type: SessionType.pt, date: today.subtract(const Duration(days: 30))),
      ];
      expect(computeDiaryStats(entries, today: today).sessionsLast30Days, 1);
    });
  });
}
