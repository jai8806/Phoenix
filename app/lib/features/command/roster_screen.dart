import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/roster.dart';
import '../../data/providers.dart';
import '../shared/widgets.dart';

class RosterScreen extends ConsumerStatefulWidget {
  const RosterScreen({super.key});

  @override
  ConsumerState<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends ConsumerState<RosterScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    final q = _query.toLowerCase();
    final shown = roster
        .where((r) =>
            q.isEmpty ||
            r.user.fullName.toLowerCase().contains(q) ||
            (r.user.regimentalNo ?? '').toLowerCase().contains(q))
        .toList();

    return PageBody(children: [
      Row(children: [
        Expanded(
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              labelText: 'Search by name or regimental number',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(width: Space.md),
        Tooltip(
          message: 'CSV roster import arrives in Phase 1',
          child: OutlinedButton.icon(onPressed: null, icon: const Icon(Icons.upload_file), label: const Text('Import CSV')),
        ),
      ]),
      const SizedBox(height: Space.sm),
      const Align(alignment: Alignment.centerLeft, child: DemoBadge(text: 'Sample roster · live roster and attendance come next')),
      const SizedBox(height: Space.lg),
      if (shown.isEmpty)
        EmptyState(
          icon: Icons.person_search_outlined,
          title: 'No cadets match "$_query"',
          message: 'Check the spelling, or search by regimental number.',
        )
      else
        ListCard(children: [for (final r in shown) _CadetRow(r)]),
    ]);
  }
}

class _CadetRow extends StatelessWidget {
  const _CadetRow(this.record);

  final RosterCadet record;

  @override
  Widget build(BuildContext context) {
    final e = record.eligibility;
    final c = Theme.of(context).colorScheme;
    final ok = e.isEligible;
    return ListTile(
      title: Text(record.user.displayName),
      subtitle: Text([
        if (record.user.wing != null) record.user.wing!.label,
        if (record.user.trainingYear != null) 'Year ${record.user.trainingYear}',
        'Attendance ${(record.attendance * 100).round()}%',
        if (record.mockAverage != null) 'Mocks ${record.mockAverage!.round()}%',
      ].join(' · ')),
      trailing: Chip(
        avatar: Icon(ok ? Icons.check : Icons.schedule, size: 16,
            color: ok ? context.status.success : context.status.warning),
        label: Text(ok ? '${e.rule.certificate} eligible' : '${e.rule.certificate} pending'),
        backgroundColor: c.surfaceContainerLow,
      ),
    );
  }
}
