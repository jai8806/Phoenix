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
import '../shared/figures.dart';
import '../shared/visual_notes.dart';
import '../../domain/study_format.dart';
import '../../data/models/figure.dart';
import '../shared/rich_answer.dart';
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
  const ChapterScreen({super.key, required this.code, this.book});

  final String code;

  /// Chapter codes repeat across books ("AF I" is in the JD/JW and SD/SW books).
  final String? book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final precis = ref.watch(precisProvider);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final all = <PrecisPassage>[
      for (final p in precis.search?.passages ?? const <PrecisPassage>[])
        if (p.heading.startsWith('$code · ')) p,
    ];
    final senior = ref.watch(authControllerProvider)?.division?.isSenior ?? true;
    final books = {for (final p in all) p.title};
    final chosen = book ??
        (books.length < 2
            ? null
            : books.firstWhere((b) => b.contains(senior ? 'SD/SW' : 'JD/JW'), orElse: () => books.first));
    final passages = [for (final p in all) if (chosen == null || p.title == chosen) p];
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

    final pictures = visualNotesFor(code);
    if (precis.status != PrecisStatus.ready || passages.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(code)),
        body: PageBody(children: [
          body,
          if (pictures.isNotEmpty) ...[
            const SectionHeader('Picture notes'),
            for (final n in pictures) ...[VisualNoteCard(n), const SizedBox(height: Space.md)],
          ],
        ]),
      );
    }

    final bookTitle = passages.first.title;
    final figures = precis.figuresFor(code, book: bookTitle);
    final sections = <(String, List<PrecisPassage>)>[];
    for (final p in passages) {
      final name = p.heading.split(' · ').last;
      if (sections.isEmpty || sections.last.$1 != name) sections.add((name, []));
      sections.last.$2.add(p);
    }
    bool isRecap(String name) => RegExp(r'summary|conclusion', caseSensitive: false).hasMatch(name);
    final reading = [for (final s in sections) if (!isRecap(s.$1)) s];
    final points = keyPoints(passages);
    final placed = <String>{};
    List<PrecisFigure> figuresIn(List<PrecisPassage> ps) {
      final from = ps.map((p) => p.page ?? 0).reduce((a, b) => a < b ? a : b);
      final to = ps.map((p) => p.pageEnd ?? p.page ?? 0).reduce((a, b) => a > b ? a : b);
      return [
        for (final f in figures)
          if (f.page != null && f.page! >= from && f.page! <= to && placed.add(f.id)) f,
      ];
    }
    final keys = [for (final _ in reading) GlobalKey()];
    final questions = ref.watch(questionBankProvider).where((q) => q.subject == code).length;
    final studiedId = '$bookTitle|$code';
    final studied = ref.watch(studiedChaptersProvider).contains(studiedId);
    final accents = [c.primary, c.tertiary, c.secondary];

    return Scaffold(
      appBar: AppBar(title: Text(code)),
      body: PageBody(children: [
        // Header
        Wrap(spacing: Space.sm, runSpacing: Space.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
            decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(Radii.sm)),
            child: Text(code, style: t.labelLarge?.copyWith(color: c.onPrimaryContainer)),
          ),
          if (studied) Icon(Icons.check_circle, size: 18, color: context.status.success),
        ]),
        const SizedBox(height: Space.sm),
        Text(title, style: t.headlineSmall),
        const SizedBox(height: Space.xs),
        Text(
          [
            bookTitle,
            'p. ${passages.first.page ?? '–'}–${passages.last.pageEnd ?? passages.last.page ?? '–'}',
            '${readMinutes(passages)} min read',
            if (figures.isNotEmpty) '${figures.length} figure${figures.length == 1 ? '' : 's'}',
          ].join(' · '),
          style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
        ),
        // In 30 seconds
        if (points.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Container(
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(
              color: c.tertiaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.bolt, size: 18, color: c.tertiary),
                const SizedBox(width: Space.xs),
                Text('IN 30 SECONDS', style: t.labelMedium?.copyWith(color: c.tertiary, letterSpacing: 1.1)),
              ]),
              const SizedBox(height: Space.sm),
              RichAnswer([for (final p in points) '- $p'].join('\n'), style: t.bodyMedium),
            ]),
          ),
        ],
        // Picture notes: the chapter's key facts as diagrams
        if (pictures.isNotEmpty) ...[
          SectionHeader(pictures.length == 1 ? 'Picture note' : 'Picture notes (${pictures.length})'),
          for (final n in pictures) ...[VisualNoteCard(n), const SizedBox(height: Space.sm)],
        ],
        // Jump to a section
        if (reading.length > 1) ...[
          const SizedBox(height: Space.lg),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: reading.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
              itemBuilder: (context, i) => ActionChip(
                label: Text(_shortSection(reading[i].$1)),
                onPressed: () {
                  final ctx = keys[i].currentContext;
                  if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
                },
              ),
            ),
          ),
        ],
        // Sections
        for (final (i, (name, ps)) in reading.indexed) ...[
          const SizedBox(height: Space.lg),
          Card(
            key: keys[i],
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(border: Border(left: BorderSide(color: accents[i % accents.length], width: 4))),
              padding: const EdgeInsets.all(Space.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: accents[i % accents.length].withValues(alpha: 0.15),
                    child: Text('${i + 1}', style: t.labelMedium?.copyWith(color: accents[i % accents.length])),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text(_shortSection(name), style: t.titleMedium)),
                ]),
                const SizedBox(height: Space.md),
                for (final p in ps) ...[
                  RichAnswer(formatForStudy(p.content), style: t.bodyLarge?.copyWith(height: 1.5)),
                  const SizedBox(height: Space.sm),
                ],
                Builder(builder: (_) {
                  final figs = figuresIn(ps);
                  if (figs.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: FigureStrip(figures: figs, height: 170),
                  );
                }),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('p. ${ps.first.page ?? '–'}${ps.last.pageEnd != null || ps.last.page != ps.first.page ? '–${ps.last.pageEnd ?? ps.last.page}' : ''}',
                      style: t.labelSmall?.copyWith(color: c.onSurfaceVariant)),
                ),
              ]),
            ),
          ),
        ],
        // Figures not tied to a section's pages
        Builder(builder: (_) {
          final rest = [for (final f in figures) if (!placed.contains(f.id)) f];
          if (rest.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader('More figures (${rest.length})'),
            FigureStrip(figures: rest, height: 150),
          ]);
        }),
        // Test yourself
        const SectionHeader('Test yourself'),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.quiz_outlined),
              title: Text(questions == 0 ? 'No questions for $code yet' : 'Practise $questions question${questions == 1 ? '' : 's'} from $code'),
              subtitle: Text(questions == 0
                  ? 'Your ANO approves this chapter\'s questions in the review queue.'
                  : 'Quick, untimed check of what you just read.'),
              trailing: questions == 0 ? null : const Icon(Icons.play_arrow),
              onTap: questions == 0 ? null : () => context.push(Routes.quiz('chapter:$code')),
            ),
            SwitchListTile(
              secondary: Icon(studied ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: studied ? context.status.success : null),
              title: const Text('Mark as studied'),
              value: studied,
              onChanged: (_) => ref.read(studiedChaptersProvider.notifier).toggle(studiedId),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// "Part II: Types of North and Bearings" -> "Types of North and Bearings".
String _shortSection(String s) => s.replaceFirst(RegExp(r'^Part\s+[IVX\d]+\s*[:\-–]\s*', caseSensitive: false), '');

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

/// Every chapter of one précis book, for browsing.
class BookScreen extends ConsumerWidget {
  const BookScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final precis = ref.watch(precisProvider);
    final chapters = precis.chaptersOf(title);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: chapters.isEmpty
          ? const EmptyState(
              icon: Icons.menu_book_outlined,
              title: 'Not downloaded yet',
              message: 'Open Ustaad once while online to download the study material.')
          : PageBody(children: [
              ListCard(children: [
                for (final (code, name, n) in chapters)
                  ListTile(
                    leading: SizedBox(width: 56, child: Text(code, style: Theme.of(context).textTheme.labelLarge)),
                    title: Text(name),
                    subtitle: Text('$n passage${n == 1 ? '' : 's'}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.chapter(code, book: title)),
                  ),
              ]),
            ]),
    );
  }
}
