import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/test.dart';
import '../../data/providers.dart';
import '../shared/widgets.dart';

/// Runs a test: a unit test by id, or 'practice' / 'fall-in' drawn from the bank.
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key, required this.testId});

  final String testId;

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  late final String _title;
  late final List<Question> _questions;
  late final MarkingScheme _marking;
  late final Duration _limit;
  final Map<String, int> _answers = {};
  int _index = 0;
  TestResult? _result;
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    final bank = ref.read(questionBankProvider);
    final rng = Random();
    TestDefinition? def;
    for (final t in ref.read(testsProvider)) {
      if (t.id == widget.testId) def = t;
    }
    if (def != null) {
      final ids = def.questionIds.toSet();
      _title = def.title;
      _questions = bank.where((q) => ids.contains(q.id)).toList()..shuffle(rng);
      _marking = def.marking;
      _limit = Duration(minutes: def.durationMinutes);
    } else {
      final count = widget.testId == 'fall-in' ? 5 : 10;
      _title = widget.testId == 'fall-in' ? 'Daily Fall-In' : 'Quick practice';
      _questions = (List.of(bank)..shuffle(rng)).take(count).toList();
      _marking = const MarkingScheme();
      _limit = Duration(minutes: count);
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _result != null) return;
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed >= _limit) _submit();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _submit() {
    _timer?.cancel();
    setState(() => _result = scoreTest(questions: _questions, answers: _answers, marking: _marking));
  }

  Future<void> _confirmSubmit() async {
    final unanswered = _questions.length - _answers.length;
    if (unanswered == 0) return _submit();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit test?'),
        content: Text('$unanswered question${unanswered == 1 ? ' is' : 's are'} still unanswered.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep answering')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit test')),
        ],
      ),
    );
    if (ok == true) _submit();
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: const EmptyState(icon: Icons.quiz_outlined, title: 'No questions yet',
            message: 'This test has no questions in the bank yet.'),
      );
    }
    if (_result != null) return _ResultView(title: _title, result: _result!, questions: _questions, answers: _answers);

    final q = _questions[_index];
    final remaining = _limit - _elapsed;
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    String mmss(Duration d) =>
        '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: Space.lg),
              child: Row(children: [
                Icon(Icons.timer_outlined, size: 18,
                    color: remaining.inSeconds < 60 ? c.error : c.onSurfaceVariant),
                const SizedBox(width: Space.xs),
                Text(mmss(remaining), style: t.titleSmall),
              ]),
            ),
          ),
        ],
      ),
      body: PageBody(children: [
        LinearProgressIndicator(value: (_index + 1) / _questions.length),
        const SizedBox(height: Space.lg),
        Text('Question ${_index + 1} of ${_questions.length} · ${q.subject}',
            style: t.labelMedium?.copyWith(color: c.onSurfaceVariant)),
        const SizedBox(height: Space.sm),
        Text(q.prompt, style: t.titleLarge),
        const SizedBox(height: Space.lg),
        RadioGroup<int>(
          groupValue: _answers[q.id],
          onChanged: (v) => setState(() => v == null ? _answers.remove(q.id) : _answers[q.id] = v),
          child: Column(children: [
            for (var i = 0; i < q.options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Card(
                  child: RadioListTile<int>(
                    value: i,
                    title: Text(q.options[i]),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: Space.lg),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _index == 0 ? null : () => setState(() => _index--),
              child: const Text('Previous'),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: _index < _questions.length - 1
                ? FilledButton(onPressed: () => setState(() => _index++), child: const Text('Next question'))
                : FilledButton(onPressed: _confirmSubmit, child: const Text('Submit test')),
          ),
        ]),
      ]),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.title, required this.result, required this.questions, required this.answers});

  final String title;
  final TestResult result;
  final List<Question> questions;
  final Map<String, int> answers;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    String n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(title: Text('$title · Result')),
      body: PageBody(children: [
        Text('${n(result.score)} / ${n(result.maxScore)}', style: t.displaySmall),
        Text('${result.percentage.round()}% · ${result.correct} right · ${result.wrong} wrong · ${result.skipped} skipped',
            style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
        if (result.weakSubjects.isNotEmpty) ...[
          const SectionHeader('Work on these'),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            for (final s in result.weakSubjects)
              Chip(label: Text('${s.subject} · ${(s.accuracy * 100).round()}%')),
          ]),
        ],
        const SectionHeader('Review answers'),
        for (final q in questions) _ReviewCard(question: q, chosen: answers[q.id]),
        const SizedBox(height: Space.lg),
        FilledButton(onPressed: () => context.pop(), child: const Text('Done')),
      ]),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.question, required this.chosen});

  final Question question;
  final int? chosen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final right = chosen == question.correctIndex;
    final (icon, color, label) = chosen == null
        ? (Icons.remove_circle_outline, c.onSurfaceVariant, 'Skipped')
        : right
            ? (Icons.check_circle_outline, context.status.success, 'Correct')
            : (Icons.cancel_outlined, c.error, 'Wrong');

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: Space.xs),
              Text(label, style: t.labelMedium?.copyWith(color: color)),
            ]),
            const SizedBox(height: Space.sm),
            Text(question.prompt, style: t.titleSmall),
            const SizedBox(height: Space.xs),
            Text('Answer: ${question.options[question.correctIndex]}', style: t.bodyMedium),
            if (chosen != null && !right)
              Text('You chose: ${question.options[chosen!]}', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            if (question.explanation != null) ...[
              const SizedBox(height: Space.sm),
              Text(question.explanation!, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            ],
          ]),
        ),
      ),
    );
  }
}
