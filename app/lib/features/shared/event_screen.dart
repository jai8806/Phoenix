import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/comms.dart';
import '../../data/providers.dart';
import '../../data/unit_repository.dart';
import '../../domain/roll_call.dart';
import 'widgets.dart';

/// Everyone's replies to one event (admins), reloaded on demand.
final eventResponsesProvider = FutureProvider.autoDispose.family<List<EventResponse>, String>((ref, eventId) async {
  final repo = ref.watch(unitRepositoryProvider);
  if (repo == null) return const [];
  return repo.eventResponses(eventId);
});

/// One event: details, the cadet's reply, and for admins the roll-call.
class EventScreen extends ConsumerWidget {
  const EventScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    CalendarEvent? event;
    for (final e in ref.watch(eventsProvider)) {
      if (e.id == eventId) event = e;
    }
    final user = ref.watch(authControllerProvider);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    if (event == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.event_busy, title: 'Event not found', message: 'It may have been removed.'));
    }
    final e = event;
    final admin = user?.role.canAdminister ?? false;
    final when = e.endsAt == null
        ? DateFormat('EEEE d MMMM, h:mm a').format(e.startsAt)
        : '${DateFormat('d MMM').format(e.startsAt)} – ${DateFormat('d MMM yyyy').format(e.endsAt!)}';

    return Scaffold(
      appBar: AppBar(title: Text(e.kind.label)),
      body: PageBody(children: [
        Text(e.title, style: t.headlineSmall),
        const SizedBox(height: Space.xs),
        Row(children: [
          Icon(Icons.schedule, size: 16, color: c.onSurfaceVariant),
          const SizedBox(width: Space.xs),
          Expanded(child: Text(when, style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant))),
        ]),
        if (e.location != null)
          Row(children: [
            Icon(Icons.place_outlined, size: 16, color: c.onSurfaceVariant),
            const SizedBox(width: Space.xs),
            Expanded(child: Text(e.location!, style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant))),
          ]),
        if (e.details != null && e.details!.trim().isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Card(child: Padding(padding: const EdgeInsets.all(Space.lg), child: SelectableText(e.details!, style: t.bodyLarge))),
        ],
        if (e.needsResponse) ...[
          const SectionHeader('Your reply'),
          ReplyCard(event: e),
          if (admin) ...[
            const SectionHeader('Roll-call'),
            _RollCallPanel(event: e),
          ],
        ],
      ]),
    );
  }
}

/// "I'll be there" / "Can't come" with a reason, and what the cadet replied.
class ReplyCard extends ConsumerStatefulWidget {
  const ReplyCard({super.key, required this.event, this.compact = false});

  final CalendarEvent event;

  /// On the Today screen: the event's name and time on the card itself.
  final bool compact;

  @override
  ConsumerState<ReplyCard> createState() => _ReplyCardState();
}

class _ReplyCardState extends ConsumerState<ReplyCard> {
  bool _busy = false;
  String? _error;

  Future<void> _send(Attendance status, {String? reason}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(myResponsesProvider.notifier).respond(widget.event.id, status, reason: reason);
    } catch (e) {
      if (mounted) setState(() => _error = e is UnitDataFailure ? e.message : "Couldn't send your reply. Try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _absent() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ReasonSheet(),
    );
    if (reason != null) await _send(Attendance.absent, reason: reason);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final e = widget.event;
    final now = ref.watch(clockProvider)();
    final mine = ref.watch(myResponsesProvider).where((r) => r.eventId == e.id).firstOrNull;
    final open = e.repliesOpen(now);
    final closes = DateFormat('EEE d MMM, h:mm a').format(e.repliesCloseAt);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.compact) ...[
            Text(e.title, style: t.titleMedium),
            Text([DateFormat('EEE d MMM, h:mm a').format(e.startsAt), ?e.location].join(' · '),
                style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            const SizedBox(height: Space.md),
          ],
          if (mine != null)
            Row(children: [
              Icon(mine.status == Attendance.coming ? Icons.check_circle : Icons.do_not_disturb_on_outlined,
                  color: mine.status == Attendance.coming ? context.status.success : context.status.warning),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  mine.status == Attendance.coming ? "You're coming" : "You can't come: ${mine.reason ?? ''}",
                  style: t.titleSmall,
                ),
              ),
            ])
          else
            Text(open ? 'Will you be there?' : "You didn't reply.", style: t.titleSmall),
          const SizedBox(height: Space.xs),
          Text(open ? 'Replies close $closes.' : 'Replies closed $closes.', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
          if (open) ...[
            const SizedBox(height: Space.md),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || mine?.status == Attendance.coming ? null : () => _send(Attendance.coming),
                  icon: const Icon(Icons.check),
                  label: const Text("I'll be there"),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _absent,
                  icon: const Icon(Icons.close),
                  label: Text(mine?.status == Attendance.absent ? 'Change reason' : "Can't come"),
                ),
              ),
            ]),
          ],
          if (_error != null) ...[
            const SizedBox(height: Space.sm),
            Text(_error!, style: t.bodySmall?.copyWith(color: c.error)),
          ],
        ]),
      ),
    );
  }
}

class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet();

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  final _reason = TextEditingController();
  String? _error;
  static const _common = ['University exam', 'Unwell', 'Family function', 'Lab / internal assessment', 'Out of station'];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _done() {
    final r = _reason.text.trim();
    if (r.length < 3) return setState(() => _error = 'Write why you need to be absent.');
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Reason for absence', style: t.titleLarge),
        const SizedBox(height: Space.xs),
        Text('Your ANO and senior cadets see this. Take permission before you reply.', style: t.bodySmall),
        const SizedBox(height: Space.md),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          for (final r in _common)
            ActionChip(label: Text(r), onPressed: () => setState(() {
                  _reason.text = r;
                  _error = null;
                })),
        ]),
        const SizedBox(height: Space.md),
        TextField(
          controller: _reason,
          autofocus: true,
          maxLines: 3,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(labelText: 'Reason', errorText: _error),
        ),
        const SizedBox(height: Space.md),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: _done, child: const Text('Send'))),
      ]),
    );
  }
}

/// Counts, reasons, no replies, marking who came, and the summary for the ANO.
class _RollCallPanel extends ConsumerStatefulWidget {
  const _RollCallPanel({required this.event});

  final CalendarEvent event;

  @override
  ConsumerState<_RollCallPanel> createState() => _RollCallPanelState();
}

enum _Tab { coming, absent, noReply }

class _RollCallPanelState extends ConsumerState<_RollCallPanel> {
  _Tab _tab = _Tab.absent;
  bool _marking = false;
  final Map<String, bool> _marks = {}; // changes not yet reloaded

  Future<void> _mark(String cadetId, bool came) async {
    setState(() => _marks[cadetId] = came);
    try {
      await ref.read(unitRepositoryProvider)?.markAttendance(widget.event.id, cadetId, came);
    } catch (e) {
      if (!mounted) return;
      setState(() => _marks.remove(cadetId));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _copy(RollCall rc) async {
    await Clipboard.setData(ClipboardData(text: rollCallSummary(rc, unitName: ref.read(authControllerProvider)?.unitName)));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Summary copied. Paste it in WhatsApp.')));
  }

  Future<void> _pdf(RollCall rc) async {
    final doc = pw.Document();
    final e = rc.event;
    pw.Widget table(String title, List<List<String>> rows, List<String> head) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(height: 12),
          pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.SizedBox(height: 4),
          if (rows.isEmpty) pw.Text('None', style: const pw.TextStyle(fontSize: 10)) else pw.TableHelper.fromTextArray(headers: head, data: rows, cellStyle: const pw.TextStyle(fontSize: 10), headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ]);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (_) => [
        pw.Text(ref.read(authControllerProvider)?.unitName ?? 'NCC unit', style: const pw.TextStyle(fontSize: 10)),
        pw.Text(e.title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text('${DateFormat('EEEE d MMMM yyyy, h:mm a').format(e.startsAt)}${e.location == null ? '' : ' · ${e.location}'}'),
        pw.SizedBox(height: 8),
        pw.Text('Coming: ${rc.coming.length} (refreshments)   Absent with permission: ${rc.absent.length}   No reply: ${rc.noReply.length}'
            '${rc.attended.isEmpty ? '' : '   Present on the day: ${rc.attended.length}'}'),
        table('Absent with permission', [for (final (i, r) in rc.absent.indexed) ['${i + 1}', r.cadetName, r.reason ?? '']], ['#', 'Cadet', 'Reason']),
        table('No reply', [for (final (i, m) in rc.noReply.indexed) ['${i + 1}', m.displayName]], ['#', 'Cadet']),
        table('Coming', [for (final (i, r) in rc.coming.indexed) ['${i + 1}', r.cadetName, if (rc.attended.isNotEmpty) (rc.attended.contains(r.cadetId) ? 'Present' : 'Not present')]],
            ['#', 'Cadet', if (rc.attended.isNotEmpty) 'On the day']),
        pw.SizedBox(height: 16),
        pw.Text('Compiled in Phoenix on ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 8)),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'Roll-call ${e.title}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final responses = ref.watch(eventResponsesProvider(widget.event.id));
    final members = ref.watch(membersProvider);
    return responses.when(
      loading: () => const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => EmptyState(icon: Icons.cloud_off, title: "Couldn't load the replies", message: '$e'),
      data: (list) {
        final merged = [
          for (final r in list) _marks.containsKey(r.cadetId) ? r.copyWith(attended: () => _marks[r.cadetId]) : r,
          for (final e in _marks.entries)
            if (!list.any((r) => r.cadetId == e.key))
              EventResponse(eventId: widget.event.id, cadetId: e.key, status: Attendance.coming, attended: e.value),
        ];
        final rc = rollCall(widget.event, members, merged);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TileGrid(minTileWidth: 150, children: [
            StatTile(label: 'Coming · refreshments', value: '${rc.coming.length}', icon: Icons.check_circle_outline),
            StatTile(label: 'Absent with permission', value: '${rc.absent.length}', icon: Icons.do_not_disturb_on_outlined),
            StatTile(label: 'No reply', value: '${rc.noReply.length}', icon: Icons.hourglass_empty),
            if (rc.attended.isNotEmpty) StatTile(label: 'Present on the day', value: '${rc.attended.length}', icon: Icons.how_to_reg_outlined),
          ]),
          const SizedBox(height: Space.md),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            FilledButton.icon(onPressed: () => _copy(rc), icon: const Icon(Icons.copy), label: const Text('Copy summary')),
            OutlinedButton.icon(onPressed: () => _pdf(rc), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Report PDF')),
            OutlinedButton.icon(
              onPressed: () => ref.invalidate(eventResponsesProvider(widget.event.id)),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ]),
          const SizedBox(height: Space.lg),
          SegmentedButton<_Tab>(
            segments: [
              ButtonSegment(value: _Tab.absent, label: Text('Absent ${rc.absent.length}')),
              ButtonSegment(value: _Tab.noReply, label: Text('No reply ${rc.noReply.length}')),
              ButtonSegment(value: _Tab.coming, label: Text('Coming ${rc.coming.length}')),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
          const SizedBox(height: Space.sm),
          if (_tab == _Tab.coming || _tab == _Tab.noReply)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mark who came'),
              subtitle: const Text('Tick each cadet present at the event.'),
              value: _marking,
              onChanged: (v) => setState(() => _marking = v),
            ),
          switch (_tab) {
            _Tab.absent => rc.absent.isEmpty
                ? const EmptyState(icon: Icons.check, title: 'No one has asked to be absent', message: '')
                : ListCard(children: [
                    for (final r in rc.absent)
                      ListTile(
                        leading: Icon(Icons.do_not_disturb_on_outlined, color: context.status.warning),
                        title: Text(r.cadetName),
                        subtitle: Text(r.reason ?? ''),
                        trailing: r.respondedAt == null ? null : Text(DateFormat('d MMM').format(r.respondedAt!), style: t.bodySmall),
                      ),
                  ]),
            _Tab.noReply => rc.noReply.isEmpty
                ? const EmptyState(icon: Icons.check, title: 'Everyone has replied', message: '')
                : ListCard(children: [
                    for (final m in rc.noReply)
                      _marking
                          ? CheckboxListTile(
                              value: rc.attended.contains(m.id),
                              onChanged: (v) => _mark(m.id, v ?? false),
                              title: Text(m.displayName),
                              subtitle: const Text('No reply'),
                            )
                          : ListTile(leading: const Icon(Icons.hourglass_empty), title: Text(m.displayName)),
                  ]),
            _Tab.coming => rc.coming.isEmpty
                ? const EmptyState(icon: Icons.group_off_outlined, title: 'No one has confirmed yet', message: '')
                : ListCard(children: [
                    for (final r in rc.coming)
                      _marking
                          ? CheckboxListTile(
                              value: rc.attended.contains(r.cadetId),
                              onChanged: (v) => _mark(r.cadetId, v ?? false),
                              title: Text(r.cadetName),
                            )
                          : ListTile(
                              leading: Icon(rc.attended.contains(r.cadetId) ? Icons.how_to_reg : Icons.check_circle_outline,
                                  color: context.status.success),
                              title: Text(r.cadetName),
                            ),
                  ]),
          },
          const SizedBox(height: Space.sm),
          Text('Only the ANO and senior cadets see reasons and this list.', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
        ]);
      },
    );
  }
}
