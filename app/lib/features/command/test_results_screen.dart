import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/test.dart';
import '../../data/providers.dart';
import '../../domain/hosted_tests.dart';
import '../shared/widgets.dart';
import 'tests_screen.dart';

/// The questions and attempts behind one test's results.
final testReportProvider = FutureProvider.autoDispose.family<TestReport?, String>((ref, testId) async {
  TestDefinition? test;
  for (final t in ref.watch(testsProvider)) {
    if (t.id == testId) test = t;
  }
  if (test == null) return null;
  final repo = ref.watch(unitRepositoryProvider);
  if (repo == null) {
    // Sample mode has no submissions to show.
    final ids = test.questionIds.toSet();
    final questions = ref.read(questionBankProvider).where((q) => ids.contains(q.id)).toList();
    return summarizeAttempts(questions: questions, attempts: const [], marking: test.marking);
  }
  final results = await Future.wait([repo.testQuestions(testId), repo.testAttempts(testId)]);
  return summarizeAttempts(
    questions: results[0] as List<Question>,
    attempts: results[1] as List<AttemptRecord>,
    marking: test.marking,
  );
});

class TestResultsScreen extends ConsumerWidget {
  const TestResultsScreen({super.key, required this.testId});

  final String testId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    TestDefinition? test;
    for (final t in ref.watch(testsProvider)) {
      if (t.id == testId) test = t;
    }
    final report = ref.watch(testReportProvider(testId));
    final members = ref.watch(membersProvider);
    final now = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(
        title: Text(test?.title ?? 'Results'),
        actions: [
          IconButton(
            tooltip: 'Refresh results',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(testReportProvider(testId)),
          ),
        ],
      ),
      body: test == null
          ? const EmptyState(icon: Icons.search_off, title: 'Test not found', message: 'It may have been deleted.')
          : report.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(icon: Icons.cloud_off, title: "Couldn't load the results", message: '$e'),
              data: (r) => r == null
                  ? const EmptyState(icon: Icons.search_off, title: 'Test not found', message: 'It may have been deleted.')
                  : _ReportBody(test: test!, report: r, cadets: members.where((m) => !m.role.isAno).length, now: now),
            ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.test, required this.report, required this.cadets, required this.now});

  final TestDefinition test;
  final TestReport report;
  final int cadets;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    String pct(double score) => '${report.percent(score).round()}%';

    return PageBody(children: [
      Text(
        [
          testStatus(test, now),
          '${test.questionIds.length} questions',
          '${fmtMarks(report.maxScore)} marks',
          '+${fmtMarks(test.marking.correct)} / −${fmtMarks(test.marking.wrong)}',
        ].join(' · '),
        style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant),
      ),
      const SizedBox(height: Space.lg),
      TileGrid(minTileWidth: 150, children: [
        StatTile(
          label: 'Submitted',
          value: cadets == 0 ? '${report.attempts.length}' : '${report.attempts.length} / $cadets',
          icon: Icons.how_to_reg_outlined,
        ),
        StatTile(label: 'Average', value: report.isEmpty ? '—' : pct(report.average), icon: Icons.functions),
        StatTile(label: 'Highest', value: report.isEmpty ? '—' : pct(report.highest), icon: Icons.emoji_events_outlined),
        StatTile(label: 'Lowest', value: report.isEmpty ? '—' : pct(report.lowest), icon: Icons.trending_down),
      ]),
      if (report.isEmpty) ...[
        const SizedBox(height: Space.xl),
        const EmptyState(
          icon: Icons.hourglass_empty,
          title: 'No submissions yet',
          message: 'Results appear here as cadets submit. Pull the refresh button to check again.',
        ),
      ] else ...[
        const SectionHeader('Weak subjects across the unit'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(children: [
              for (final s in report.bySubject) _AccuracyRow(label: s.subject, accuracy: s.accuracy),
            ]),
          ),
        ),
        const SectionHeader('Most missed questions'),
        ListCard(children: [
          for (final q in report.hardest)
            ListTile(
              title: Text(q.question.prompt, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('Answer: ${q.question.options[q.question.correctIndex]} · ${q.question.subject}'),
              trailing: Text('${(q.accuracy * 100).round()}% right', style: t.labelMedium),
            ),
        ]),
        const SectionHeader('Scores'),
        ListCard(children: [
          for (final (i, a) in report.attempts.indexed)
            ListTile(
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: c.surfaceContainerHigh,
                child: Text('${i + 1}', style: t.labelMedium),
              ),
              title: Text(a.cadetName),
              subtitle: Text([
                if (a.submittedAt != null) DateFormat('d MMM, h:mm a').format(a.submittedAt!),
                if (a.focusLost > 0) 'left the app ${a.focusLost}×',
              ].join(' · ')),
              trailing: Text('${fmtMarks(a.score)} · ${pct(a.score)}', style: t.titleSmall),
            ),
        ]),
        const SizedBox(height: Space.sm),
        Text('"Left the app" counts how often the cadet switched away during the test.',
            style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
      ],
    ]);
  }
}

class _AccuracyRow extends StatelessWidget {
  const _AccuracyRow({required this.label, required this.accuracy});

  final String label;
  final double accuracy;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final color = accuracy < 0.4
        ? Theme.of(context).colorScheme.error
        : accuracy < 0.6
            ? context.status.warning
            : context.status.success;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(children: [
        Expanded(flex: 3, child: Text(label, style: t.bodyMedium, overflow: TextOverflow.ellipsis)),
        Expanded(
          flex: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: accuracy, minHeight: 8, color: color),
          ),
        ),
        SizedBox(width: 48, child: Text('${(accuracy * 100).round()}%', textAlign: TextAlign.end, style: t.labelMedium)),
      ]),
    );
  }
}
