import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

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
        if (usesBGuide(track)) ...[
          const SizedBox(height: Space.sm),
          Text(
            'C Cert weightage for your directorate isn\'t added yet, so this uses the B Cert 2024 pattern as a guide. '
            'Share a C Cert paper with your ANO to update it.',
            style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
        ],
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
                'from the question banks and the 2024 paper.',
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
        const SectionHeader('Tests from your unit'),
        if (tests.isEmpty)
          const EmptyState(icon: Icons.quiz_outlined, title: 'No tests yet',
              message: 'Tests your ANO or senior cadets host will appear here. Meanwhile, use Quick practice.')
        else
          ListCard(children: [
            for (final test in tests)
              _TestTile(test: test, isOpen: test.opensAt == null || !test.opensAt!.isAfter(now)),
          ]),
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
          Text('Pass: ${insights.passRule} · 2 marks per question',
              style: t.bodySmall?.copyWith(color: on.withValues(alpha: 0.85))),
          Text(insights.source, style: t.bodySmall?.copyWith(color: on.withValues(alpha: 0.65))),
        ]),
      ),
    );
  }
}

class _TestTile extends StatelessWidget {
  const _TestTile({required this.test, required this.isOpen});

  final TestDefinition test;
  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final m = test.marking;
    final neg = m.wrong == 0 ? 'no negative marking' : '−${_fmt(m.wrong)} per wrong answer';
    return ListTile(
      title: Text(test.title),
      subtitle: Text(
        isOpen
            ? '${test.questionIds.length} Q · ${test.durationMinutes} min · $neg'
            : 'Opens ${DateFormat('EEE d MMM, h:mm a').format(test.opensAt!)}',
      ),
      trailing: isOpen
          ? FilledButton.tonal(onPressed: () => context.push(Routes.quiz(test.id)), child: const Text('Start'))
          : const Icon(Icons.lock_clock_outlined),
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
