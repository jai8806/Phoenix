import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/comms.dart';
import '../../data/models/test.dart';
import '../../data/providers.dart';
import '../../data/unit_repository.dart';
import '../../domain/omr/exam_pattern.dart';
import '../omr/question_paper_pdf.dart';
import '../shared/widgets.dart';

/// The questions already in a test (covers ones the unit wrote itself).
final draftQuestionsProvider = FutureProvider.autoDispose.family<List<Question>, String>((ref, id) async {
  final repo = ref.watch(unitRepositoryProvider);
  if (repo == null) return const [];
  return repo.testQuestions(id);
});

/// A generated mock before cadets see it: laid out like the real paper, with
/// the answer to every question, so the CSUO / SUO / ANO can check it, swap
/// or correct questions, and then schedule it.
class MockDraftScreen extends ConsumerStatefulWidget {
  const MockDraftScreen({super.key, required this.testId});

  final String testId;

  @override
  ConsumerState<MockDraftScreen> createState() => _MockDraftScreenState();
}

class _MockDraftScreenState extends ConsumerState<MockDraftScreen> {
  Map<int, String>? _byNumber;
  final Map<String, Question> _extra = {}; // questions not in the approved bank (unit-written)
  final Set<int> _changed = {};
  bool _saving = false;
  final _rng = Random();

  Map<String, Question> _known() => {
        for (final q in ref.read(questionBankProvider)) q.id: q,
        for (final q in ref.read(draftQuestionsProvider(widget.testId)).value ?? const <Question>[]) q.id: q,
        ..._extra,
      };

  Future<void> _apply(Map<int, String> next, Iterable<int> touched, {String? done}) async {
    final before = _byNumber!;
    setState(() {
      _byNumber = next;
      _changed.addAll(touched);
      _saving = true;
    });
    try {
      await ref.read(testsProvider.notifier).setQuestions(widget.testId, next);
      if (done != null && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(done), duration: const Duration(seconds: 2)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _byNumber = before);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is UnitDataFailure ? e.message : "Couldn't save the change. Try again.")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Question> _pool(ExamPattern pattern, int n) {
    final section = pattern.slot(n).$2;
    final used = _byNumber!.values.toSet();
    return [for (final q in ref.read(questionBankProvider)) if (section.matches(q) && !used.contains(q.id)) q];
  }

  Future<void> _replace(ExamPattern pattern, int n) async {
    final pool = _pool(pattern, n);
    if (pool.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No other approved ${pattern.slot(n).$2.subject} questions. Write one with Edit.')));
      return;
    }
    await _apply({..._byNumber!, n: pool[_rng.nextInt(pool.length)].id}, [n], done: 'Q$n replaced');
  }

  Future<void> _fillEmpty(ExamPattern pattern) async {
    final next = {..._byNumber!};
    final touched = <int>[];
    for (var n = 1; n <= pattern.questionCount; n++) {
      if (next.containsKey(n)) continue;
      final section = pattern.slot(n).$2;
      final used = next.values.toSet();
      final pool = [for (final q in ref.read(questionBankProvider)) if (section.matches(q) && !used.contains(q.id)) q];
      if (pool.isEmpty) continue;
      next[n] = pool[_rng.nextInt(pool.length)].id;
      touched.add(n);
    }
    if (touched.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The bank has no more questions for the empty sections. Approve more, or write them with Edit.')));
      return;
    }
    await _apply(next, touched, done: 'Filled ${touched.length} question${touched.length == 1 ? '' : 's'}');
  }

  Future<void> _choose(ExamPattern pattern, int n) async {
    final section = pattern.slot(n).$2;
    final picked = await showModalBottomSheet<Question>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BankPicker(title: 'Q$n · ${section.subject}', questions: _pool(pattern, n)),
    );
    if (picked != null) await _apply({..._byNumber!, n: picked.id}, [n], done: 'Q$n changed');
  }

  Future<void> _edit(ExamPattern pattern, int n, Question? current) async {
    final section = pattern.slot(n).$2;
    final edited = await showDialog<Question>(
      context: context,
      builder: (_) => _EditQuestionDialog(number: n, subject: current?.subject ?? section.subject, initial: current),
    );
    if (edited == null || !mounted) return;
    try {
      final saved = await ref.read(unitRepositoryProvider)?.addUnitQuestion(edited) ??
          Question(id: 'local${DateTime.now().microsecondsSinceEpoch}', subject: edited.subject, prompt: edited.prompt,
              options: edited.options, correctIndex: edited.correctIndex);
      _extra[saved.id] = saved;
      await _apply({..._byNumber!, n: saved.id}, [n], done: 'Q$n saved');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _remove(int n) async {
    final next = {..._byNumber!}..remove(n);
    await _apply(next, [n], done: 'Q$n removed');
  }

  Future<void> _sharePdf(ExamPattern pattern, TestDefinition test) async {
    final known = _known();
    final bytes = await buildQuestionPaperPdf(
      pattern: pattern,
      title: test.title,
      unitName: ref.read(authControllerProvider)?.unitName,
      byNumber: {for (final e in _byNumber!.entries) if (known[e.value] != null) e.key: known[e.value]!},
    );
    await Printing.sharePdf(bytes: bytes, filename: 'DRAFT ${test.title}.pdf');
  }

  Future<void> _publish(ExamPattern pattern, TestDefinition test) async {
    final result = await showDialog<_PublishChoice>(
      context: context,
      builder: (_) => _PublishDialog(test: test, pattern: pattern, missing: pattern.questionCount - _byNumber!.length),
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(testsProvider.notifier).publish(test.id, scheduledFor: result.when, title: result.title);
      if (result.addToCalendar) {
        final now = ref.read(clockProvider)();
        final replyBy = result.when.subtract(const Duration(hours: 12));
        await ref.read(eventsProvider.notifier).add(CalendarEvent(
              id: 'e${DateTime.now().microsecondsSinceEpoch}',
              title: result.title,
              kind: EventKind.exam,
              startsAt: result.when,
              details: '${pattern.name} OMR mock, exactly like the real paper: ${pattern.questionCount} questions, '
                  '${fmtNum(pattern.totalMarks)} marks, ${pattern.durationMinutes ~/ 60} hours. '
                  'Bring a black ball pen and your phone (charged). The OMR sheet is given at the hall.',
              needsResponse: true,
              respondBy: replyBy.isAfter(now) ? replyBy : null,
            ));
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('Published. Cadets see it in Learn${result.addToCalendar ? ' and on the calendar' : ''}. '
              'Print the OMR sheets from the mock, and start it on the day.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is UnitDataFailure ? e.message : '$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final test = ref.watch(testsProvider).where((t) => t.id == widget.testId).firstOrNull;
    ref.watch(questionBankProvider);
    final loaded = ref.watch(draftQuestionsProvider(widget.testId));
    final user = ref.watch(authControllerProvider);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    if (test == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Draft not found', message: 'It may have been deleted.'));
    }
    if (loaded.isLoading && _byNumber == null) {
      return Scaffold(appBar: AppBar(title: Text(test.title)), body: const Center(child: CircularProgressIndicator()));
    }
    _byNumber ??= {
      for (var i = 0; i < test.questionIds.length; i++) (i < test.numbers.length ? test.numbers[i] : i + 1): test.questionIds[i],
    };
    final pattern = ExamPattern.byId(test.pattern ?? 'bcert');
    final known = _known();
    final byNumber = _byNumber!;
    final missing = pattern.questionCount - byNumber.length;
    final canPublish = user?.isCommand ?? false;

    // Flat list: header, then per paper a title, per section a heading, then questions.
    final items = <Widget>[
      _DraftBanner(missing: missing, changed: _changed.length, saving: _saving, canPublish: canPublish),
      const SizedBox(height: Space.md),
      _PaperHeader(pattern: pattern, title: test.title, unitName: user?.unitName),
    ];
    var n = 1;
    for (final paper in pattern.papers) {
      items.add(Padding(
        padding: const EdgeInsets.only(top: Space.xl, bottom: Space.xs),
        child: Column(children: [
          Text(paper.title, textAlign: TextAlign.center, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          Text(paperMarksLine(paper, pattern.marking.correct), style: t.labelLarge),
        ]),
      ));
      for (final s in paper.sections) {
        if (paper.sections.length > 1) {
          final have = [for (var k = n; k < n + s.count; k++) if (byNumber.containsKey(k)) k].length;
          items.add(Padding(
            padding: const EdgeInsets.only(top: Space.lg, bottom: Space.sm),
            child: Row(children: [
              Expanded(child: Text(sectionHeading(s, pattern.marking.correct), style: t.titleSmall?.copyWith(color: c.primary))),
              if (have < s.count) Text('${s.count - have} empty', style: t.labelMedium?.copyWith(color: context.status.warning)),
            ]),
          ));
        }
        for (var i = 0; i < s.count; i++) {
          final number = n;
          final q = byNumber[number] == null ? null : known[byNumber[number]];
          items.add(_DraftQuestion(
            number: number,
            question: q,
            missingText: byNumber[number] != null && q == null,
            changed: _changed.contains(number),
            onReplace: () => _replace(pattern, number),
            onChoose: () => _choose(pattern, number),
            onEdit: () => _edit(pattern, number, q),
            onRemove: byNumber[number] == null ? null : () => _remove(number),
          ));
          n++;
        }
      }
    }
    items.add(const SizedBox(height: 96));

    return Scaffold(
      appBar: AppBar(
        title: Text('Draft · ${test.title}'),
        actions: [
          IconButton(
            tooltip: 'Share the draft as PDF (with answer key)',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => _sharePdf(pattern, test),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContentWidth),
          child: ListView.builder(
            padding: const EdgeInsets.all(Space.lg),
            itemCount: items.length,
            itemBuilder: (_, i) => items[i],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
          child: Row(children: [
            if (missing > 0) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => _fillEmpty(pattern),
                  icon: const Icon(Icons.auto_fix_high),
                  label: Text('Fill $missing empty'),
                ),
              ),
              const SizedBox(width: Space.sm),
            ],
            Expanded(
              child: FilledButton.icon(
                onPressed: _saving || !canPublish ? null : () => _publish(pattern, test),
                icon: const Icon(Icons.event_available),
                label: Text(canPublish ? 'Schedule & publish' : 'CSUO / SUO / ANO publishes'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _DraftBanner extends StatelessWidget {
  const _DraftBanner({required this.missing, required this.changed, required this.saving, required this.canPublish});

  final int missing;
  final int changed;
  final bool saving;
  final bool canPublish;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(color: c.secondaryContainer, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.visibility_off_outlined, color: c.onSecondaryContainer),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Draft: cadets can\'t see this yet', style: t.titleSmall?.copyWith(color: c.onSecondaryContainer)),
            const SizedBox(height: 2),
            Text(
              'Check each question and its answer (in green). Tap ⋮ to replace, pick from the bank, correct or remove one. '
              'Changes save as you go, so other seniors see them.${canPublish ? '' : ' A CSUO, SUO or the ANO publishes it.'}',
              style: t.bodySmall?.copyWith(color: c.onSecondaryContainer),
            ),
            const SizedBox(height: Space.xs),
            Text(
              [
                missing == 0 ? 'All questions in place' : '$missing empty',
                if (changed > 0) '$changed changed',
                if (saving) 'Saving…',
              ].join(' · '),
              style: t.labelMedium?.copyWith(color: missing == 0 ? context.status.success : context.status.warning),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// The top of the real paper.
class _PaperHeader extends StatelessWidget {
  const _PaperHeader({required this.pattern, required this.title, this.unitName});

  final ExamPattern pattern;
  final String title;
  final String? unitName;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final b = t.bodyMedium?.copyWith(fontWeight: FontWeight.w700);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(pattern.directorate, textAlign: TextAlign.center, style: b),
          Text('${pattern.heading} – ${DateTime.now().year}', textAlign: TextAlign.center, style: b),
          Text(pattern.candidates, textAlign: TextAlign.center, style: b),
          const SizedBox(height: Space.xs),
          Text(title, textAlign: TextAlign.center, style: t.bodySmall),
          const Divider(height: Space.xl),
          Wrap(spacing: Space.lg, runSpacing: Space.xs, children: [
            Text('Unit: ${unitName ?? '________'}', style: t.bodySmall),
            Text('Common subject: ${fmtNum(pattern.commonMarks)} Marks', style: t.bodySmall),
            Text('Special Subject: ${fmtNum(pattern.specialMarks)} Marks', style: t.bodySmall),
            Text('Total Marks: ${fmtNum(pattern.totalMarks)} Marks', style: t.bodySmall),
            Text('Pass Marks: ${fmtNum(pattern.passPercent)}% in each paper', style: t.bodySmall),
            Text('Time allotted: ${pattern.durationMinutes ~/ 60} Hrs', style: t.bodySmall),
          ]),
          const SizedBox(height: Space.sm),
          Text('General Instructions:', style: t.labelLarge),
          for (final (i, line) in pattern.instructions.indexed) Text('${i + 1}. $line', style: t.bodySmall),
          const SizedBox(height: Space.sm),
          Text('Pattern: ${pattern.basedOn}', style: t.labelSmall?.copyWith(color: c.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _DraftQuestion extends StatelessWidget {
  const _DraftQuestion({
    required this.number,
    required this.question,
    required this.missingText,
    required this.changed,
    required this.onReplace,
    required this.onChoose,
    required this.onEdit,
    this.onRemove,
  });

  final int number;
  final Question? question;
  final bool missingText; // a question id we couldn't load
  final bool changed;
  final VoidCallback onReplace;
  final VoidCallback onChoose;
  final VoidCallback onEdit;
  final VoidCallback? onRemove;

  static const letters = ['A', 'B', 'C', 'D'];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final q = question;
    final menu = PopupMenuButton<String>(
      tooltip: 'Change Q$number',
      onSelected: (v) => switch (v) {
        'replace' => onReplace(),
        'choose' => onChoose(),
        'edit' => onEdit(),
        _ => onRemove?.call(),
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'replace', child: Text(q == null ? 'Fill with a random question' : 'Replace with another')),
        const PopupMenuItem(value: 'choose', child: Text('Choose from the bank')),
        PopupMenuItem(value: 'edit', child: Text(q == null ? 'Write a question' : 'Correct this question')),
        if (onRemove != null) const PopupMenuItem(value: 'remove', child: Text('Remove')),
      ],
    );
    return Card(
      margin: const EdgeInsets.only(bottom: Space.sm),
      color: q == null ? c.errorContainer.withValues(alpha: 0.35) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, 0, Space.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 40, child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('$number.', style: t.titleSmall),
            )),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: q == null
                    ? Text(missingText ? 'Question could not be loaded' : 'Empty: no question yet',
                        style: t.bodyMedium?.copyWith(color: c.error, fontStyle: FontStyle.italic))
                    : Text(q.prompt, style: t.bodyMedium),
              ),
            ),
            menu,
          ]),
          if (q != null) ...[
            for (final (i, o) in q.options.indexed)
              Padding(
                padding: const EdgeInsets.only(left: 40, right: Space.md, top: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${letters[i]})  ', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700,
                      color: i == q.correctIndex ? context.status.success : null)),
                  Expanded(
                    child: Text(o, style: t.bodySmall?.copyWith(
                      color: i == q.correctIndex ? context.status.success : null,
                      fontWeight: i == q.correctIndex ? FontWeight.w700 : null,
                    )),
                  ),
                  if (i == q.correctIndex) Icon(Icons.check_circle, size: 16, color: context.status.success),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 40, right: Space.md, top: Space.xs),
              child: Text(
                [q.subject, if (q.explanation != null && q.explanation!.isNotEmpty) q.explanation!, if (changed) 'changed'].join(' · '),
                style: t.labelSmall?.copyWith(color: c.onSurfaceVariant),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _BankPicker extends StatefulWidget {
  const _BankPicker({required this.title, required this.questions});

  final String title;
  final List<Question> questions;

  @override
  State<_BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends State<_BankPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final shown = [for (final q in widget.questions) if (_q.isEmpty || q.prompt.toLowerCase().contains(_q)) q];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          child: Text(widget.title, style: t.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: TextField(
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search this section\'s questions'),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const EmptyState(icon: Icons.inbox_outlined, title: 'No unused questions here',
                  message: 'Approve more in the review queue, or write one with "Write a question".')
              : ListView.separated(
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final q = shown[i];
                    return ListTile(
                      title: Text(q.prompt),
                      subtitle: Text('Answer: ${q.options[q.correctIndex]}'),
                      onTap: () => Navigator.of(context).pop(q),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class _EditQuestionDialog extends StatefulWidget {
  const _EditQuestionDialog({required this.number, required this.subject, this.initial});

  final int number;
  final String subject;
  final Question? initial;

  @override
  State<_EditQuestionDialog> createState() => _EditQuestionDialogState();
}

class _EditQuestionDialogState extends State<_EditQuestionDialog> {
  late final _prompt = TextEditingController(text: widget.initial?.prompt);
  late final _options = [for (var i = 0; i < 4; i++) TextEditingController(text: widget.initial?.options.elementAtOrNull(i))];
  late int _answer = widget.initial?.correctIndex ?? 0;
  String? _error;

  @override
  void dispose() {
    _prompt.dispose();
    for (final o in _options) {
      o.dispose();
    }
    super.dispose();
  }

  void _save() {
    final p = _prompt.text.trim();
    final opts = [for (final o in _options) o.text.trim()];
    if (p.length < 5) return setState(() => _error = 'Write the question.');
    if (opts.any((o) => o.isEmpty)) return setState(() => _error = 'Fill in all four options.');
    if (opts.toSet().length < 4) return setState(() => _error = 'The four options must be different.');
    Navigator.of(context).pop(Question(id: '', subject: widget.subject, prompt: p, options: opts, correctIndex: _answer,
        explanation: 'Written by the unit'));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(widget.initial == null ? 'Write Q${widget.number}' : 'Correct Q${widget.number}'),
      scrollable: true,
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.subject, style: t.labelLarge),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _prompt,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Question'),
          ),
          const SizedBox(height: Space.md),
          Text('Options: tick the correct answer', style: t.labelMedium),
          RadioGroup<int>(
            groupValue: _answer,
            onChanged: (v) => setState(() => _answer = v ?? _answer),
            child: Column(children: [
              for (var i = 0; i < 4; i++)
                Row(children: [
                  Radio<int>(value: i),
                  Expanded(
                    child: TextField(
                      controller: _options[i],
                      decoration: InputDecoration(labelText: 'Option ${'ABCD'[i]}', isDense: true),
                    ),
                  ),
                ]),
            ]),
          ),
          const SizedBox(height: Space.sm),
          Text(
            widget.initial == null
                ? 'Saved to your unit\'s question bank as approved.'
                : 'Saves a corrected copy for your unit; the original précis question is left as it is.',
            style: t.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.sm),
            Text(_error!, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save question')),
      ],
    );
  }
}

class _PublishChoice {
  const _PublishChoice(this.title, this.when, this.addToCalendar);
  final String title;
  final DateTime when;
  final bool addToCalendar;
}

class _PublishDialog extends ConsumerStatefulWidget {
  const _PublishDialog({required this.test, required this.pattern, required this.missing});

  final TestDefinition test;
  final ExamPattern pattern;
  final int missing;

  @override
  ConsumerState<_PublishDialog> createState() => _PublishDialogState();
}

class _PublishDialogState extends ConsumerState<_PublishDialog> {
  late final _title = TextEditingController(text: widget.test.title);
  late DateTime _date = () {
    final d = ref.read(clockProvider)().add(const Duration(days: 1));
    return DateTime(d.year, d.month, d.day);
  }();
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 30);
  bool _calendar = true;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final now = ref.read(clockProvider)();
    return AlertDialog(
      title: const Text('Schedule & publish'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.missing > 0)
            Container(
              margin: const EdgeInsets.only(bottom: Space.md),
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(color: c.errorContainer, borderRadius: BorderRadius.circular(Radii.sm)),
              child: Text('${widget.missing} question number${widget.missing == 1 ? ' is' : 's are'} still empty. '
                  'Cadets will leave ${widget.missing == 1 ? 'it' : 'them'} blank on the sheet.',
                  style: t.bodySmall?.copyWith(color: c.onErrorContainer)),
            ),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Name cadets see')),
          const SizedBox(height: Space.md),
          Text('Exam day and time', style: t.labelLarge),
          const SizedBox(height: Space.sm),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(DateFormat('EEE d MMM').format(_date)),
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: now.add(const Duration(days: 365)));
                  if (d != null) setState(() => _date = d);
                },
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(_time.format(context)),
                onPressed: () async {
                  final p = await showTimePicker(context: context, initialTime: _time);
                  if (p != null) setState(() => _time = p);
                },
              ),
            ),
          ]),
          const SizedBox(height: Space.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _calendar,
            onChanged: (v) => setState(() => _calendar = v),
            title: const Text('Add to the unit calendar'),
            subtitle: const Text('With roll-call, so you know who is coming and how many OMR sheets to print.'),
          ),
          Text('Cadets see the mock in Learn from now on. You start it in the hall on the day; the paper runs '
              '${widget.pattern.durationMinutes ~/ 60} hours.', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
          if (_error != null) ...[
            const SizedBox(height: Space.sm),
            Text(_error!, style: t.bodySmall?.copyWith(color: c.error)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Not yet')),
        FilledButton(
          onPressed: () {
            final title = _title.text.trim();
            if (title.isEmpty) return setState(() => _error = 'Give it a name.');
            final when = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
            if (!when.isAfter(now)) return setState(() => _error = 'Pick a time in the future.');
            Navigator.of(context).pop(_PublishChoice(title, when, _calendar));
          },
          child: const Text('Publish'),
        ),
      ],
    );
  }
}
