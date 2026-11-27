import '../data/exam/insights.dart';

/// A chapter to study, with how much the exam leans on it.
class StudyChapter {
  const StudyChapter({required this.subject, required this.code, required this.title, this.share = 0});

  final String subject;
  final String code;
  final String title;

  /// Share of the subject's past questions from this chapter (0 if unknown).
  final double share;
}

enum PlanDayKind { learn, finalRevision, mock }

class PlanItem {
  const PlanItem.learn(this.chapter) : revision = false, label = null;
  const PlanItem.revise(this.chapter) : revision = true, label = null;
  const PlanItem.task(this.label) : chapter = null, revision = false;

  final StudyChapter? chapter;
  final bool revision;

  /// Free-text task, e.g. "Full 350-mark mock test".
  final String? label;
}

class PlanDay {
  const PlanDay({required this.date, required this.kind, required this.items});

  final DateTime date;
  final PlanDayKind kind;
  final List<PlanItem> items;
}

class StudyPlan {
  const StudyPlan({required this.days, required this.skipped});

  final List<PlanDay> days;

  /// Low-weight chapters left out because there wasn't enough time.
  final List<StudyChapter> skipped;

  bool get isEmpty => days.isEmpty;
}

/// Revision gaps in days after first study (spaced repetition).
const reviseAfter = [1, 3, 7];

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Builds a day-by-day plan from today to the day before the exam.
///
/// * The last fifth of the time (up to 10 days, at least 1 when possible) is
///   for final revision and full mock tests on alternate days.
/// * Learning days cover chapters in an order weighted by marks, so heavy
///   subjects come up more often, and within a subject the most-asked
///   chapters first. If time is short, the least important chapters are
///   skipped (and listed) rather than squeezed in.
/// * Each chapter is revised 1, 3 and 7 days after it is first studied.
StudyPlan buildStudyPlan({
  required ExamInsights insights,
  required Map<String, List<StudyChapter>> chaptersBySubject,
  required DateTime today,
  required DateTime examDate,
  int chaptersPerDay = 2,
}) {
  final start = _day(today);
  final totalDays = _day(examDate).difference(start).inDays;
  if (totalDays <= 0) return const StudyPlan(days: [], skipped: []);

  final finalDays = totalDays < 3 ? 0 : (totalDays * 0.2).round().clamp(1, 10);
  final learnDays = totalDays - finalDays;

  // Chapters per subject, most-asked first.
  final subjects = insights.ranked();
  final queues = <String, List<StudyChapter>>{};
  for (final s in subjects) {
    final list = List.of(chaptersBySubject[s.name] ?? const <StudyChapter>[])
      ..sort((a, b) => b.share.compareTo(a.share));
    if (list.isNotEmpty) queues[s.name] = list;
  }

  // Weighted round robin: each step, the subject with the most "credit" goes next.
  final order = <StudyChapter>[];
  final credit = {for (final s in subjects) s.name: 0.0};
  final totalMarks = subjects.fold(0, (a, s) => a + s.marks);
  final capacity = learnDays * chaptersPerDay;
  while (order.length < capacity && queues.values.any((q) => q.isNotEmpty)) {
    for (final s in subjects) {
      if (queues[s.name]?.isNotEmpty ?? false) credit[s.name] = credit[s.name]! + s.marks;
    }
    final next = subjects
        .where((s) => queues[s.name]?.isNotEmpty ?? false)
        .reduce((a, b) => credit[a.name]! >= credit[b.name]! ? a : b);
    credit[next.name] = credit[next.name]! - totalMarks;
    order.add(queues[next.name]!.removeAt(0));
  }
  final skipped = [for (final q in queues.values) ...q];

  final days = <PlanDay>[];
  final firstStudied = <StudyChapter, int>{};
  var cursor = 0;
  for (var d = 0; d < learnDays; d++) {
    final items = <PlanItem>[];
    for (var k = 0; k < chaptersPerDay && cursor < order.length; k++) {
      final ch = order[cursor++];
      firstStudied[ch] = d;
      items.add(PlanItem.learn(ch));
    }
    for (final e in firstStudied.entries) {
      if (e.value != d && reviseAfter.contains(d - e.value)) items.add(PlanItem.revise(e.key));
    }
    if (items.isEmpty) items.add(const PlanItem.task('Practise 30 questions from your weakest subject'));
    days.add(PlanDay(date: start.add(Duration(days: d)), kind: PlanDayKind.learn, items: items));
  }

  for (var f = 0; f < finalDays; f++) {
    final date = start.add(Duration(days: learnDays + f));
    final isMock = f.isEven;
    if (isMock) {
      days.add(PlanDay(date: date, kind: PlanDayKind.mock, items: [
        PlanItem.task('Full ${insights.totalMarks}-mark mock test (${insights.durationMinutes ~/ 60} h, timed)'),
        const PlanItem.task('Review every wrong answer against the précis'),
      ]));
    } else {
      // Revise the heaviest subjects again, rotating through them.
      final heavy = subjects.take(4).toList();
      final pick = heavy.isEmpty ? null : heavy[(f ~/ 2) % heavy.length];
      days.add(PlanDay(date: date, kind: PlanDayKind.finalRevision, items: [
        if (pick != null) PlanItem.task('Revise ${pick.name} (${pick.marks} marks): notes and most-asked chapters'),
        const PlanItem.task('Past-paper questions: 50 in exam conditions'),
      ]));
    }
  }
  return StudyPlan(days: days, skipped: skipped);
}

/// How-to-revise guidance shown in the app.
const revisionTips = <(String, String)>[
  ('Start with the heavy subjects',
      'Personality Development, SSCD and Weapon Training carry over half the Common paper; Map Reading and Field Craft lead the Special paper.'),
  ('Learn the précis wording',
      'Questions use the book\'s own phrases. Read the chapter, then answer from memory before checking.'),
  ('Revise on day 1, 3 and 7',
      'Coming back to a chapter after a gap fixes it in memory far better than rereading it the same day.'),
  ('Practise with past questions',
      'Do the bank questions for each chapter you finish. Mark wrong ones and redo them two days later.'),
  ('Take full mocks under time',
      '175 questions in 3 hours is about a minute each. Practise the pace so nothing is left blank.'),
  ('Don\'t skip low-mark subjects completely',
      'NCC General, Obstacle Training and Communication are only a few marks each, but they are quick to learn.'),
];
