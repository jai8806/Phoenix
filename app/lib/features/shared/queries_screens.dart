import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/queries.dart';
import '../../data/providers.dart';
import '../../data/unit_repository.dart';
import 'widgets.dart';

String _when(DateTime d, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (!d.isBefore(today)) return DateFormat('h:mm a').format(d);
  if (!d.isBefore(today.subtract(const Duration(days: 6)))) return DateFormat('EEE').format(d);
  return DateFormat('d MMM').format(d);
}

Color _statusColor(BuildContext context, QueryStatus s) => switch (s) {
      QueryStatus.open => context.status.warning,
      QueryStatus.answered => context.status.success,
      QueryStatus.escalated => Theme.of(context).colorScheme.tertiary,
      QueryStatus.closed => Theme.of(context).colorScheme.onSurfaceVariant,
    };

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);

  final QueryStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Radii.sm)),
      child: Text(status.label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

/// How anonymity works, in plain words.
class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: c.onPrimaryContainer),
            const SizedBox(width: Space.sm),
            Expanded(child: Text(text, style: t.bodySmall?.copyWith(color: c.onPrimaryContainer))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(Radii.lg)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.shield_outlined, color: c.onPrimaryContainer),
          const SizedBox(width: Space.sm),
          Expanded(child: Text('Ask without giving your name', style: t.titleMedium?.copyWith(color: c.onPrimaryContainer))),
        ]),
        point(Icons.person_off_outlined, 'Phoenix does not save who wrote it. Not your name, not your account.'),
        point(Icons.visibility_outlined, 'Only the CSUO and SUO read it. You can also let the JUO, CSM and CQMS help.'),
        point(Icons.block, 'The ANO cannot see it. If it is serious, the seniors take it to the ANO in person, without your name.'),
        point(Icons.key_outlined, 'Replies come back to this phone through a private ticket code. Note it down to read them on another phone.'),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Asker: my queries
// ---------------------------------------------------------------------------

class AskSeniorsScreen extends ConsumerWidget {
  const AskSeniorsScreen({super.key});

  Future<void> _addTicket(BuildContext context, WidgetRef ref) async {
    final ctl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open a ticket'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Ticket code', hintText: 'ABCD-EFGH-…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, parseTicket(ctl.text)), child: const Text('Open')),
        ],
      ),
    );
    ctl.dispose();
    if (code == null) return;
    await ref.read(queryTicketsProvider.notifier).add(code);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(isLiveProvider);
    final queries = ref.watch(myQueriesProvider);
    final now = ref.watch(clockProvider)();
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask a senior'),
        actions: [
          IconButton(
            tooltip: 'Open a ticket from its code',
            icon: const Icon(Icons.key_outlined),
            onPressed: live ? () => _addTicket(context, ref) : null,
          ),
        ],
      ),
      floatingActionButton: live
          ? FloatingActionButton.extended(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => const NewQuerySheet(),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('New query'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myQueriesProvider.future),
        child: PageBody(children: [
          const _PrivacyCard(),
          const SectionHeader('Your queries'),
          if (!live)
            const EmptyState(icon: Icons.lock_outline, title: 'Sign in to ask', message: 'Anonymous queries need your unit account.')
          else
            queries.when(
              loading: () => const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => EmptyState(
                icon: Icons.cloud_off,
                title: "Couldn't load your queries",
                message: '$e',
                action: FilledButton(onPressed: () => ref.invalidate(myQueriesProvider), child: const Text('Try again')),
              ),
              data: (list) => list.isEmpty
                  ? const EmptyState(
                      icon: Icons.forum_outlined,
                      title: 'Nothing asked yet',
                      message: 'Problems at camp, with seniors, studies, health… ask here and a senior will reply.')
                  : ListCard(children: [
                      for (final q in list)
                        ListTile(
                          leading: Icon(q.hasReply ? Icons.mark_chat_unread_outlined : Icons.chat_bubble_outline),
                          title: Text(q.subject),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(spacing: Space.sm, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              _StatusChip(q.status),
                              Text(q.category.label, style: t.bodySmall),
                            ]),
                          ),
                          trailing: Text(_when(q.updatedAt, now), style: t.bodySmall),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => QueryThreadScreen(queryId: q.id, asker: true),
                          )),
                        ),
                    ]),
            ),
          const SizedBox(height: 80),
        ]),
      ),
    );
  }
}

class NewQuerySheet extends ConsumerStatefulWidget {
  const NewQuerySheet({super.key});

  @override
  ConsumerState<NewQuerySheet> createState() => _NewQuerySheetState();
}

class _NewQuerySheetState extends ConsumerState<NewQuerySheet> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  QueryCategory _category = QueryCategory.personal;
  bool _allSeniors = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final subject = _subject.text.trim();
    final body = _body.text.trim();
    if (subject.length < 3) return setState(() => _error = 'Give it a short title.');
    if (body.length < 5) return setState(() => _error = 'Write a little more so the seniors can help.');
    final repo = ref.read(unitRepositoryProvider);
    if (repo == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final code = newTicketCode();
    try {
      await repo.askQuery(code, subject: subject, body: body, category: _category, toAllSeniors: _allSeniors);
      await ref.read(queryTicketsProvider.notifier).add(code);
      if (!mounted) return;
      final nav = Navigator.of(context);
      nav.pop();
      await showDialog<void>(context: nav.context, builder: (_) => _TicketDialog(code: code));
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e is UnitDataFailure ? e.message : "Couldn't send it. Try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('New anonymous query', style: t.titleLarge),
          const SizedBox(height: Space.xs),
          Text('Your name is not attached. Avoid details that give you away if you want to stay anonymous.', style: t.bodySmall),
          const SizedBox(height: Space.md),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            for (final cat in QueryCategory.values)
              ChoiceChip(label: Text(cat.label), selected: _category == cat, onSelected: (_) => setState(() => _category = cat)),
          ]),
          const SizedBox(height: Space.md),
          TextField(
            controller: _subject,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Problem with a senior at camp'),
          ),
          TextField(
            controller: _body,
            minLines: 4,
            maxLines: 10,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'What happened / what do you need?', alignLabelWithHint: true),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _allSeniors,
            onChanged: (v) => setState(() => _allSeniors = v),
            title: const Text('Also let the JUO, CSM and CQMS help'),
            subtitle: Text(_allSeniors ? 'CSUO, SUO, JUO, CSM and CQMS can read it.' : 'Only the CSUO and SUO can read it.'),
          ),
          Text('The ANO never sees anonymous queries.', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
          if (_error != null) ...[
            const SizedBox(height: Space.sm),
            Text(_error!, style: t.bodySmall?.copyWith(color: c.error)),
          ],
          const SizedBox(height: Space.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
              label: Text(_sending ? 'Sending…' : 'Send anonymously'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TicketDialog extends StatelessWidget {
  const _TicketDialog({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      icon: const Icon(Icons.check_circle_outline),
      title: const Text('Sent anonymously'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Replies will appear here on this phone. Your private ticket code:'),
        const SizedBox(height: Space.md),
        SelectableText(formatTicket(code), style: t.titleMedium?.copyWith(fontFamily: 'monospace', letterSpacing: 1)),
        const SizedBox(height: Space.md),
        const Text('Write it down if you might change phones or sign out: signing out removes your tickets from this phone, '
            'and nobody (not even the seniors) can look it up for you.'),
      ]),
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: formatTicket(code))),
          child: const Text('Copy code'),
        ),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Thread (both sides)
// ---------------------------------------------------------------------------

class QueryThreadScreen extends ConsumerStatefulWidget {
  const QueryThreadScreen({super.key, required this.queryId, required this.asker});

  final String queryId;

  /// The person who asked (replies with their ticket), not a senior.
  final bool asker;

  @override
  ConsumerState<QueryThreadScreen> createState() => _QueryThreadScreenState();
}

class _QueryThreadScreenState extends ConsumerState<QueryThreadScreen> {
  final _reply = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(widget.asker ? myQueriesProvider : queryInboxProvider);

  Future<void> _send(AnonQuery q) async {
    final body = _reply.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(unitRepositoryProvider)?.replyToQuery(q.id, body, token: widget.asker ? q.token : null);
      _reply.clear();
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _status(AnonQuery q, QueryStatus s) async {
    if (s == QueryStatus.escalated) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Raise with the ANO?'),
          content: const Text('Phoenix does not send it to the ANO: you speak to the ANO in person. '
              'Marking it tells the cadet that it has been taken up. Do not reveal anything that could identify them.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark as raised')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ref.read(unitRepositoryProvider)?.setQueryStatus(q.id, s, token: widget.asker ? q.token : null);
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(widget.asker ? myQueriesProvider : queryInboxProvider);
    final q = async.value?.where((x) => x.id == widget.queryId).firstOrNull;
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final now = ref.watch(clockProvider)();
    if (q == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const EmptyState(icon: Icons.search_off, title: 'Query not found', message: 'It may have been removed.'),
      );
    }
    final closed = q.status == QueryStatus.closed;
    return Scaffold(
      appBar: AppBar(
        title: Text(q.subject, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<QueryStatus>(
            tooltip: 'Status',
            onSelected: (s) => _status(q, s),
            itemBuilder: (_) => widget.asker
                ? [if (!closed) const PopupMenuItem(value: QueryStatus.closed, child: Text('Close: my problem is solved'))]
                : [
                    if (q.status != QueryStatus.escalated)
                      const PopupMenuItem(value: QueryStatus.escalated, child: Text('Mark as raised with the ANO')),
                    if (!closed) const PopupMenuItem(value: QueryStatus.closed, child: Text('Close')),
                    if (closed) const PopupMenuItem(value: QueryStatus.open, child: Text('Reopen')),
                  ],
          ),
        ],
      ),
      body: Column(children: [
        Material(
          color: c.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
            child: Row(children: [
              _StatusChip(q.status),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  [q.category.label, q.toAllSeniors ? 'CSUO, SUO, JUO, CSM, CQMS' : 'CSUO and SUO only'].join(' · '),
                  style: t.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(Space.lg), children: [
            if (!widget.asker)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: Text('Anonymous: no one, including you, can see who asked. Reply as you would to any cadet.',
                    style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              ),
            for (final m in q.messages)
              Align(
                alignment: m.fromSenior == widget.asker ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  margin: const EdgeInsets.only(bottom: Space.sm),
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(
                    color: m.fromSenior ? c.secondaryContainer : c.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      m.fromSenior ? (m.seniorLabel ?? 'Senior') : (widget.asker ? 'You' : 'Cadet (anonymous)'),
                      style: t.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    SelectableText(m.body, style: t.bodyMedium),
                    const SizedBox(height: 2),
                    Text(_when(m.createdAt, now), style: t.labelSmall?.copyWith(color: c.onSurfaceVariant)),
                  ]),
                ),
              ),
            if (q.status == QueryStatus.escalated)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  widget.asker
                      ? 'The seniors have taken this up with the ANO, without your name.'
                      : 'Marked as raised with the ANO.',
                  style: t.bodySmall?.copyWith(color: c.tertiary),
                ),
              ),
          ]),
        ),
        if (!closed)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.sm, Space.sm),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _reply,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(hintText: widget.asker ? 'Add more…' : 'Reply to the cadet…'),
                  ),
                ),
                IconButton(
                  tooltip: 'Send',
                  icon: const Icon(Icons.send),
                  onPressed: _sending ? null : () => _send(q),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Seniors: inbox
// ---------------------------------------------------------------------------

class QueryInboxScreen extends ConsumerStatefulWidget {
  const QueryInboxScreen({super.key});

  @override
  ConsumerState<QueryInboxScreen> createState() => _QueryInboxScreenState();
}

class _QueryInboxScreenState extends ConsumerState<QueryInboxScreen> {
  bool _showClosed = false;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider);
    final async = ref.watch(queryInboxProvider);
    final now = ref.watch(clockProvider)();
    final t = Theme.of(context).textTheme;
    if (me == null || !me.canHandleQueries(toAllSeniors: true)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Anonymous queries')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Only senior cadets with an appointment',
          message: 'Anonymous queries are read by the CSUO and SUO (and JUO, CSM, CQMS when the cadet allows). The ANO does not see them.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Anonymous queries')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(queryInboxProvider.future),
        child: PageBody(children: [
          Text(
            me.appointment!.isCommand
                ? 'Cadets ask here without their names. You see every query in the unit; the ANO does not. '
                    'If one is serious, speak to the ANO in person and mark it as raised.'
                : 'You see the queries cadets opened to the JUO, CSM and CQMS. The CSUO / SUO see all of them.',
            style: t.bodySmall,
          ),
          const SizedBox(height: Space.md),
          async.when(
            loading: () => const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => EmptyState(
              icon: Icons.cloud_off,
              title: "Couldn't load the queries",
              message: '$e',
              action: FilledButton(onPressed: () => ref.invalidate(queryInboxProvider), child: const Text('Try again')),
            ),
            data: (all) {
              final active = [for (final q in all) if (q.status != QueryStatus.closed) q]
                ..sort((a, b) => a.awaitingSenior != b.awaitingSenior ? (a.awaitingSenior ? -1 : 1) : b.updatedAt.compareTo(a.updatedAt));
              final closed = [for (final q in all) if (q.status == QueryStatus.closed) q];
              final waiting = active.where((q) => q.awaitingSenior).length;
              Widget tile(AnonQuery q) => ListTile(
                    leading: Icon(q.awaitingSenior ? Icons.mark_chat_unread : Icons.chat_bubble_outline,
                        color: q.awaitingSenior ? context.status.warning : null),
                    title: Text(q.subject),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(spacing: Space.sm, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        _StatusChip(q.status),
                        Text(q.category.label, style: t.bodySmall),
                        if (q.awaitingSenior) Text('needs a reply', style: t.bodySmall?.copyWith(color: context.status.warning)),
                      ]),
                    ),
                    trailing: Text(_when(q.updatedAt, now), style: t.bodySmall),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => QueryThreadScreen(queryId: q.id, asker: false),
                    )),
                  );
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TileGrid(minTileWidth: 150, children: [
                  StatTile(label: 'Need a reply', value: '$waiting', icon: Icons.mark_chat_unread_outlined),
                  StatTile(label: 'Open', value: '${active.length}', icon: Icons.forum_outlined),
                  StatTile(label: 'Raised with ANO', value: '${all.where((q) => q.status == QueryStatus.escalated).length}', icon: Icons.outbound_outlined),
                ]),
                const SizedBox(height: Space.md),
                if (active.isEmpty)
                  const EmptyState(icon: Icons.inbox_outlined, title: 'No open queries', message: 'New ones appear here.')
                else
                  ListCard(children: [for (final q in active) tile(q)]),
                if (closed.isNotEmpty) ...[
                  const SizedBox(height: Space.md),
                  TextButton(
                    onPressed: () => setState(() => _showClosed = !_showClosed),
                    child: Text(_showClosed ? 'Hide closed' : 'Show closed (${closed.length})'),
                  ),
                  if (_showClosed) ListCard(children: [for (final q in closed) tile(q)]),
                ],
              ]);
            },
          ),
        ]),
      ),
    );
  }
}
