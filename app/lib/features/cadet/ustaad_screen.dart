import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';

class _Message {
  const _Message(this.text, {required this.fromCadet});
  final String text;
  final bool fromCadet;
}

/// Ustaad, the study assistant. In Phase 0 it is only the chat surface: it
/// says plainly that it is not connected yet rather than inventing answers.
/// Phase 1 wires it to the RAG service over the unit's knowledge base.
class UstaadScreen extends StatefulWidget {
  const UstaadScreen({super.key});

  @override
  State<UstaadScreen> createState() => _UstaadScreenState();
}

class _UstaadScreenState extends State<UstaadScreen> {
  final _input = TextEditingController();
  final _messages = <_Message>[];

  static const _suggestions = [
    'Explain the 8-figure grid reference',
    'What is the B Certificate exam pattern?',
    'Make me a 7-day revision plan for Map Reading',
  ];

  static const _notConnected =
      "I'm not connected to your unit's study material yet. Once your ANO uploads the precis, "
      "I'll answer from it and show you the page each answer comes from.";

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _messages
        ..add(_Message(trimmed, fromCadet: true))
        ..add(const _Message(_notConnected, fromCadet: false));
    });
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;

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
                      Text('Answers come only from material your unit has approved, with the source shown.',
                          style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant), textAlign: TextAlign.center),
                      const SizedBox(height: Space.xl),
                      for (final s in _suggestions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: OutlinedButton(onPressed: () => _send(s), child: Text(s)),
                        ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(Space.lg),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => _Bubble(_messages[i]),
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
                      decoration: const InputDecoration(labelText: 'Ask a question'),
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

class _Bubble extends StatelessWidget {
  const _Bubble(this.message);

  final _Message message;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final mine = message.fromCadet;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.sm),
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: mine ? c.primary : c.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Text(message.text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: mine ? c.onPrimary : c.onSurface)),
      ),
    );
  }
}
