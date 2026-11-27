import 'package:flutter_test/flutter_test.dart';
import 'package:phoenix/data/exam/b_cert_insights.dart';
import 'package:phoenix/data/exam/exam_data.dart';
import 'package:phoenix/data/exam/insights.dart';
import 'package:phoenix/domain/study_plan.dart';

void main() {
  final today = DateTime(2026, 11, 27, 20);

  test('blueprint adds up to the paper: 240 common + 110 special', () {
    expect(bCertInsights.marksFor(ExamPaper.common), 240);
    expect(bCertInsights.marksFor(ExamPaper.special), 110);
    expect(bCertInsights.ranked().first.name, 'Personality Development');
    expect(bCertInsights.ranked(ExamPaper.special).first.marks, 24);
    expect(bCertInsights.ranked().any((s) => s.name == 'Drill'), isFalse); // 0 written marks
  });

  test('every subject with précis chapters maps to official SD/SW chapters', () {
    final mr = chaptersFor(subjectNamed(bCertInsights, 'Map Reading')!);
    expect(mr.length, 10);
    expect(mr.map((c) => c.code), contains('MR-3'));
    expect(mr.firstWhere((c) => c.code == 'MR-3').share, greaterThan(0)); // most-asked chapter
    expect(chaptersFor(subjectNamed(bCertInsights, 'Obstacle Training')!), isEmpty); // not in the précis
  });

  test('plan fits before the exam, ends with mocks, and revises on day 1, 3 and 7', () {
    final plan = buildStudyPlan(
      insights: bCertInsights,
      chaptersBySubject: chaptersBySubject(bCertInsights),
      today: today,
      examDate: today.add(const Duration(days: 60)),
    );
    expect(plan.days.length, 60);
    expect(plan.days.first.date, DateTime(2026, 11, 27));
    expect(plan.days.last.date.isBefore(DateTime(2027, 1, 26)), isTrue);
    expect(plan.days.where((d) => d.kind == PlanDayKind.mock), isNotEmpty);
    expect(plan.days.sublist(plan.days.length - 10).every((d) => d.kind != PlanDayKind.learn), isTrue);

    // A chapter first studied on day N comes back on N+1, N+3 and N+7.
    final first = plan.days.first.items.firstWhere((i) => !i.revision && i.chapter != null).chapter!;
    final revisedOn = [
      for (var d = 0; d < plan.days.length; d++)
        if (plan.days[d].items.any((i) => i.revision && i.chapter == first)) d,
    ];
    expect(revisedOn, [1, 3, 7]);
  });

  test('heavier subjects come up first and more often', () {
    final plan = buildStudyPlan(
      insights: bCertInsights,
      chaptersBySubject: chaptersBySubject(bCertInsights),
      today: today,
      examDate: today.add(const Duration(days: 40)),
    );
    final learned = [for (final d in plan.days) for (final i in d.items) if (!i.revision && i.chapter != null) i.chapter!];
    expect(learned.first.subject, 'Personality Development');
    final firstTen = learned.take(10).map((c) => c.subject).toList();
    expect(firstTen.where((s) => s == 'Personality Development').length,
        greaterThan(firstTen.where((s) => s == 'Communication').length));
    // Within a subject, the most-asked chapter comes first.
    final wt = learned.where((c) => c.subject == 'Weapon Training').toList();
    expect(wt.first.share, greaterThanOrEqualTo(wt.last.share));
  });

  test('short on time: least important chapters are skipped and listed', () {
    final plan = buildStudyPlan(
      insights: bCertInsights,
      chaptersBySubject: chaptersBySubject(bCertInsights),
      today: today,
      examDate: today.add(const Duration(days: 10)),
    );
    expect(plan.skipped, isNotEmpty);
    expect(plan.days.length, 10);
  });

  test('exam today or past gives an empty plan', () {
    expect(buildStudyPlan(insights: bCertInsights, chaptersBySubject: const {}, today: today, examDate: today).isEmpty,
        isTrue);
  });
}
