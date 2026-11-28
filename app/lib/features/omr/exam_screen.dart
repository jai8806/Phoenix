import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/test.dart';
import '../../data/providers.dart';
import '../../domain/omr/exam_pattern.dart';
import '../../domain/omr/exam_session.dart';
import '../shared/widgets.dart';
import 'omr_sheet_pdf.dart';
import 'scan_runner.dart';

/// Where sheet photos come from: the camera or gallery, or a test's own picture.
final sheetPhotoSourceProvider = Provider<Future<Uint8List?> Function(ImageSource source)?>((ref) => null);

/// An OMR mock, from the cadet's side: wait for the start, read the paper,
/// scan the sheet, see the result.
class ExamScreen extends ConsumerStatefulWidget {
  const ExamScreen({super.key, required this.testId});

  final String testId;

  @override
  ConsumerState<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends ConsumerState<ExamScreen> with WidgetsBindingObserver {
  Timer? _tick;
  List<PaperItem>? _paper;
  String? _loadError;
  bool _scanning = false; // the cadet chose to scan before time was up
  int _focusLost = 0;

  // After submitting.
  Map<int, int?>? _submittedSheet;
  double? _score;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {});
      // While waiting for the ANO, check for the start every 15 seconds.
      final test = _test;
      if (test != null && test.startedAt == null && t.tick % 15 == 0) ref.read(testsProvider.notifier).reload();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final t = _test;
    if (t != null && state == AppLifecycleState.paused && examPhase(t, DateTime.now()) == ExamPhase.paper) _focusLost++;
  }

  TestDefinition? get _test {
    for (final t in ref.read(testsProvider)) {
      if (t.id == widget.testId) return t;
    }
    return null;
  }

  String get _set => setFor(ref.read(authControllerProvider)?.id ?? '', widget.testId);

  Future<void> _loadPaper(TestDefinition t) async {
    if (_paper != null || _loadError != null) return;
    try {
      final repo = ref.read(unitRepositoryProvider);
      final questions = repo == null
          ? [for (final q in ref.read(questionBankProvider)) if (t.questionIds.contains(q.id)) q]
          : await repo.testQuestions(t.id);
      if (!mounted) return;
      setState(() => _paper = paperFor(t, {for (final q in questions) q.id: q}, _set));
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(testsProvider);
    final t = _test;
    if (t == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Exam not found', message: 'It may have been deleted.'));
    }
    final now = DateTime.now();
    final phase = examPhase(t, now);

    Widget body;
    String title = t.title;
    if (_submittedSheet != null && _paper != null) {
      body = _ResultView(test: t, paper: _paper!, sheet: _submittedSheet!, score: _score!);
    } else if (t.attempted) {
      body = EmptyState(
        icon: Icons.task_alt,
        title: 'Submitted · ${fmtScore(t.myScore!)} / ${fmtScore(t.maxScore)}',
        message: phase == ExamPhase.closed
            ? 'The exam is over. Review your answers to see where you lost marks.'
            : 'The answer key opens when the exam closes${t.closesAt == null ? '' : ' at ${DateFormat('h:mm a').format(t.closesAt!)}'}.',
        action: phase == ExamPhase.closed
            ? FilledButton(onPressed: () => context.push(Routes.quiz(t.id)), child: const Text('Review answers'))
            : null,
      );
    } else {
      switch (phase) {
        case ExamPhase.waiting:
          body = _Lobby(test: t, set: _set, onRefresh: () => ref.read(testsProvider.notifier).reload());
        case ExamPhase.paper when !_scanning:
          _loadPaper(t);
          title = '${t.title} · Set $_set';
          body = _loadError != null
              ? EmptyState(icon: Icons.cloud_off, title: "Couldn't load the paper", message: _loadError!)
              : _paper == null
                  ? const Center(child: CircularProgressIndicator())
                  : _PaperView(
                      test: t,
                      set: _set,
                      paper: _paper!,
                      remaining: t.paperEndsAt!.difference(now),
                      onFinish: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Finished the paper?'),
                            content: const Text('Check every answer is darkened on your OMR sheet, then scan it.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep going')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Scan my sheet')),
                            ],
                          ),
                        );
                        if (ok == true) setState(() => _scanning = true);
                      },
                    );
        case ExamPhase.paper:
        case ExamPhase.scanning:
          _loadPaper(t);
          title = 'Scan your OMR sheet';
          body = _paper == null
              ? (_loadError != null
                  ? EmptyState(icon: Icons.cloud_off, title: "Couldn't load the paper", message: _loadError!)
                  : const Center(child: CircularProgressIndicator()))
              : ScanFlow(
                  test: t,
                  set: _set,
                  paper: _paper!,
                  focusLost: _focusLost,
                  closesAt: t.closesAt,
                  onSubmitted: (sheet, score) => setState(() {
                    _submittedSheet = sheet;
                    _score = score;
                  }),
                );
        case ExamPhase.closed:
          body = EmptyState(
            icon: Icons.event_busy_outlined,
            title: 'This exam has closed',
            message: 'Uploads closed${t.closesAt == null ? '' : ' at ${DateFormat('h:mm a').format(t.closesAt!)}'}. Ask your ANO if you missed it.',
          );
      }
    }
    return Scaffold(appBar: AppBar(title: Text(title)), body: body);
  }
}

String fmtScore(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

class _Lobby extends StatelessWidget {
  const _Lobby({required this.test, required this.set, required this.onRefresh});

  final TestDefinition test;
  final String set;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final pattern = ExamPattern.byId(test.pattern ?? 'bcert');
    return PageBody(children: [
      Card(
        color: c.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('YOUR SET', style: t.labelMedium?.copyWith(color: c.onPrimaryContainer, letterSpacing: 1.1)),
            Text(set, style: t.displaySmall?.copyWith(color: c.onPrimaryContainer, fontWeight: FontWeight.w700)),
            Text('Darken $set in the SET box of your OMR sheet.', style: t.bodyMedium?.copyWith(color: c.onPrimaryContainer)),
          ]),
        ),
      ),
      const SizedBox(height: Space.lg),
      Text('${pattern.name} mock · ${test.questionIds.length} questions · ${test.durationMinutes ~/ 60} h'
          '${test.durationMinutes % 60 == 0 ? '' : ' ${test.durationMinutes % 60} min'} · '
          '+${fmtScore(test.marking.correct)} / −${fmtScore(test.marking.wrong)}',
          style: t.titleSmall),
      const SectionHeader('Before you start'),
      const ListCard(children: [
        ListTile(leading: Icon(Icons.edit_outlined), title: Text('A black or blue ball pen')),
        ListTile(leading: Icon(Icons.description_outlined), title: Text('Your printed Phoenix OMR sheet'), subtitle: Text('Write your regimental number and name on it.')),
        ListTile(leading: Icon(Icons.radio_button_checked), title: Text('Fill each circle fully'), subtitle: Text('One answer per question. Two marks count as wrong.')),
        ListTile(leading: Icon(Icons.photo_camera_outlined), title: Text('At the end you will photograph the sheet'), subtitle: Text('Keep it flat and clean; don\'t fold it.')),
      ]),
      const SizedBox(height: Space.xl),
      Center(
        child: Column(children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(height: Space.sm),
          Text('Waiting for your ANO to start the exam…', style: t.bodyMedium),
          TextButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh), label: const Text('Check now')),
        ]),
      ),
    ]);
  }
}

class _PaperView extends StatelessWidget {
  const _PaperView({required this.test, required this.set, required this.paper, required this.remaining, required this.onFinish});

  final TestDefinition test;
  final String set;
  final List<PaperItem> paper;
  final Duration remaining;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    String hms(Duration d) {
      if (d.isNegative) return '0:00:00';
      return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    }

    final rows = <Object>[];
    PatternPaper? current;
    for (final item in paper) {
      if (item.paper != current) {
        current = item.paper;
        rows.add(current);
      }
      rows.add(item);
    }
    return Column(children: [
      Material(
        color: remaining.inMinutes < 10 ? c.errorContainer : c.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
          child: Row(children: [
            Icon(Icons.timer_outlined, size: 18, color: remaining.inMinutes < 10 ? c.error : c.onSurfaceVariant),
            const SizedBox(width: Space.xs),
            Text(hms(remaining), style: t.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text('Set $set · mark answers on your sheet',
                  style: t.labelMedium, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 96),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final row = rows[i];
            if (row is PatternPaper) {
              return Padding(
                padding: const EdgeInsets.only(top: Space.md, bottom: Space.sm),
                child: Text('${row.title} (${fmtScore(row.count * test.marking.correct)} MARKS)',
                    style: t.titleSmall?.copyWith(color: c.primary, fontWeight: FontWeight.w700)),
              );
            }
            final item = row as PaperItem;
            return Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${item.number}. ${item.question.prompt}', style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: Space.xs),
                for (final (k, o) in item.question.options.indexed)
                  Padding(
                    padding: const EdgeInsets.only(left: Space.md, top: 2),
                    child: Text('(${String.fromCharCode(97 + k)}) $o', style: t.bodyMedium),
                  ),
              ]),
            );
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onFinish,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Finished · scan my sheet'),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Photograph, check and submit the OMR sheet.
class ScanFlow extends ConsumerStatefulWidget {
  const ScanFlow({
    super.key,
    required this.test,
    required this.set,
    required this.paper,
    required this.focusLost,
    required this.onSubmitted,
    this.closesAt,
    this.pick,
  });

  final TestDefinition test;
  final String set;
  final List<PaperItem> paper;
  final int focusLost;
  final DateTime? closesAt;
  final void Function(Map<int, int?> sheet, double score) onSubmitted;

  /// Picks a photo; replaced in tests.
  final Future<Uint8List?> Function(ImageSource source)? pick;

  @override
  ConsumerState<ScanFlow> createState() => _ScanFlowState();
}

class _ScanFlowState extends ConsumerState<ScanFlow> {
  bool _busy = false;
  String? _problem;
  ScanOutcome? _scan;
  final Map<int, int?> _fixed = {}; // sheet number -> the cadet's reading of a flagged mark
  bool _submitting = false;
  String? _submitError;

  Future<Uint8List?> _pick(ImageSource source) async {
    if (widget.pick != null) return widget.pick!(source);
    final override = ref.read(sheetPhotoSourceProvider);
    if (override != null) return override(source);
    final file = await ImagePicker().pickImage(source: source, maxWidth: 2600, imageQuality: 92);
    return file?.readAsBytes();
  }

  Future<void> _take(ImageSource source) async {
    final photo = await _pick(source);
    if (photo == null || !mounted) return;
    setState(() {
      _busy = true;
      _problem = null;
      _scan = null;
      _fixed.clear();
    });
    final out = await scanSheet(photo, widget.test.pattern ?? 'bcert');
    if (!mounted) return;
    String? problem = out.problem;
    if (problem == null && out.sheetCode != null && widget.test.sheetCode != null && out.sheetCode != widget.test.sheetCode) {
      problem = 'This sheet is for a different test (${formatSheetCode(out.sheetCode!)}). '
          'Use the sheet given out for this mock (${formatSheetCode(widget.test.sheetCode!)}).';
    }
    setState(() {
      _busy = false;
      _problem = problem;
      _scan = problem == null ? out : null;
    });
  }

  Map<int, int?> get _sheet => {...?_scan?.answers, ..._fixed};

  Future<void> _submit() async {
    final scan = _scan!;
    final repo = ref.read(unitRepositoryProvider);
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final sheet = _sheet;
      String? path;
      if (repo != null && scan.upload != null) path = await repo.uploadSheet(widget.test.id, scan.upload!);
      final answers = answersByQuestion(widget.paper, sheet);
      final flags = scan.flags.length + (scan.setLabel != null && scan.setLabel != widget.set ? 1 : 0);
      final score = repo == null
          ? 0.0
          : await repo.submitAttempt(widget.test.id, answers,
              focusLost: widget.focusLost, sheetPath: path, setLabel: widget.set, scanFlags: flags, corrected: _fixed.length);
      if (!mounted) return;
      ref.read(testsProvider.notifier).markTaken(widget.test.id, score);
      widget.onSubmitted(sheet, score);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitError = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    if (_busy) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(),
        SizedBox(height: Space.md),
        Text('Reading your sheet…'),
      ]));
    }
    final scan = _scan;
    if (scan == null) {
      return PageBody(children: [
        if (widget.closesAt != null)
          Text('Upload before ${DateFormat('h:mm a').format(widget.closesAt!)}.', style: t.titleSmall?.copyWith(color: c.primary)),
        const SizedBox(height: Space.sm),
        const ListCard(children: [
          ListTile(leading: Icon(Icons.crop_free), title: Text('All four black corner squares in the photo')),
          ListTile(leading: Icon(Icons.wb_sunny_outlined), title: Text('Good light, no shadow across the sheet')),
          ListTile(leading: Icon(Icons.table_restaurant_outlined), title: Text('Sheet flat on a table, phone held straight above')),
        ]),
        if (_problem != null) ...[
          const SizedBox(height: Space.lg),
          Card(
            color: c.errorContainer,
            child: ListTile(
              leading: Icon(Icons.error_outline, color: c.onErrorContainer),
              title: Text(_problem!, style: TextStyle(color: c.onErrorContainer)),
            ),
          ),
        ],
        const SizedBox(height: Space.xl),
        FilledButton.icon(
          onPressed: () => _take(ImageSource.camera),
          icon: const Icon(Icons.photo_camera),
          label: Text(_problem == null ? 'Take photo of my sheet' : 'Take another photo'),
        ),
        const SizedBox(height: Space.sm),
        OutlinedButton.icon(
          onPressed: () => _take(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose a photo'),
        ),
      ]);
    }

    final sheet = _sheet;
    final numbers = [for (final i in widget.paper) i.number];
    final answered = numbers.where((n) => (sheet[n] ?? -2) >= 0).length;
    final blank = numbers.where((n) => sheet[n] == null).length;
    final toCheck = scan.flags.keys.where((n) => !_fixed.containsKey(n) && numbers.contains(n)).length;
    final setMismatch = scan.setLabel != null && scan.setLabel != widget.set;

    return Column(children: [
      Expanded(
        child: PageBody(children: [
          Text('Check what was read', style: t.titleLarge),
          const SizedBox(height: Space.xs),
          Text('$answered answered · $blank blank · ${toCheck == 0 ? 'nothing to check' : '$toCheck to check'}',
              style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
          if (setMismatch) ...[
            const SizedBox(height: Space.sm),
            Card(
              color: c.tertiaryContainer,
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text('Your sheet is marked ${scan.setLabel}, but your paper was Set ${widget.set}. '
                    'Your answers are marked against Set ${widget.set}.'),
              ),
            ),
          ],
          if (toCheck > 0) ...[
            const SizedBox(height: Space.sm),
            Text('Tap the amber ones and choose what you marked. Only those can be changed.', style: t.bodySmall),
          ],
          const SizedBox(height: Space.md),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final n in numbers) _AnswerTile(
              number: n,
              value: sheet[n],
              flag: _fixed.containsKey(n) ? null : scan.flags[n],
              fixed: _fixed.containsKey(n),
              onTap: scan.flags.containsKey(n) ? () => _choose(n) : null,
            ),
          ]),
          if (_submitError != null) ...[
            const SizedBox(height: Space.md),
            Text(_submitError!, style: t.bodyMedium?.copyWith(color: c.error)),
          ],
        ]),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting ? null : () => setState(() => _scan = null),
                child: const Text('Retake photo'),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: FilledButton(
                onPressed: _submitting || toCheck > 0 ? null : _submit,
                child: Text(_submitting ? 'Submitting…' : toCheck > 0 ? 'Check $toCheck first' : 'Submit answers'),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Future<void> _choose(int n) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Question $n: what did you mark?', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: Space.sm),
            Text('Look at your sheet and choose exactly what is darkened.', style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: Space.lg),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
              for (var k = 0; k < 4; k++)
                ChoiceChip(label: Text(String.fromCharCode(65 + k)), selected: false, onSelected: (_) => Navigator.pop(ctx, k)),
              ChoiceChip(label: const Text('Left blank'), selected: false, onSelected: (_) => Navigator.pop(ctx, -9)),
              ChoiceChip(label: const Text('Two marked'), selected: false, onSelected: (_) => Navigator.pop(ctx, -1)),
            ]),
          ]),
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _fixed[n] = picked == -9 ? null : picked);
  }
}

class _AnswerTile extends StatelessWidget {
  const _AnswerTile({required this.number, required this.value, this.flag, this.fixed = false, this.onTap});

  final int number;
  final int? value;
  final String? flag;
  final bool fixed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final label = value == null ? '–' : value == -1 ? '2×' : String.fromCharCode(65 + value!);
    final bg = flag != null
        ? context.status.warning.withValues(alpha: 0.25)
        : value == -1
            ? c.errorContainer
            : value == null
                ? c.surfaceContainerHighest
                : c.surfaceContainerHigh;
    return Semantics(
      button: onTap != null,
      label: 'Question $number, ${value == null ? 'blank' : label}${flag != null ? ', check this' : ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 50,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: flag != null ? Border.all(color: context.status.warning, width: 1.5) : (fixed ? Border.all(color: c.primary) : null),
          ),
          child: Column(children: [
            Text('$number', style: t.labelSmall?.copyWith(color: c.onSurfaceVariant)),
            Text(label, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

/// Right after submitting: score, each paper's pass/fail and where marks went.
class _ResultView extends StatelessWidget {
  const _ResultView({required this.test, required this.paper, required this.sheet, required this.score});

  final TestDefinition test;
  final List<PaperItem> paper;
  final Map<int, int?> sheet;
  final double score;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final papers = paperResultsFor(test, paper, sheet);
    final lost = marksLostBySubject(paper, sheet, test.marking).where((e) => e.$2 > 0).take(5).toList();
    final max = paper.length * test.marking.correct;
    final passedAll = papers.every((p) => p.passed);
    return PageBody(children: [
      Text('${fmtScore(score)} / ${fmtScore(max)}', style: t.displaySmall),
      Text(passedAll ? 'You would pass every paper.' : 'You would not pass every paper yet.',
          style: t.titleSmall?.copyWith(color: passedAll ? context.status.success : c.error)),
      const SectionHeader('Each paper (33% to pass)'),
      ListCard(children: [
        for (final p in papers)
          ListTile(
            leading: Icon(p.passed ? Icons.check_circle : Icons.cancel, color: p.passed ? context.status.success : c.error),
            title: Text(p.paper.shortTitle),
            subtitle: LinearProgressIndicator(value: (p.percent / 100).clamp(0, 1)),
            trailing: Text('${fmtScore(p.score)} / ${fmtScore(p.max)}', style: t.titleSmall),
          ),
      ]),
      if (lost.isNotEmpty) ...[
        const SectionHeader('Where you lost the most marks'),
        ListCard(children: [
          for (final (subject, l, possible) in lost)
            ListTile(
              title: Text(subject),
              subtitle: Text('Lost ${fmtScore(l)} of ${fmtScore(possible)} marks'),
              trailing: Text('${((possible - l) / possible * 100).clamp(0, 100).round()}%', style: t.titleSmall),
            ),
        ]),
      ],
      const SizedBox(height: Space.md),
      Text('The answer key opens when the exam closes, so it can\'t be passed around.', style: t.bodySmall),
      const SizedBox(height: Space.lg),
      FilledButton(onPressed: () => context.pop(), child: const Text('Done')),
    ]);
  }
}
