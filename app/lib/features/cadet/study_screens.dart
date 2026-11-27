import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/exam/exam_data.dart';
import '../../data/exam/insights.dart';
import '../../data/providers.dart';
import '../../domain/precis_search.dart';
import '../../domain/study_plan.dart';
import '../shared/widgets.dart';

IconData subjectIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('map')) return Icons.explore_outlined;
  if (n.contains('weapon')) return Icons.adjust;
  if (n.contains('field craft')) return Icons.forest_outlined;
  if (n.contains('armed')) return Icons.shield_outlined;
  if (n.contains('history')) return Icons.military_tech_outlined;
  if (n.contains('communication')) return Icons.settings_input_antenna;
  if (n.contains('personality')) return Icons.psychology_outlined;
  if (n.contains('leadership')) return Icons.flag_outlined;
  if (n.contains('social')) return Icons.volunteer_activism_outlined;
  if (n.contains('health')) return Icons.health_and_safety_outlined;
  if (n.contains('disaster')) return Icons.crisis_alert_outlined;
  if (n.contains('integration')) return Icons.diversity_3_outlined;
  if (n.contains('adventure')) return Icons.terrain_outlined;
  if (n.contains('border')) return Icons.public_outlined;
  if (n.contains('obstacle')) return Icons.directions_run;
  if (n.contains('drill')) return Icons.directions_walk;
  if (n.contains('environment')) return Icons.eco_outlined;
  return Icons.menu_book_outlined;
}

/// One subject's weight as a labelled bar.
class WeightRow extends StatelessWidget {
  const WeightRow({super.key, required this.subject, required this.maxMarks, required this.totalMarks, this.onTap});

  final SubjectInsight subject;
  final int maxMarks;
  final int totalMarks;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final pct = (subject.marks / totalMarks * 100).round();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm, horizontal: Space.xs),
        child: Row(children: [
          Icon(subjectIcon(subject.name), size: 20, color: c.onSurfaceVariant),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(subject.name, style: t.bodyMedium, overflow: TextOverflow.ellipsis)),
                Text('${subject.marks}', style: t.titleSmall),
                Text('  $pct%', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              ]),
              const SizedBox(height: Space.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: LinearProgressIndicator(
                  value: subject.marks / maxMarks,
                  minHeight: 6,
                  color: subject.paper == ExamPaper.common ? c.primary : c.secondary,
                  backgroundColor: c.surfaceContainerHighest,
                ),
              ),
            ]),
          ),
          if (onTap != null) ...[
            const SizedBox(width: Space.sm),
            Icon(Icons.chevron_right, size: 18, color: c.onSurfaceVariant),
          ],
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Subject
// ---------------------------------------------------------------------------
class SubjectScreen extends ConsumerWidget {
  const SubjectScreen({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = insightsFor(ref.watch(certTrackProvider));
    final s = subjectNamed(insights, name);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.search_off, title: 'Subject not found', message: 'Go back and pick a subject.'),
      );
    }
    final chapters = chaptersFor(s);
    final topCodes = {for (final ch in s.topChapters) ch.code};

    return Scaffold(
      appBar: AppBar(title: Text(s.name)),
      body: PageBody(children: [
        TileGrid(minTileWidth: 140, children: [
          StatTile(label: 'Marks', value: '${s.marks}', caption: s.paper.label, icon: Icons.star_outline),
          StatTile(
              label: 'Of the paper',
              value: '${(insights.weight(s) * 100).round()}%',
              caption: '${s.questions} questions',
              icon: Icons.pie_chart_outline),
          StatTile(label: 'To practise', value: '${s.bankQuestions}', caption: 'bank questions', icon: Icons.quiz_outlined),
        ]),
        if (s.note.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          Text('Note: ${s.note}.', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
        ],
        const SizedBox(height: Space.lg),
        FilledButton.icon(
          onPressed: s.bankQuestions == 0 ? null : () => context.push(Routes.quiz('subject:${s.name}')),
          icon: const Icon(Icons.play_arrow),
          label: Text('Practise ${s.name}'),
        ),
        if (s.topChapters.isNotEmpty) ...[
          const SectionHeader('Most asked chapters'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final ch in s.topChapters)
                  InkWell(
                    onTap: () => context.push(Routes.chapter(ch.code)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(ch.title, style: t.bodyMedium)),
                          Text('${(ch.share * 100).round()}%', style: t.titleSmall),
                        ]),
                        const SizedBox(height: Space.xs),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.pill),
                          child: LinearProgressIndicator(
                            value: ch.share,
                            minHeight: 6,
                            color: context.status.warning,
                            backgroundColor: c.surfaceContainerHighest,
                          ),
                        ),
                      ]),
                    ),
                  ),
                const SizedBox(height: Space.sm),
                Text('Share of ${s.name} questions in the banks and the 2024 paper that come from each chapter.',
                    style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              ]),
            ),
          ),
        ],
        SectionHeader('All chapters (${chapters.length})'),
        if (chapters.isEmpty)
          const EmptyState(
              icon: Icons.menu_book_outlined,
              title: 'No précis chapter',
              message: 'This subject is not in the SD/SW précis. Practise with the question bank.')
        else
          ListCard(children: [
            for (final ch in chapters)
              ListTile(
                leading: SizedBox(width: 56, child: Text(ch.code, style: t.labelMedium?.copyWith(color: c.primary))),
                title: Text(ch.title),
                trailing: topCodes.contains(ch.code)
                    ? Chip(
                        label: const Text('Asked often'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: c.tertiaryContainer,
                        labelStyle: t.labelSmall?.copyWith(color: c.onTertiaryContainer),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.chapter(ch.code)),
              ),
          ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Chapter reader
// ---------------------------------------------------------------------------
class ChapterScreen extends ConsumerWidget {
  const ChapterScreen({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final precis = ref.watch(precisProvider);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final passages = <PrecisPassage>[
      for (final p in precis.search?.passages ?? const <PrecisPassage>[])
        if (p.heading.startsWith('$code · ')) p,
    ];
    final title = passages.isEmpty ? code : passages.first.heading.split(' · ')[1];

    Widget body;
    switch (precis.status) {
      case PrecisStatus.sample:
        body = const EmptyState(
            icon: Icons.lock_outline,
            title: 'Sign in to read the précis',
            message: 'Chapters open here once you sign in with your unit account.');
      case PrecisStatus.loading:
        body = const Center(child: CircularProgressIndicator());
      case PrecisStatus.error:
        body = EmptyState(
          icon: Icons.cloud_off_outlined,
          title: "Couldn't load the précis",
          message: precis.error ?? 'Check your connection.',
          action: FilledButton(onPressed: () => ref.read(precisProvider.notifier).refresh(), child: const Text('Try again')),
        );
      case PrecisStatus.ready:
        body = passages.isEmpty
            ? const EmptyState(
                icon: Icons.menu_book_outlined,
                title: 'Not loaded yet',
                message: 'This chapter is not in the study material on your unit yet. Ask your ANO.')
            : const SizedBox.shrink();
    }

    if (precis.status != PrecisStatus.ready || passages.isEmpty) {
      return Scaffold(appBar: AppBar(title: Text(code)), body: PageBody(children: [body]));
    }

    String? lastSection;
    return Scaffold(
      appBar: AppBar(title: Text(code)),
      body: PageBody(children: [
        Text(title, style: t.headlineSmall),
        const SizedBox(height: Space.xs),
        Text('${passages.first.title} · p. ${passages.first.page ?? '–'}–${passages.last.pageEnd ?? passages.last.page ?? '–'}',
            style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
        const SizedBox(height: Space.lg),
        for (final p in passages) ...[
          if (p.heading.split(' · ').last != lastSection) ...[
            Padding(
              padding: const EdgeInsets.only(top: Space.lg, bottom: Space.sm),
              child: Text((lastSection = p.heading.split(' · ').last), style: t.titleMedium),
            ),
          ],
          SelectableText(p.content, style: t.bodyLarge?.copyWith(height: 1.55)),
          Padding(
            padding: const EdgeInsets.only(top: Space.xs, bottom: Space.md),
            child: Text('p. ${p.pages}', style: t.labelSmall?.copyWith(color: c.onSurfaceVariant)),
          ),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Study plan
// ---------------------------------------------------------------------------
String _dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

String planItemId(PlanDay day, PlanItem item) =>
    '${_dayKey(day.date)}|${item.chapter?.code ?? item.label}|${item.revision ? 'r' : 'l'}';

final studyPlanProvider = Provider<StudyPlan?>((ref) {
  final exam = ref.watch(examDateProvider);
  if (exam == null) return null;
  final insights = insightsFor(ref.watch(certTrackProvider));
  return buildStudyPlan(
    insights: insights,
    chaptersBySubject: chaptersBySubject(insights),
    today: ref.watch(clockProvider)(),
    examDate: exam,
  );
});

class StudyPlanScreen extends ConsumerStatefulWidget {
  const StudyPlanScreen({super.key});

  @override
  ConsumerState<StudyPlanScreen> createState() => _StudyPlanScreenState();
}

class _StudyPlanScreenState extends ConsumerState<StudyPlanScreen> {
  bool _showAll = false;

  Future<void> _pickDate() async {
    final now = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: ref.read(examDateProvider) ?? now.add(const Duration(days: 60)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 400)),
      helpText: 'Your exam date',
    );
    if (picked != null) ref.read(examDateProvider.notifier).set(picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final exam = ref.watch(examDateProvider);
    final plan = ref.watch(studyPlanProvider);
    final done = ref.watch(planProgressProvider);
    final track = ref.watch(certTrackProvider);
    final now = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(title: Text('${track.label} plan')),
      body: PageBody(children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text(exam == null ? 'Set your exam date' : DateFormat('EEEE, d MMMM yyyy').format(exam)),
            subtitle: Text(exam == null
                ? 'The plan counts back from it'
                : '${exam.difference(DateTime(now.year, now.month, now.day)).inDays} days to go'),
            trailing: TextButton(onPressed: _pickDate, child: Text(exam == null ? 'Set date' : 'Change')),
          ),
        ),
        if (plan == null || plan.isEmpty) ...[
          const SizedBox(height: Space.lg),
          EmptyState(
            icon: Icons.event_note_outlined,
            title: exam == null ? 'When is your exam?' : 'The exam date has passed',
            message: 'Set the exam date and Phoenix builds a day-by-day plan weighted by marks, with revision built in.',
            action: FilledButton(onPressed: _pickDate, child: const Text('Set exam date')),
          ),
        ] else ...[
          const SizedBox(height: Space.md),
          _PlanSummary(plan: plan, done: done),
          for (final day in (_showAll ? plan.days : plan.days.take(14)))
            _DayCard(day: day, done: done, isToday: _dayKey(day.date) == _dayKey(now)),
          if (!_showAll && plan.days.length > 14)
            TextButton(
              onPressed: () => setState(() => _showAll = true),
              child: Text('Show all ${plan.days.length} days'),
            ),
          if (plan.skipped.isNotEmpty) ...[
            const SectionHeader('Left out for lack of time'),
            Text(
              '${plan.skipped.length} lower-weight chapters: ${plan.skipped.take(6).map((c) => c.code).join(', ')}'
              '${plan.skipped.length > 6 ? '…' : ''}. Skim them if you get spare time.',
              style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
          ],
        ],
      ]),
    );
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.plan, required this.done});

  final StudyPlan plan;
  final Set<String> done;

  @override
  Widget build(BuildContext context) {
    final all = [for (final d in plan.days) for (final i in d.items) planItemId(d, i)];
    final completed = all.where(done.contains).length;
    final chapters = {for (final d in plan.days) for (final i in d.items) if (i.chapter != null) i.chapter!.code}.length;
    return TileGrid(minTileWidth: 140, children: [
      StatTile(label: 'Chapters', value: '$chapters', caption: 'with spaced revision', icon: Icons.menu_book_outlined),
      StatTile(
          label: 'Mock tests',
          value: '${plan.days.where((d) => d.kind == PlanDayKind.mock).length}',
          caption: 'in the final stretch',
          icon: Icons.timer_outlined),
      StatTile(
          label: 'Done',
          value: all.isEmpty ? '0%' : '${(completed / all.length * 100).round()}%',
          caption: '$completed of ${all.length} tasks',
          icon: Icons.task_alt),
    ]);
  }
}

class _DayCard extends ConsumerWidget {
  const _DayCard({required this.day, required this.done, required this.isToday});

  final PlanDay day;
  final Set<String> done;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final (tag, tagColor) = switch (day.kind) {
      PlanDayKind.learn => ('Learn', c.primary),
      PlanDayKind.finalRevision => ('Final revision', context.status.warning),
      PlanDayKind.mock => ('Mock test', c.tertiary),
    };
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: isToday ? c.primary : c.outlineVariant, width: isToday ? 2 : 1),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(isToday ? 'TODAY' : DateFormat('EEE d MMM').format(day.date).toUpperCase(),
                  style: t.labelMedium?.copyWith(letterSpacing: 1.1, color: isToday ? c.primary : c.onSurfaceVariant)),
              const Spacer(),
              Text(tag, style: t.labelMedium?.copyWith(color: tagColor)),
              const SizedBox(width: Space.sm),
            ]),
            for (final item in day.items)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: done.contains(planItemId(day, item)),
                onChanged: (_) => ref.read(planProgressProvider.notifier).toggle(planItemId(day, item)),
                title: Text(item.chapter == null
                    ? item.label!
                    : '${item.revision ? 'Revise' : 'Study'} ${item.chapter!.code} · ${item.chapter!.title}'),
                subtitle: item.chapter == null ? null : Text(item.chapter!.subject),
                secondary: item.chapter == null
                    ? null
                    : IconButton(
                        tooltip: 'Open chapter',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => context.push(Routes.chapter(item.chapter!.code)),
                      ),
              ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// How to revise
// ---------------------------------------------------------------------------
void showRevisionTips(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final t = Theme.of(ctx).textTheme;
      final c = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('How to revise', style: t.titleLarge),
            const SizedBox(height: Space.md),
            for (final (i, (title, body)) in revisionTips.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: c.primaryContainer,
                    child: Text('${i + 1}', style: t.labelMedium?.copyWith(color: c.onPrimaryContainer)),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: t.titleSmall),
                      const SizedBox(height: 2),
                      Text(body, style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
      );
    },
  );
}
