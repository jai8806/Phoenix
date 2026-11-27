import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/figure.dart';
import '../../data/models/ustaad.dart';
import '../../data/providers.dart';
import '../../data/unit_repository.dart';
import '../../domain/precis_search.dart';
import '../shared/figures.dart';

class _Message {
  const _Message(this.text,
      {required this.fromCadet, this.question, this.precis, this.sources = const [], this.isError = false, this.isAi = false});
  final String text;
  final bool fromCadet;

  /// The question this reply answers (for "Explain simply").
  final String? question;

  /// Lines taken straight from the précis.
  final PrecisAnswer? precis;
  final List<UstaadSource> sources;
  final bool isError;
  final bool isAi;
}

/// Ustaad, the study assistant. It answers from the précis saved on the phone:
/// instantly, offline and without any AI, quoting the book with chapter and
/// page. "Explain simply" asks the AI for a plainer explanation when wanted.
class UstaadScreen extends ConsumerStatefulWidget {
  const UstaadScreen({super.key});

  @override
  ConsumerState<UstaadScreen> createState() => _UstaadScreenState();
}

class _UstaadScreenState extends ConsumerState<UstaadScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Message>[];
  bool _thinking = false;

  static const _suggestions = [
    'What are the types of north?',
    'What is the motto of NCC?',
    'First aid for snake bite',
  ];

  static const _sampleMode =
      "I'm not connected in sample mode. Sign in with your unit account and I'll answer from your "
      'précis, showing the chapter and page each answer comes from.';

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });

  void _send(String text) {
    final question = text.trim();
    if (question.isEmpty || _thinking) return;
    _input.clear();
    final precis = ref.read(precisProvider);
    setState(() {
      _messages.add(_Message(question, fromCadet: true));
      switch (precis.status) {
        case PrecisStatus.sample:
          _messages.add(const _Message(_sampleMode, fromCadet: false));
        case PrecisStatus.loading:
          _messages.add(const _Message(
              'Still downloading your précis for offline use. Try again in a few seconds.',
              fromCadet: false));
        case PrecisStatus.error:
          _messages.add(_Message(precis.error ?? "Couldn't load the study material.", fromCadet: false, isError: true));
        case PrecisStatus.ready:
          final answer = precis.search!.answer(question);
          _messages.add(answer.found
              ? _Message('', fromCadet: false, question: question, precis: answer)
              : const _Message(
                  "That isn't in your précis. Try the words the book uses, e.g. \"types of north\" or "
                  '"judging distance".',
                  fromCadet: false));
      }
    });
    _toBottom();
  }

  Future<void> _explain(String question) async {
    final repo = ref.read(unitRepositoryProvider);
    if (repo == null || _thinking) return;
    setState(() => _thinking = true);
    _toBottom();
    try {
      final reply = await repo.askUstaad(question);
      if (!mounted) return;
      setState(() => _messages.add(_Message(reply.answer, fromCadet: false, sources: reply.sources, isAi: true)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(_Message(
            e is UnitDataFailure ? e.message : "Couldn't explain just now. The précis lines above are still correct.",
            fromCadet: false,
            isError: true,
          )));
    } finally {
      if (mounted) setState(() => _thinking = false);
      _toBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final precis = ref.watch(precisProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ustaad'),
        actions: [
          if (precis.status == PrecisStatus.ready)
            Padding(
              padding: const EdgeInsets.only(right: Space.lg),
              child: Tooltip(
                message: '${precis.passageCount} précis passages saved on this phone',
                child: Row(children: [
                  Icon(precis.refreshing ? Icons.sync : Icons.offline_pin_outlined, size: 18, color: c.primary),
                  const SizedBox(width: Space.xs),
                  Text('Offline ready', style: t.labelMedium?.copyWith(color: c.primary)),
                ]),
              ),
            ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(children: [
            if (precis.status == PrecisStatus.loading) const LinearProgressIndicator(),
            Expanded(
              child: _messages.isEmpty
                  ? ListView(padding: const EdgeInsets.all(Space.xl), children: [
                      const SizedBox(height: Space.xl),
                      Icon(Icons.menu_book_outlined, size: 40, color: c.primary),
                      const SizedBox(height: Space.md),
                      Text('Ask anything from your précis', style: t.titleLarge, textAlign: TextAlign.center),
                      const SizedBox(height: Space.sm),
                      Text(
                        switch (precis.status) {
                          PrecisStatus.sample => 'Sample mode: sign in with your unit account to get real answers.',
                          PrecisStatus.loading => 'Saving your précis on this phone so Ustaad works offline…',
                          PrecisStatus.error => precis.error ?? "Couldn't load the study material.",
                          PrecisStatus.ready =>
                            'Answers come straight from the book, with chapter and page. Works offline.',
                        },
                        style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      if (precis.status == PrecisStatus.error) ...[
                        const SizedBox(height: Space.md),
                        Center(
                          child: FilledButton(
                            onPressed: () => ref.read(precisProvider.notifier).refresh(),
                            child: const Text('Try again'),
                          ),
                        ),
                      ],
                      const SizedBox(height: Space.xl),
                      for (final s in _suggestions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: OutlinedButton(onPressed: () => _send(s), child: Text(s)),
                        ),
                    ])
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(Space.lg),
                      itemCount: _messages.length + (_thinking ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == _messages.length) return const _Thinking();
                        final m = _messages[i];
                        if (m.precis != null) {
                          final top = m.precis!.passages.first;
                          return _PrecisBubble(
                            answer: m.precis!,
                            figures: precis.figuresFor(top.heading.split(' · ').first, book: top.title,
                                fromPage: top.page, toPage: top.pageEnd ?? top.page),
                            onExplain: ref.watch(isLiveProvider) && !_thinking ? () => _explain(m.question!) : null,
                          );
                        }
                        return _Bubble(m);
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      maxLength: 500,
                      decoration: const InputDecoration(labelText: 'Ask a question', counterText: ''),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: () => _send(_input.text),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Lines quoted from the précis, the full passage on demand, and "Explain simply".
class _PrecisBubble extends StatefulWidget {
  const _PrecisBubble({required this.answer, required this.onExplain, this.figures = const []});

  final PrecisAnswer answer;
  final List<PrecisFigure> figures;
  final VoidCallback? onExplain;

  @override
  State<_PrecisBubble> createState() => _PrecisBubbleState();
}

class _PrecisBubbleState extends State<_PrecisBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final top = widget.answer.passages.first;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.sm),
        padding: const EdgeInsets.all(Space.lg),
        constraints: const BoxConstraints(maxWidth: 600),
        decoration: BoxDecoration(
          color: c.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border(left: BorderSide(color: c.primary, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.menu_book_outlined, size: 16, color: c.primary),
            const SizedBox(width: Space.xs),
            Text('FROM YOUR PRÉCIS', style: t.labelSmall?.copyWith(color: c.primary, letterSpacing: 1.1)),
          ]),
          const SizedBox(height: Space.sm),
          for (final s in widget.answer.snippets) ...[
            SelectableText(s.text, style: t.bodyMedium),
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: Space.sm),
              child: Text(s.passage.citation, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            ),
          ],
          if (widget.figures.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            FigureStrip(figures: widget.figures.take(4).toList(), height: 96),
            const SizedBox(height: Space.sm),
          ],
          if (_expanded) ...[
            const Divider(),
            const SizedBox(height: Space.sm),
            Text(top.heading, style: t.labelLarge),
            const SizedBox(height: Space.xs),
            SelectableText(top.content, style: t.bodyMedium),
            const SizedBox(height: Space.xs),
            Text(top.citation, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
          ],
          Wrap(spacing: Space.sm, children: [
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.article_outlined, size: 18),
              label: Text(_expanded ? 'Hide passage' : 'Read full passage'),
            ),
            if (widget.onExplain != null)
              TextButton.icon(
                onPressed: widget.onExplain,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Explain simply'),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.sm),
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
        decoration: BoxDecoration(color: c.surfaceContainerHigh, borderRadius: BorderRadius.circular(Radii.lg)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: Space.sm),
          Text('Writing a simpler explanation…', style: Theme.of(context).textTheme.bodyMedium),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.message);

  final _Message message;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final mine = message.fromCadet;
    final fg = mine ? c.onPrimary : (message.isError ? c.onErrorContainer : c.onSurface);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.sm),
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: mine ? c.primary : (message.isError ? c.errorContainer : c.surfaceContainerHigh),
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (message.isAi) ...[
            Row(children: [
              Icon(Icons.auto_awesome, size: 14, color: c.onSurfaceVariant),
              const SizedBox(width: Space.xs),
              Text('AI EXPLANATION', style: t.labelSmall?.copyWith(color: c.onSurfaceVariant, letterSpacing: 1.1)),
            ]),
            const SizedBox(height: Space.xs),
          ],
          SelectableText(message.text, style: t.bodyMedium?.copyWith(color: fg)),
          if (message.sources.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Text('SOURCES', style: t.labelSmall?.copyWith(color: c.onSurfaceVariant, letterSpacing: 1.1)),
            const SizedBox(height: Space.xs),
            for (final s in message.sources)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('[${s.n}] ${s.label}', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              ),
          ],
        ]),
      ),
    );
  }
}
