import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/comms.dart';
import '../../data/providers.dart';
import '../../data/unit_repository.dart';
import 'widgets.dart';

/// Unit calendar. Cadets read it; admins can add events.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key, required this.editable});

  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(upcomingEventsProvider);
    final byMonth = <String, List<CalendarEvent>>{};
    for (final e in events) {
      byMonth.putIfAbsent(DateFormat('MMMM yyyy').format(e.startsAt), () => []).add(e);
    }

    final body = PageBody(children: [
      if (editable)
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => showDialog<void>(context: context, builder: (_) => const _NewEventDialog()),
            icon: const Icon(Icons.add),
            label: const Text('Add event'),
          ),
        ),
      if (events.isEmpty)
        const EmptyState(icon: Icons.event_available, title: 'Nothing scheduled',
            message: 'Upcoming parades, camps and exams will appear here.'),
      for (final entry in byMonth.entries) ...[
        SectionHeader(entry.key),
        ListCard(children: [for (final e in entry.value) EventTile(e)]),
      ],
    ]);

    // Inside the Command Center the shell already provides the app bar.
    return editable ? body : Scaffold(appBar: AppBar(title: const Text('Calendar')), body: body);
  }
}

class _NewEventDialog extends ConsumerStatefulWidget {
  const _NewEventDialog();

  @override
  ConsumerState<_NewEventDialog> createState() => _NewEventDialogState();
}

class _NewEventDialogState extends ConsumerState<_NewEventDialog> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  EventKind _kind = EventKind.parade;
  late DateTime _date = ref.read(clockProvider)().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  String? _titleError;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  bool _busy = false;
  String? _saveError;

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = 'Add a title, e.g. "Parade" or "ATC briefing"');
      return;
    }
    setState(() {
      _busy = true;
      _saveError = null;
    });
    try {
      await ref.read(eventsProvider.notifier).add(CalendarEvent(
            id: 'e${DateTime.now().microsecondsSinceEpoch}',
            title: _title.text.trim(),
            kind: _kind,
            startsAt: DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute),
            location: _location.text.trim().isEmpty ? null : _location.text.trim(),
          ));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _saveError = e is UnitDataFailure ? e.message : 'Couldn\'t add the event. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.read(clockProvider)();
    return AlertDialog(
      title: const Text('Add event'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _title,
            autofocus: true,
            onChanged: (_) => setState(() => _titleError = null),
            decoration: InputDecoration(labelText: 'Title', errorText: _titleError),
          ),
          const SizedBox(height: Space.md),
          DropdownButtonFormField<EventKind>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [for (final k in EventKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
            onChanged: (k) => setState(() => _kind = k ?? _kind),
          ),
          const SizedBox(height: Space.md),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(DateFormat('d MMM yyyy').format(_date)),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: now.subtract(const Duration(days: 1)),
                    lastDate: now.add(const Duration(days: 730)),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(_time.format(context)),
                onPressed: () async {
                  final picked = await showTimePicker(context: context, initialTime: _time);
                  if (picked != null) setState(() => _time = picked);
                },
              ),
            ),
          ]),
          const SizedBox(height: Space.md),
          TextField(controller: _location, decoration: const InputDecoration(labelText: 'Location (optional)')),
          if (_saveError != null) ...[
            const SizedBox(height: Space.md),
            Text(_saveError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Add event')),
      ],
    );
  }
}
