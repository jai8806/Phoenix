import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/exam/exam_data.dart';
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

class _QuizScreenState extends ConsumerState<QuizScreen> with WidgetsBindingObserver {
  late final String _title;
  List<Question> _questions = const [];
  late final MarkingScheme _marking;
  late final Duration _limit;
  final Map<String, int> _answers = {};
  int _index = 0;
  TestResult? _result;
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  /// Set for a test hosted by the unit on the backend: marked on the server.
  TestDefinition? _hosted;
  bool _loading = false;
  String? _blocked; // why the test can't be taken right now
  String? _loadError;
  bool _submitting = false;
  String? _submitError;
  double? _serverScore;
  int _focusLost = 0;
  bool _reviewOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final bank = ref.read(questionBankProvider);
    final rng = Random();
    TestDefinition? def;
    for (final t in ref.read(testsProvider)) {
      if (t.id == widget.testId) def = t;
    }
    if (def != null) {
      _title = def.title;
      _marking = def.marking;
      _limit = Duration(minutes: def.durationMinutes);
      if (ref.read(unitRepositoryProvider) != null) {
        _hosted = def;
        _openHosted(def);
        return;
      }
      final ids = def.questionIds.toSet();
      _questions = bank.where((q) => ids.contains(q.id)).toList()..shuffle(rng);
    } else if (widget.testId == 'mock') {
      // Full mock in the exam pattern: each subject gets its share of questions.
      final insights = insightsFor(ref.read(certTrackProvider));
      final picked = <Question>[];
      for (final s in insights.ranked()) {
        final pool = bank.where((q) => s.bankSections.contains(q.subject)).toList()..shuffle(rng);
        picked.addAll(pool.take(s.questions));
      }
      _title = 'Full ${insights.exam} mock';
      _questions = picked;
      _marking = MarkingScheme(correct: 2, wrong: insights.negativeMarks);
      _limit = Duration(minutes: (insights.durationMinutes * picked.length / insights.questionCount).ceil().clamp(1, 600));
    } else if (widget.testId.startsWith('subject:')) {
      final name = widget.testId.substring('subject:'.length);
      final s = subjectNamed(insightsFor(ref.read(certTrackProvider)), name);
      final pool = bank.where((q) => s?.bankSections.contains(q.subject) ?? false).toList()..shuffle(rng);
      _title = name;
      _questions = pool.take(25).toList();
      _marking = const MarkingScheme();
      _limit = Duration(minutes: _questions.length.clamp(1, 25));
    } else {
      final count = widget.testId == 'fall-in' ? 5 : 10;
      _title = widget.testId == 'fall-in' ? 'Daily Fall-In' : 'Quick practice';
      _questions = (List.of(bank)..shuffle(rng)).take(count).toList();
      _marking = const MarkingScheme();
      _limit = Duration(minutes: count);
    }
    _startTimer();
  }

  /// A unit test: take it if it is open, or review it once it has closed.
  Future<void> _openHosted(TestDefinition def) async {
    final now = ref.read(clockProvider)();
    final fmt = DateFormat('EEE d MMM, h:mm a');
    if (def.attempted && !def.hasClosed(now)) {
      _blocked = 'You scored ${_fmtScore(def.myScore!)} / ${_fmtScore(def.maxScore)}. '
          '${def.closesAt == null ? 'The answer key unlocks when your ANO closes the test.' : 'The answer key unlocks when the test closes on ${fmt.format(def.closesAt!)}.'}';
      return;
    }
    if (!def.attempted && !def.hasOpened(now)) {
      _blocked = 'This test opens on ${fmt.format(def.opensAt!)}.';
      return;
    }
    if (!def.attempted && def.hasClosed(now)) {
      _blocked = 'This test closed on ${fmt.format(def.closesAt!)} before you took it.';
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final repo = ref.read(unitRepositoryProvider)!;
      final questions = await repo.testQuestions(def.id);
      final mine = def.attempted ? await repo.myAnswers(def.id) : const <String, int?>{};
      if (!mounted) return;
      setState(() {
        _loading = false;
        _questions = def.attempted ? questions : (List.of(questions)..shuffle());
        if (def.attempted) {
          _reviewOnly = true;
          _serverScore = def.myScore;
          for (final e in mine.entries) {
            if (e.value != null) _answers[e.key] = e.value!;
          }
          _result = scoreTest(questions: _questions, answers: _answers, marking: _marking);
        }
      });
      if (!def.attempted) _startTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '$e';
        });
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _result != null || _submitting) return;
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed >= _limit) _submit();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_hosted != null && _result == null && !_reviewOnly && state == AppLifecycleState.paused) _focusLost++;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    _timer?.cancel();
    final local = scoreTest(questions: _questions, answers: _answers, marking: _marking);
    final hosted = _hosted;
    if (hosted == null) return setState(() => _result = local);

    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final score = await ref
          .read(unitRepositoryProvider)!
          .submitAttempt(hosted.id, Map.of(_answers), focusLost: _focusLost);
      if (!mounted) return;
      ref.read(testsProvider.notifier).markTaken(hosted.id, score);
      setState(() {
        _submitting = false;
        _serverScore = score;
        _result = local;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitError = '$e';
        });
      }
    }
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
    if (_blocked != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: EmptyState(
          icon: _hosted?.attempted == true ? Icons.task_alt : Icons.lock_clock_outlined,
          title: _hosted?.attempted == true ? 'Submitted' : 'Not available',
          message: _blocked!,
        ),
      );
    }
    if (_loading) {
      return Scaffold(appBar: AppBar(title: Text(_title)), body: const Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: PageBody(children: [
          EmptyState(icon: Icons.cloud_off, title: "Couldn't open the test", message: _loadError!),
          Center(child: FilledButton(onPressed: () => _openHosted(_hosted!), child: const Text('Try again'))),
        ]),
      );
    }
    if (_submitting || _submitError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_title), automaticallyImplyLeading: false),
        body: _submitting
            ? const Center(child: CircularProgressIndicator())
            : PageBody(children: [
                EmptyState(icon: Icons.cloud_off, title: 'Not submitted yet', message: _submitError!),
                Center(child: FilledButton(onPressed: _submit, child: const Text('Submit again'))),
              ]),
      );
    }
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: const EmptyState(icon: Icons.quiz_outlined, title: 'No questions yet',
            message: 'Your ANO approves précis questions in the Command Center; they will appear here for practice.'),
      );
    }
    if (_result != null) {
      final now = ref.read(clockProvider)();
      final keyLocked = _hosted != null && !_hosted!.hasClosed(now);
      return _ResultView(
        title: _title,
        result: _result!,
        questions: _questions,
        answers: _answers,
        score: _serverScore,
        showAnswers: !keyLocked,
        note: keyLocked
            ? 'Submitted and marked. The answer key unlocks when the test closes, so it can\'t be passed around.'
            : null,
      );
    }

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
  const _ResultView({
    required this.title,
    required this.result,
    required this.questions,
    required this.answers,
    this.score,
    this.showAnswers = true,
    this.note,
  });

  final String title;
  final TestResult result;
  final List<Question> questions;
  final Map<String, int> answers;

  /// The score the server gave, for hosted tests.
  final double? score;
  final bool showAnswers;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    String n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(title: Text('$title · Result')),
      body: PageBody(children: [
        Text('${n(score ?? result.score)} / ${n(result.maxScore)}', style: t.displaySmall),
        Text('${result.percentage.round()}% · ${result.correct} right · ${result.wrong} wrong · ${result.skipped} skipped',
            style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
        if (result.weakSubjects.isNotEmpty) ...[
          const SectionHeader('Work on these'),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            for (final s in result.weakSubjects)
              Chip(label: Text('${s.subject} · ${(s.accuracy * 100).round()}%')),
          ]),
        ],
        if (note != null) ...[
          const SizedBox(height: Space.lg),
          Card(child: ListTile(leading: const Icon(Icons.lock_outline), title: Text(note!))),
        ],
        if (showAnswers) ...[
          const SectionHeader('Review answers'),
          for (final q in questions) _ReviewCard(question: q, chosen: answers[q.id]),
        ],
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

String _fmtScore(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
