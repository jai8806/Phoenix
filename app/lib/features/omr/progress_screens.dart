import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/providers.dart';
import '../../domain/omr/exam_pattern.dart';
import '../../domain/omr/progress.dart';
import '../shared/widgets.dart';

Color accuracyColor(BuildContext context, double a) => a < 0.4
    ? Theme.of(context).colorScheme.error
    : a < 0.6
        ? context.status.warning
        : context.status.success;

/// A cadet's scores over time and accuracy per subject.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(myHistoryProvider);
    final pattern = ExamPattern.byId(ref.watch(certTrackProvider).name == 'c' ? 'ccert' : 'bcert');
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    if (history.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('My progress')),
        body: const EmptyState(
          icon: Icons.insights_outlined,
          title: 'No tests yet',
          message: 'Take a unit test or OMR mock and your scores and weak subjects will show here.',
        ),
      );
    }
    final stats = subjectStats(history, pattern: pattern);
    final mocks = history.where((h) => h.pattern != null).toList();
    final latestMock = mocks.isEmpty ? null : mocks.last;
    final recent = history.length > 10 ? history.sublist(history.length - 10) : history;

    return Scaffold(
      appBar: AppBar(title: const Text('My progress')),
      body: PageBody(children: [
        Text('${history.length} test${history.length == 1 ? '' : 's'} · latest ${recent.last.percent.round()}%', style: t.titleMedium),
        const SizedBox(height: Space.md),
        _ScoreBars(values: [for (final h in recent) h.percent], labels: [for (final h in recent) h.submittedAt == null ? '' : DateFormat('d MMM').format(h.submittedAt!)]),
        if (latestMock != null) ...[
          const SectionHeader('Would you pass today?'),
          Text('From your latest mock: ${latestMock.testTitle}', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
          const SizedBox(height: Space.sm),
          ListCard(children: [
            for (final (paper, pct) in paperPercents(latestMock, ExamPattern.byId(latestMock.pattern!)))
              ListTile(
                leading: Icon(pct >= 33 ? Icons.check_circle : Icons.cancel, color: pct >= 33 ? context.status.success : c.error),
                title: Text(paper.title.replaceFirst(RegExp(r'^PAPER - [IVX]+ : '), '')),
                trailing: Text('${pct.round()}%', style: t.titleSmall),
              ),
          ]),
        ],
        const SectionHeader('Subjects, weakest first'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(children: [
              for (final s in stats)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Row(children: [
                    Expanded(
                      flex: 5,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.subject, style: t.bodyMedium, overflow: TextOverflow.ellipsis),
                        Text(
                          [
                            '${s.correct}/${s.total} right',
                            if (subjectMarks(s.subject, pattern) > 0) '${subjectMarks(s.subject, pattern).toStringAsFixed(0)} marks in the paper',
                          ].join(' · '),
                          style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                        ),
                      ]),
                    ),
                    Expanded(
                      flex: 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: s.accuracy, minHeight: 8, color: accuracyColor(context, s.accuracy)),
                      ),
                    ),
                    SizedBox(width: 44, child: Text('${(s.accuracy * 100).round()}%', textAlign: TextAlign.end, style: t.labelMedium)),
                  ]),
                ),
            ]),
          ),
        ),
        const SizedBox(height: Space.sm),
        Text('Weak subjects that carry many marks are the fastest way to raise your score.', style: t.bodySmall),
      ]),
    );
  }
}

class _ScoreBars extends StatelessWidget {
  const _ScoreBars({required this.values, required this.labels});

  final List<double> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final (i, v) in values.indexed)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('${v.round()}', style: t.labelSmall),
                const SizedBox(height: 2),
                Container(
                  height: 100 * (v.clamp(0, 100) / 100) + 2,
                  decoration: BoxDecoration(
                    color: v >= 33 ? c.primary : c.error,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(labels[i], style: t.labelSmall?.copyWith(color: c.onSurfaceVariant, fontSize: 9), maxLines: 1, overflow: TextOverflow.clip),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// The ANO's view: who is at risk, the unit's weak subjects, and a heatmap.
class UnitPerformanceScreen extends ConsumerWidget {
  const UnitPerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(unitHistoryProvider);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    if (history.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Unit performance')),
        body: const EmptyState(
          icon: Icons.insights_outlined,
          title: 'No results yet',
          message: 'Host a test or an OMR mock. Results, weak subjects and cadets at risk appear here.',
        ),
      );
    }
    final risk = cadetsAtRisk(history);
    final stats = subjectStats(history);
    final map = heatmap(history);
    final names = {for (final h in history) h.cadetId: h.cadetName};
    final subjects = [for (final s in stats.reversed) s.subject]; // strongest first, left to right
    final cadets = map.keys.toList()..sort((a, b) => (names[a] ?? '').compareTo(names[b] ?? ''));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unit performance'),
        actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => ref.read(unitHistoryProvider.notifier).reload())],
      ),
      body: PageBody(children: [
        Text('${history.length} attempts by ${cadets.length} cadet${cadets.length == 1 ? '' : 's'}', style: t.titleMedium),
        const SectionHeader('At risk of failing a paper'),
        if (risk.isEmpty)
          const EmptyState(icon: Icons.check_circle_outline, title: 'No one is below 33%', message: 'Based on each cadet\'s latest OMR mock.')
        else
          ListCard(children: [
            for (final r in risk)
              ListTile(
                leading: Icon(Icons.warning_amber_rounded, color: context.status.warning),
                title: Text(r.cadetName),
                subtitle: Text([
                  for (final (p, pct) in r.failing) '${p.title.replaceFirst(RegExp(r'^PAPER - [IVX]+ : '), '')} ${pct.round()}%',
                ].join(' · ')),
                trailing: Text(r.testTitle, style: t.bodySmall),
              ),
          ]),
        const SectionHeader('Weakest subjects across the unit'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(children: [
              for (final s in stats.take(6))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Row(children: [
                    Expanded(flex: 5, child: Text(s.subject, overflow: TextOverflow.ellipsis)),
                    Expanded(
                      flex: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: s.accuracy, minHeight: 8, color: accuracyColor(context, s.accuracy)),
                      ),
                    ),
                    SizedBox(width: 44, child: Text('${(s.accuracy * 100).round()}%', textAlign: TextAlign.end)),
                  ]),
                ),
            ]),
          ),
        ),
        const SectionHeader('Cadet by subject'),
        Text('Accuracy across all their tests. Grey: no questions yet.', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
        const SizedBox(height: Space.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const SizedBox(width: 130),
              for (final s in subjects)
                SizedBox(
                  width: 44,
                  height: 90,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(s, style: t.labelSmall, overflow: TextOverflow.ellipsis),
                  ),
                ),
            ]),
            for (final id in cadets)
              Row(children: [
                SizedBox(width: 130, child: Text(names[id] ?? 'Cadet', style: t.bodySmall, overflow: TextOverflow.ellipsis)),
                for (final s in subjects)
                  Builder(builder: (context) {
                    final cell = map[id]![s];
                    final a = cell?.accuracy;
                    return Tooltip(
                      message: cell == null ? '$s: no questions yet' : '$s: ${cell.correct}/${cell.total}',
                      child: Container(
                        width: 40,
                        height: 26,
                        margin: const EdgeInsets.all(2),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: a == null ? c.surfaceContainerHighest : accuracyColor(context, a).withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(a == null ? '' : '${(a * 100).round()}', style: t.labelSmall),
                      ),
                    );
                  }),
              ]),
          ]),
        ),
        const SizedBox(height: Space.xl),
      ]),
    );
  }
}
