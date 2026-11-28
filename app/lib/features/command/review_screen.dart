import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../data/demo/demo_data.dart';
import '../../data/models/test.dart';
import '../../data/providers.dart';
import '../../data/unit_repository.dart';
import '../shared/widgets.dart';

/// The ANO (or a senior cadet) sets the correct answer for précis questions,
/// one at a time. Approved questions join the unit's practice bank.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  List<ReviewItem>? _queue;
  String? _error;
  int? _choice;
  bool _busy = false;
  int _approved = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(unitRepositoryProvider);
    setState(() {
      _error = null;
      _queue = null;
    });
    if (repo == null) {
      // Sample mode: a few starter questions with their answers hidden.
      setState(() => _queue = [
            for (final q in DemoData.questions.take(3))
              ReviewItem(id: q.id, prompt: q.prompt, options: q.options, source: 'Sample · ${q.subject}'),
          ]);
      return;
    }
    try {
      final items = await repo.reviewQueue();
      if (mounted) setState(() => _queue = items);
    } catch (e) {
      if (mounted) setState(() => _error = e is UnitDataFailure ? e.message : "Couldn't load the questions.");
    }
  }

  Future<void> _approve(ReviewItem item) async {
    final choice = _choice;
    if (choice == null) return;
    final repo = ref.read(unitRepositoryProvider);
    setState(() => _busy = true);
    try {
      await repo?.approveQuestion(item.id, choice);
      if (!mounted) return;
      setState(() {
        _queue!.remove(item);
        _choice = null;
        _approved++;
      });
      await ref.read(questionBankProvider.notifier).reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e is UnitDataFailure ? e.message : "Couldn't approve. Try again.")));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _skip(ReviewItem item) => setState(() {
        _queue!
          ..remove(item)
          ..add(item);
        _choice = null;
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final queue = _queue;

    Widget body;
    if (_error != null) {
      body = PageBody(children: [
        EmptyState(
          icon: Icons.cloud_off_outlined,
          title: "Couldn't load questions",
          message: _error!,
          action: FilledButton(onPressed: _load, child: const Text('Try again')),
        ),
      ]);
    } else if (queue == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (queue.isEmpty) {
      body = PageBody(children: [
        EmptyState(
          icon: Icons.task_alt,
          title: _approved > 0 ? 'All caught up' : 'Nothing to review',
          message: _approved > 0
              ? 'You approved $_approved question${_approved == 1 ? '' : 's'}. They are now in your unit\'s practice bank.'
              : 'Précis questions waiting for an answer will appear here.',
        ),
      ]);
    } else {
      final item = queue.first;
      body = PageBody(children: [
        Row(children: [
          Expanded(
            child: Text('${queue.length} to review${_approved > 0 ? ' · $_approved approved' : ''}',
                style: t.labelLarge?.copyWith(color: c.onSurfaceVariant)),
          ),
          if (!ref.watch(isLiveProvider)) const DemoBadge(),
        ]),
        const SizedBox(height: Space.md),
        Text([item.source, if (item.page != null) 'p. ${item.page}'].join(' · '),
            style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
        const SizedBox(height: Space.sm),
        Text(item.prompt, style: t.titleLarge),
        const SizedBox(height: Space.md),
        Text('Pick the correct answer', style: t.labelLarge),
        const SizedBox(height: Space.sm),
        RadioGroup<int>(
          groupValue: _choice,
          onChanged: (v) => setState(() => _choice = v),
          child: Column(children: [
            for (var i = 0; i < item.options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Card(child: RadioListTile<int>(value: i, title: Text(item.options[i]))),
              ),
          ]),
        ),
        const SizedBox(height: Space.md),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _skip(item), child: const Text('Skip for now'))),
          const SizedBox(width: Space.md),
          Expanded(
            child: FilledButton(
              onPressed: _busy || _choice == null ? null : () => _approve(item),
              child: const Text('Approve answer'),
            ),
          ),
        ]),
        const SizedBox(height: Space.md),
        Text('Check the answer against the précis page before approving: cadets will be marked on it.',
            style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
      ]);
    }

    return Scaffold(appBar: AppBar(title: const Text('Review précis questions')), body: body);
  }
}
