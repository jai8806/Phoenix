import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/ustaad.dart';
import '../../data/providers.dart';
import '../../data/unit_repository.dart';

class _Message {
  const _Message(this.text, {required this.fromCadet, this.sources = const [], this.isError = false});
  final String text;
  final bool fromCadet;
  final List<UstaadSource> sources;
  final bool isError;
}

/// Ustaad, the study assistant. Live members get answers built only from their
/// unit's précis, with the passages it used. In sample mode it says plainly
/// that it isn't connected rather than inventing answers.
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
    'Explain the 8-figure grid reference',
    'What does the NDRF do?',
  ];

  static const _notConnected =
      "I'm not connected in sample mode. Sign in with your unit account and I'll answer from your "
      "précis, showing the page each answer comes from.";

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

  Future<void> _send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _thinking) return;
    _input.clear();
    final repo = ref.read(unitRepositoryProvider);
    setState(() {
      _messages.add(_Message(question, fromCadet: true));
      if (repo == null) _messages.add(const _Message(_notConnected, fromCadet: false));
      _thinking = repo != null;
    });
    _toBottom();
    if (repo == null) return;
    try {
      final reply = await repo.askUstaad(question);
      if (!mounted) return;
      setState(() => _messages.add(_Message(reply.answer, fromCadet: false, sources: reply.sources)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(_Message(
            e is UnitDataFailure ? e.message : "Ustaad couldn't answer just now. Try again in a moment.",
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
    final live = ref.watch(isLiveProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ustaad')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(children: [
            Expanded(
              child: _messages.isEmpty
                  ? ListView(padding: const EdgeInsets.all(Space.xl), children: [
                      const SizedBox(height: Space.xl),
                      Icon(Icons.auto_awesome, size: 40, color: c.primary),
                      const SizedBox(height: Space.md),
                      Text('Ask Ustaad anything from your syllabus', style: t.titleLarge, textAlign: TextAlign.center),
                      const SizedBox(height: Space.sm),
                      Text(
                        live
                            ? 'Answers come only from your précis, with the chapter and page shown.'
                            : 'Sample mode: sign in with your unit account to get real answers.',
                        style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
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
                      itemBuilder: (_, i) => i == _messages.length ? const _Thinking() : _Bubble(_messages[i]),
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
                    onPressed: _thinking ? null : () => _send(_input.text),
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
          Text('Reading the précis…', style: Theme.of(context).textTheme.bodyMedium),
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
