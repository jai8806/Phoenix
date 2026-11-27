import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../data/exam/exam_data.dart';
import '../../data/exam/insights.dart';
import '../../data/models/test.dart';
import '../../data/models/user.dart';
import '../../data/providers.dart';
import '../../data/syllabus/syllabus.dart';
import '../shared/widgets.dart';
import 'study_screens.dart';

class LearnScreen extends ConsumerStatefulWidget {
  const LearnScreen({super.key});

  @override
  ConsumerState<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends ConsumerState<LearnScreen> {
  SyllabusLevel? _level;
  ExamPaper _paper = ExamPaper.common;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider);
    final level = _level ?? SyllabusLevel.of(user?.division);
    final wing = user?.wing ?? Wing.army;
    final now = ref.watch(clockProvider)();
    final tests = ref.watch(testsProvider);
    final track = ref.watch(certTrackProvider);
    final insights = insightsFor(track);
    final plan = ref.watch(studyPlanProvider);
    final exam = ref.watch(examDateProvider);
    final bank = ref.watch(questionBankProvider);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final ranked = insights.ranked(_paper);
    final todayPlan = plan == null || plan.isEmpty ? null : plan.days.first;

    return Scaffold(
      appBar: AppBar(title: const Text('Learn')),
      body: PageBody(children: [
        SegmentedButton<CertTrack>(
          segments: [for (final tr in CertTrack.values) ButtonSegment(value: tr, label: Text(tr.label))],
          selected: {track},
          onSelectionChanged: (s) => ref.read(certTrackProvider.notifier).set(s.first),
        ),
        const SizedBox(height: Space.lg),
        _ExamHero(insights: insights, track: track),
        const SectionHeader('Where the marks are'),
        SegmentedButton<ExamPaper>(
          segments: [
            for (final p in ExamPaper.values)
              ButtonSegment(value: p, label: Text('${p == ExamPaper.common ? 'Common' : 'Special'} · ${insights.marksFor(p)}')),
          ],
          selected: {_paper},
          onSelectionChanged: (s) => setState(() => _paper = s.first),
        ),
        const SizedBox(height: Space.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.md),
            child: Column(children: [
              for (final s in ranked)
                WeightRow(
                  subject: s,
                  maxMarks: ranked.first.marks,
                  totalMarks: insights.totalMarks,
                  onTap: () => context.push(Routes.subject(s.name)),
                ),
              const SizedBox(height: Space.sm),
              Text(
                'Tap a subject for its most-asked chapters. Based on ${insights.questionsAnalysed} questions '
                'from the question banks and the 2024 paper; the 2026 papers use the same marks per subject.',
                style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
            ]),
          ),
        ),
        const SectionHeader('Plan and revise'),
        ListCard(children: [
          ListTile(
            leading: const Icon(Icons.event_note_outlined),
            title: const Text('Your study plan'),
            subtitle: Text(exam == null
                ? 'Set your exam date to get a day-by-day plan'
                : todayPlan == null
                    ? 'Exam date has passed: set the next one'
                    : 'Today: ${todayPlan.items.length} task${todayPlan.items.length == 1 ? '' : 's'} · '
                        '${exam.difference(DateTime(now.year, now.month, now.day)).inDays} days to go'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.plan),
          ),
          ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('How to revise'),
            subtitle: const Text('Six habits that move your score'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showRevisionTips(context),
          ),
        ]),
        const SectionHeader('Practice'),
        ListCard(children: [
          ListTile(
            leading: const Icon(Icons.bolt_outlined),
            title: const Text('Quick practice'),
            subtitle: const Text('10 questions, mixed subjects'),
            trailing: const Icon(Icons.play_arrow),
            onTap: () => context.push(Routes.quiz('practice')),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text('Full ${insights.totalMarks}-mark mock'),
            subtitle: Text(bank.length < 40
                ? 'Unlocks when your unit has approved more questions (${bank.length} so far)'
                : '${insights.questionCount} questions in the exam pattern · ${insights.durationMinutes ~/ 60} h'),
            trailing: const Icon(Icons.play_arrow),
            enabled: bank.length >= 40,
            onTap: () => context.push(Routes.quiz('mock')),
          ),
        ]),
        Card(
          child: ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: const Text('My progress'),
            subtitle: const Text('Scores over time, weak subjects, would you pass today'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.progress),
          ),
        ),
        const SectionHeader('Tests from your unit'),
        if (tests.isEmpty)
          const EmptyState(icon: Icons.quiz_outlined, title: 'No tests yet',
              message: 'Tests your ANO or senior cadets host will appear here. Meanwhile, use Quick practice.')
        else
          ListCard(children: [
            for (final test in tests) _TestTile(test: test, now: now),
          ]),
        const _PrecisBooks(),
        const SectionHeader('Study library'),
        const StudyLibraryCard(),
        SectionHeader('Study material · ${wing.label}'),
        SegmentedButton<SyllabusLevel>(
          segments: [for (final l in SyllabusLevel.values) ButtonSegment(value: l, label: Text(l.label))],
          selected: {level},
          onSelectionChanged: (s) => setState(() => _level = s.first),
        ),
        const SizedBox(height: Space.md),
        _SyllabusCard(syllabus: specialSyllabus(wing, level)),
        const SizedBox(height: Space.md),
        _SyllabusCard(syllabus: commonSyllabus(level)),
      ]),
    );
  }
}

class _ExamHero extends StatelessWidget {
  const _ExamHero({required this.insights, required this.track});

  final ExamInsights insights;
  final CertTrack track;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final on = c.onPrimary;
    Widget fact(String value, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: t.headlineSmall?.copyWith(color: on, height: 1)),
            const SizedBox(height: 2),
            Text(label.toUpperCase(), style: t.labelSmall?.copyWith(color: on.withValues(alpha: 0.75), letterSpacing: 1)),
          ]),
        );
    return Card(
      color: c.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${track.label.toUpperCase()} · WRITTEN EXAM',
              style: t.labelMedium?.copyWith(color: on.withValues(alpha: 0.8), letterSpacing: 1.2)),
          const SizedBox(height: Space.lg),
          Row(children: [
            fact('${insights.totalMarks}', 'marks'),
            fact('${insights.questionCount}', 'questions'),
            fact('${insights.durationMinutes ~/ 60} h', 'time'),
          ]),
          const SizedBox(height: Space.lg),
          Text('Pass: ${insights.passRule} · +2 per right answer'
              '${insights.negativeMarks > 0 ? ', −${insights.negativeMarks} per wrong' : ''}',
              style: t.bodySmall?.copyWith(color: on.withValues(alpha: 0.85))),
          if (insights.negativeNote.contains('assumed'))
            Text(insights.negativeNote, style: t.bodySmall?.copyWith(color: on.withValues(alpha: 0.65))),
          Text(insights.source, style: t.bodySmall?.copyWith(color: on.withValues(alpha: 0.65))),
        ]),
      ),
    );
  }
}

class _TestTile extends StatelessWidget {
  const _TestTile({required this.test, required this.now});

  final TestDefinition test;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final m = test.marking;
    final neg = m.wrong == 0 ? 'no negative marking' : '−${_fmt(m.wrong)} per wrong';
    final d = DateFormat('EEE d MMM, h:mm a');
    final c = Theme.of(context).colorScheme;
    void go() => context.push(Routes.quiz(test.id));

    if (test.isOmr && !test.attempted) {
      final live = test.startedAt != null && !test.hasClosed(now);
      return ListTile(
        leading: Icon(Icons.description_outlined, color: live ? c.primary : null),
        title: Text(test.title),
        subtitle: Text(test.startedAt == null
            ? 'OMR mock · ${test.questionIds.length} Q · 3 h · waiting for your ANO to start'
            : live
                ? (now.isBefore(test.paperEndsAt!) ? 'Live now · open the question paper' : 'Scan your OMR sheet now')
                : 'Closed · missed'),
        trailing: test.hasClosed(now) ? null : FilledButton.tonal(onPressed: () => context.push(Routes.exam(test.id)), child: Text(live ? 'Open' : 'Get ready')),
        onTap: test.hasClosed(now) ? null : () => context.push(Routes.exam(test.id)),
      );
    }
    if (test.attempted) {
      final closed = test.hasClosed(now);
      return ListTile(
        leading: const Icon(Icons.task_alt),
        title: Text(test.title),
        subtitle: Text('Scored ${_fmt(test.myScore!)} / ${_fmt(test.maxScore)} · '
            '${closed ? 'answer key open' : 'answer key after it closes'}'),
        trailing: closed ? const Icon(Icons.chevron_right) : null,
        onTap: go,
      );
    }
    if (!test.hasOpened(now)) {
      return ListTile(
        leading: const Icon(Icons.lock_clock_outlined),
        title: Text(test.title),
        subtitle: Text('Opens ${d.format(test.opensAt!)}'),
      );
    }
    if (test.hasClosed(now)) {
      return ListTile(
        leading: Icon(Icons.event_busy_outlined, color: c.onSurfaceVariant),
        title: Text(test.title),
        subtitle: const Text('Closed · missed'),
      );
    }
    return ListTile(
      leading: const Icon(Icons.assignment_outlined),
      title: Text(test.title),
      subtitle: Text([
        '${test.questionIds.length} Q · ${test.durationMinutes} min · $neg',
        if (test.closesAt != null) 'closes ${d.format(test.closesAt!)}',
        'one attempt',
      ].join(' · ')),
      trailing: FilledButton.tonal(onPressed: go, child: const Text('Start')),
    );
  }
}

String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

class _SyllabusCard extends StatelessWidget {
  const _SyllabusCard({required this.syllabus});

  final Syllabus syllabus;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.sm),
          child: Row(children: [
            Icon(syllabus.official ? Icons.verified_outlined : Icons.pending_outlined, size: 18,
                color: syllabus.official ? c.primary : c.onSurfaceVariant),
            const SizedBox(width: Space.sm),
            Expanded(child: Text(syllabus.source, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant))),
            if (!syllabus.official) const DemoBadge(text: 'Provisional'),
          ]),
        ),
        for (final g in syllabus.groups) _GroupTile(group: g, showPeriods: syllabus.hasPeriods),
      ]),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.showPeriods});

  final SubjectGroup group;
  final bool showPeriods;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final n = group.subjects.length;
    return ExpansionTile(
      shape: const Border(),
      title: Text(group.name, style: t.titleSmall),
      subtitle: Text([
        '$n subject${n == 1 ? '' : 's'}',
        if (showPeriods) '${group.totalPeriods} periods',
      ].join(' · ')),
      children: [
        for (final s in group.subjects)
          ListTile(
            dense: true,
            leading: s.code.isEmpty
                ? const Icon(Icons.article_outlined, size: 20)
                : SizedBox(
                    width: 64,
                    child: Text(s.code, style: t.labelMedium?.copyWith(color: c.primary)),
                  ),
            title: Text(s.title),
            subtitle: showPeriods
                ? Text([
                    if (s.theoryPeriods > 0) '${s.theoryPeriods} theory',
                    if (s.practicalPeriods > 0) '${s.practicalPeriods} practical',
                    if (s.page != null) 'p. ${s.page}',
                  ].join(' · '))
                : null,
          ),
      ],
    );
  }
}

/// Opens the unit's Drive folder with every précis, past paper, question bank and note.
class StudyLibraryCard extends StatelessWidget {
  const StudyLibraryCard({super.key});

  static const _sections = [
    (Icons.menu_book_outlined, 'Précis 2025', 'Army, Tech Skills, NB & CP, Life Skills'),
    (Icons.history_edu_outlined, 'Past papers', 'B Cert 2024, 2026 (with keys) · C Cert 2024-25'),
    (Icons.quiz_outlined, 'Question banks', 'Common, Army special, OMR book'),
    (Icons.sticky_note_2_outlined, 'Notes', 'First aid, health, map reading, weapon training'),
  ];

  Future<void> _open(BuildContext context) async {
    final ok = await launchUrl(Uri.parse(Env.studyLibraryUrl), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the library. Check that a browser or Google Drive is installed.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.folder_shared_outlined, color: c.primary),
              const SizedBox(width: Space.sm),
              Expanded(child: Text('NCC B & C Cert library', style: t.titleMedium)),
              Icon(Icons.open_in_new, size: 18, color: c.onSurfaceVariant),
            ]),
            const SizedBox(height: Space.xs),
            Text('Every précis, past paper, question bank and set of notes, in Google Drive.',
                style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            const SizedBox(height: Space.md),
            for (final (icon, title, detail) in _sections)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Row(children: [
                  Icon(icon, size: 18, color: c.onSurfaceVariant),
                  const SizedBox(width: Space.sm),
                  Text(title, style: t.labelLarge),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(detail, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Every précis book on the phone, to read chapter by chapter.
class _PrecisBooks extends ConsumerWidget {
  const _PrecisBooks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final precis = ref.watch(precisProvider);
    final books = precis.books;
    if (books.isEmpty) return const SizedBox.shrink();
    final c = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Read the précis'),
      ListCard(children: [
        for (final b in books)
          ListTile(
            leading: Icon(b.contains('Oct 2025') ? Icons.auto_stories : Icons.menu_book_outlined, color: c.primary),
            title: Text(b),
            subtitle: Text('${precis.chaptersOf(b).length} chapters${b.contains('Oct 2025') ? ' · revised syllabus' : ''}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.book(b)),
          ),
      ]),
    ]);
  }
}
