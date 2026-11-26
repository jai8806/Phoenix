import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/test.dart';
import '../../data/providers.dart';
import '../shared/widgets.dart';

class TestsScreen extends ConsumerWidget {
  const TestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tests = ref.watch(testsProvider);
    final bank = ref.watch(questionBankProvider);
    final now = ref.watch(clockProvider)();

    return PageBody(children: [
      Row(children: [
        Expanded(
          child: Text('${bank.length} questions in the bank',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
        FilledButton.icon(
          onPressed: () => showDialog<void>(context: context, builder: (_) => const _NewTestDialog()),
          icon: const Icon(Icons.add),
          label: const Text('New test'),
        ),
      ]),
      const SizedBox(height: Space.lg),
      if (tests.isEmpty)
        const EmptyState(icon: Icons.quiz_outlined, title: 'No tests yet',
            message: 'Create a test and it appears in every cadet\'s Learn tab.')
      else
        ListCard(children: [
          for (final test in tests)
            ListTile(
              leading: const Icon(Icons.assignment_outlined),
              title: Text(test.title),
              subtitle: Text([
                '${test.questionIds.length} Q',
                '${test.durationMinutes} min',
                '+${_n(test.marking.correct)} / −${_n(test.marking.wrong)}',
                if (test.opensAt != null)
                  test.opensAt!.isAfter(now)
                      ? 'opens ${DateFormat('d MMM').format(test.opensAt!)}'
                      : 'open',
              ].join(' · ')),
            ),
        ]),
      const SectionHeader('Coming in Phase 1–2'),
      const ListCard(children: [
        ListTile(
          leading: Icon(Icons.auto_awesome),
          title: Text('AI question drafts from your precis'),
          subtitle: Text('Ustaad drafts questions from uploaded material; you approve each one before it enters the bank.'),
        ),
        ListTile(
          leading: Icon(Icons.insights_outlined),
          title: Text('Results and weak-topic heatmap'),
          subtitle: Text('See which subjects each platoon struggles with.'),
        ),
      ]),
    ]);
  }
}

String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

class _NewTestDialog extends ConsumerStatefulWidget {
  const _NewTestDialog();

  @override
  ConsumerState<_NewTestDialog> createState() => _NewTestDialogState();
}

class _NewTestDialogState extends ConsumerState<_NewTestDialog> {
  final _title = TextEditingController();
  final _duration = TextEditingController(text: '30');
  final _correct = TextEditingController(text: '2');
  final _wrong = TextEditingController(text: '0');
  String? _titleError;

  @override
  void dispose() {
    for (final c in [_title, _duration, _correct, _wrong]) {
      c.dispose();
    }
    super.dispose();
  }

  void _create() {
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = 'Give the test a name cadets will recognise');
      return;
    }
    final bank = ref.read(questionBankProvider);
    ref.read(testsProvider.notifier).add(TestDefinition(
          id: 't${DateTime.now().microsecondsSinceEpoch}',
          title: _title.text.trim(),
          durationMinutes: int.tryParse(_duration.text) ?? 30,
          marking: MarkingScheme(
            correct: double.tryParse(_correct.text) ?? 2,
            wrong: double.tryParse(_wrong.text) ?? 0,
          ),
          // Phase 0: uses the whole starter bank. Question picking comes with the bank editor.
          questionIds: [for (final q in bank) q.id],
          opensAt: ref.read(clockProvider)(),
        ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final numeric = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    return AlertDialog(
      title: const Text('New test'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _title,
            autofocus: true,
            onChanged: (_) => setState(() => _titleError = null),
            decoration: InputDecoration(labelText: 'Test name', errorText: _titleError),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _duration,
            inputFormatters: numeric,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Duration', suffixText: 'min'),
          ),
          const SizedBox(height: Space.md),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _correct,
                inputFormatters: numeric,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Marks per right answer'),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: TextField(
                controller: _wrong,
                inputFormatters: numeric,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minus per wrong answer'),
              ),
            ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _create, child: const Text('Create test')),
      ],
    );
  }
}
