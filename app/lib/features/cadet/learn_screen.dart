import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../data/demo/syllabus.dart';
import '../../data/models/test.dart';
import '../../data/models/user.dart';
import '../../data/providers.dart';
import '../shared/widgets.dart';

class LearnScreen extends ConsumerWidget {
  const LearnScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    final wing = user?.wing ?? Wing.army;
    final now = ref.watch(clockProvider)();
    final tests = ref.watch(testsProvider);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    const bp = bCertificateBlueprint;

    return Scaffold(
      appBar: AppBar(title: const Text('Learn')),
      body: PageBody(children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Full ${bp.name} mock', style: t.titleMedium),
              const SizedBox(height: Space.xs),
              Text('${bp.questionCount} questions · ${bp.totalMarks} marks · ${bp.durationMinutes} min',
                  style: t.bodyMedium),
              const SizedBox(height: Space.xs),
              Text('Pattern: ${bp.source}', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              const SizedBox(height: Space.md),
              Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                FilledButton.icon(
                  onPressed: () => context.push(Routes.quiz('practice')),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Quick practice'),
                ),
                Tooltip(
                  message: 'Unlocks once the full question bank is built from the official precis',
                  child: OutlinedButton(onPressed: null, child: Text('Start full mock')),
                ),
              ]),
            ]),
          ),
        ),
        const SectionHeader('Tests from your unit'),
        if (tests.isEmpty)
          const EmptyState(icon: Icons.quiz_outlined, title: 'No tests yet',
              message: 'Tests your ANO or senior cadets host will appear here.')
        else
          ListCard(children: [
            for (final test in tests)
              _TestTile(test: test, isOpen: test.opensAt == null || !test.opensAt!.isAfter(now)),
          ]),
        Padding(
          padding: const EdgeInsets.only(top: Space.xl, bottom: Space.sm),
          child: Row(children: [
            Expanded(
              child: Text('SYLLABUS · ${wing.label.toUpperCase()}',
                  style: t.labelLarge?.copyWith(letterSpacing: 1.1, color: c.onSurfaceVariant)),
            ),
            const DemoBadge(text: 'Provisional list'),
          ]),
        ),
        _SubjectGroup(title: 'Common subjects', subjects: commonSubjects),
        const SizedBox(height: Space.md),
        _SubjectGroup(title: '${wing.label} subjects', subjects: wingSubjects[wing] ?? const []),
      ]),
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

class _SubjectGroup extends StatelessWidget {
  const _SubjectGroup({required this.title, required this.subjects});

  final String title;
  final List<String> subjects;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        title: Text(title, style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text('${subjects.length} subjects'),
        children: [
          for (final s in subjects)
            ListTile(
              dense: true,
              leading: const Icon(Icons.article_outlined, size: 20),
              title: Text(s),
              trailing: Text('Notes soon', style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
