import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/exam/exam_data.dart';
import '../../data/models/test.dart';
import '../../data/providers.dart';
import '../../domain/hosted_tests.dart';
import '../shared/widgets.dart';

class TestsScreen extends ConsumerWidget {
  const TestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tests = ref.watch(testsProvider);
    final bank = ref.watch(questionBankProvider);
    final now = ref.watch(clockProvider)();

    return PageBody(children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.fact_check_outlined),
          title: const Text('Review précis questions'),
          subtitle: const Text('Set the correct answer for questions from the précis. Approved ones join the practice bank.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.review),
        ),
      ),
      const SizedBox(height: Space.lg),
      Row(children: [
        Expanded(
          child: Text('${bank.length} approved question${bank.length == 1 ? '' : 's'} to build tests from',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
        FilledButton.icon(
          onPressed: bank.isEmpty
              ? null
              : () => showDialog<void>(context: context, builder: (_) => const NewTestDialog()),
          icon: const Icon(Icons.add),
          label: const Text('New test'),
        ),
      ]),
      const SizedBox(height: Space.lg),
      if (tests.isEmpty)
        EmptyState(
          icon: Icons.quiz_outlined,
          title: 'No tests yet',
          message: bank.isEmpty
              ? 'Approve some précis questions first; tests are built from the approved bank.'
              : "Create a test and it appears in every cadet's Learn tab. Phoenix marks it and shows you the results.",
        )
      else
        ListCard(children: [
          for (final test in tests) _AdminTestTile(test: test, now: now),
        ]),
    ]);
  }
}

String fmtMarks(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// "Open · closes Fri 5 Dec", "Closed", "Opens Mon 1 Dec".
String testStatus(TestDefinition t, DateTime now) {
  final d = DateFormat('EEE d MMM');
  if (!t.hasOpened(now)) return 'Opens ${d.format(t.opensAt!)}';
  if (t.hasClosed(now)) return 'Closed';
  return t.closesAt == null ? 'Open' : 'Open · closes ${d.format(t.closesAt!)}';
}

class _AdminTestTile extends ConsumerWidget {
  const _AdminTestTile({required this.test, required this.now});

  final TestDefinition test;
  final DateTime now;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${test.title}"?'),
        content: const Text('Cadets will no longer see it, and its results are deleted too.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep test')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete test')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(testsProvider.notifier).delete(test.id);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = test.isOpen(now);
    return ListTile(
      leading: Icon(open ? Icons.assignment_outlined : Icons.assignment_turned_in_outlined,
          color: open ? context.status.success : null),
      title: Text(test.title),
      subtitle: Text([
        testStatus(test, now),
        '${test.questionIds.length} Q · ${test.durationMinutes} min',
        '+${fmtMarks(test.marking.correct)} / −${fmtMarks(test.marking.wrong)}',
        '${test.attemptCount} submitted',
      ].join(' · ')),
      onTap: () => context.push(Routes.testResults(test.id)),
      trailing: PopupMenuButton<String>(
        tooltip: 'Test options',
        onSelected: (v) => v == 'delete' ? _delete(context, ref) : context.push(Routes.testResults(test.id)),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'results', child: Text('See results')),
          PopupMenuItem(value: 'delete', child: Text('Delete test')),
        ],
      ),
    );
  }
}

enum _Source { pattern, subjects }

class NewTestDialog extends ConsumerStatefulWidget {
  const NewTestDialog({super.key});

  @override
  ConsumerState<NewTestDialog> createState() => _NewTestDialogState();
}

class _NewTestDialogState extends ConsumerState<NewTestDialog> {
  final _title = TextEditingController();
  final _count = TextEditingController(text: '50');
  final _duration = TextEditingController(text: '45');
  final _correct = TextEditingController(text: '2');
  late final TextEditingController _wrong;
  _Source _source = _Source.pattern;
  final Set<String> _subjects = {};
  int? _closeDays = 7;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final neg = insightsFor(ref.read(certTrackProvider)).negativeMarks;
    _wrong = TextEditingController(text: fmtMarks(neg));
  }

  @override
  void dispose() {
    for (final c in [_title, _count, _duration, _correct, _wrong]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty) return setState(() => _error = 'Give the test a name cadets will recognise.');
    if (_source == _Source.subjects && _subjects.isEmpty) {
      return setState(() => _error = 'Pick at least one subject.');
    }
    final count = int.tryParse(_count.text) ?? 0;
    if (count < 1) return setState(() => _error = 'Enter how many questions the test should have.');
    final bank = ref.read(questionBankProvider);
    final insights = insightsFor(ref.read(certTrackProvider));
    final ids = pickTestQuestions(
      bank: bank,
      insights: insights,
      count: count,
      subjects: _source == _Source.subjects ? _subjects : null,
    );
    if (ids.isEmpty) return setState(() => _error = 'No approved questions in those subjects yet.');

    final now = ref.read(clockProvider)();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(testsProvider.notifier).create(NewTest(
            title: title,
            durationMinutes: (int.tryParse(_duration.text) ?? 45).clamp(1, 600),
            marking: MarkingScheme(
              correct: double.tryParse(_correct.text) ?? 2,
              wrong: double.tryParse(_wrong.text) ?? 0,
            ),
            questionIds: ids,
            opensAt: now,
            closesAt: _closeDays == null ? null : now.add(Duration(days: _closeDays!)),
          ));
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ids.length < count
            ? 'Test created with ${ids.length} questions (that is all the approved ones in those subjects).'
            : 'Test created. Cadets see it in their Learn tab.'),
      ));
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final numeric = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final track = ref.watch(certTrackProvider);
    final insights = insightsFor(track);
    final counts = bankCountBySubject(ref.watch(questionBankProvider), insights);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('New test'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(labelText: 'Test name', hintText: 'e.g. Weekly test 4 · Map Reading'),
          ),
          const SizedBox(height: Space.lg),
          Text('Questions from', style: t.labelLarge),
          const SizedBox(height: Space.sm),
          SegmentedButton<_Source>(
            segments: [
              ButtonSegment(value: _Source.pattern, label: Text('${track.label} pattern')),
              const ButtonSegment(value: _Source.subjects, label: Text('Chosen subjects')),
            ],
            selected: {_source},
            onSelectionChanged: (s) => setState(() {
              _source = s.first;
              _error = null;
            }),
          ),
          const SizedBox(height: Space.sm),
          if (_source == _Source.pattern)
            Text('Every subject gets its share of questions by marks, like the real paper.',
                style: t.bodySmall?.copyWith(color: c.onSurfaceVariant))
          else
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
              for (final s in insights.ranked())
                FilterChip(
                  label: Text('${s.name} · ${counts[s.name] ?? 0}'),
                  selected: _subjects.contains(s.name),
                  onSelected: (counts[s.name] ?? 0) == 0
                      ? null
                      : (on) => setState(() {
                            on ? _subjects.add(s.name) : _subjects.remove(s.name);
                            _error = null;
                          }),
                ),
            ]),
          const SizedBox(height: Space.lg),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _count,
                inputFormatters: digits,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Questions'),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: TextField(
                controller: _duration,
                inputFormatters: digits,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Duration', suffixText: 'min'),
              ),
            ),
          ]),
          const SizedBox(height: Space.md),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _correct,
                inputFormatters: numeric,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Marks per right answer'),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: TextField(
                controller: _wrong,
                inputFormatters: numeric,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Minus per wrong answer'),
              ),
            ),
          ]),
          const SizedBox(height: Space.lg),
          Text('Cadets can take it', style: t.labelLarge),
          const SizedBox(height: Space.sm),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            for (final (days, label) in const [(1, 'For 24 hours'), (3, 'For 3 days'), (7, 'For a week'), (null, 'Until I delete it')])
              ChoiceChip(
                label: Text(label),
                selected: _closeDays == days,
                onSelected: (_) => setState(() => _closeDays = days),
              ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: Space.md),
            Text(_error!, style: t.bodyMedium?.copyWith(color: c.error)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _create,
          child: Text(_saving ? 'Creating…' : 'Create test'),
        ),
      ],
    );
  }
}
