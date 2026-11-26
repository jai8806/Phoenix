import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/test.dart';
import '../../data/models/user.dart';
import '../../data/providers.dart';
import '../../data/syllabus/syllabus.dart';
import '../shared/widgets.dart';

class LearnScreen extends ConsumerStatefulWidget {
  const LearnScreen({super.key});

  @override
  ConsumerState<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends ConsumerState<LearnScreen> {
  SyllabusLevel? _level;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider);
    final level = _level ?? SyllabusLevel.of(user?.division);
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
        SectionHeader('Syllabus · ${wing.label}'),
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
