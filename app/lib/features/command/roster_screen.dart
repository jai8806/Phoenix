import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/roster.dart';
import '../../data/models/user.dart';
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
    final members = ref.watch(membersProvider);
    final records = {for (final r in ref.watch(rosterProvider)) r.user.id: r};
    final averages = ref.watch(testAveragesProvider);
    final me = ref.watch(authControllerProvider);
    final live = ref.watch(isLiveProvider);
    final q = _query.toLowerCase();
    final shown = members
        .where((m) =>
            q.isEmpty ||
            m.fullName.toLowerCase().contains(q) ||
            (m.regimentalNo ?? '').toLowerCase().contains(q) ||
            (m.rank ?? '').toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.role.index != b.role.index ? b.role.index - a.role.index : a.fullName.compareTo(b.fullName));
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;

    return PageBody(children: [
      TextField(
        onChanged: (v) => setState(() => _query = v),
        decoration: const InputDecoration(
          labelText: 'Search by name, rank or regimental number',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      const SizedBox(height: Space.sm),
      Row(children: [
        Expanded(
          child: Text(
            '${members.length} member${members.length == 1 ? '' : 's'}'
            '${me?.isCommand == true ? ' · tap someone to change their rank or appointment' : ''}',
            style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
        ),
        if (!live) const DemoBadge(text: 'Sample roster'),
      ]),
      const SizedBox(height: Space.lg),
      if (members.isEmpty)
        const EmptyState(
          icon: Icons.group_add_outlined,
          title: 'No one has joined yet',
          message: 'Share your unit join code with cadets. They enter it after creating an account.',
        )
      else if (shown.isEmpty)
        EmptyState(
          icon: Icons.person_search_outlined,
          title: 'No one matches "$_query"',
          message: 'Check the spelling, or search by regimental number.',
        )
      else
        ListCard(children: [
          for (final m in shown)
            _MemberRow(
              member: m,
              record: records[m.id],
              average: averages[m.id],
              onTap: me?.isCommand == true && m.id != me!.id && !m.role.isAno ? () => _edit(m) : null,
            ),
        ]),
    ]);
  }

  Future<void> _edit(AppUser m) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditMemberSheet(member: m),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, this.record, this.average, this.onTap});

  final AppUser member;
  final RosterCadet? record;
  final double? average;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final e = record?.eligibility;
    final initials = member.fullName.split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join();
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: member.role == AppRole.cadet ? c.surfaceContainerHigh : c.primaryContainer,
        child: Text(initials, style: t.labelLarge?.copyWith(
            color: member.role == AppRole.cadet ? c.onSurfaceVariant : c.onPrimaryContainer)),
      ),
      title: Text(member.displayName),
      subtitle: Text([
        if (member.role != AppRole.cadet) member.appointment?.fullName ?? member.role.label,
        if (member.regimentalNo != null) member.regimentalNo!,
        if (member.trainingYear != null) 'Year ${member.trainingYear}',
        if (average != null) 'Tests ${average!.round()}%',
        if (record?.mockAverage != null && average == null) 'Mocks ${record!.mockAverage!.round()}%',
      ].join(' · ')),
      trailing: e != null
          ? Chip(
              avatar: Icon(e.isEligible ? Icons.check : Icons.schedule, size: 16,
                  color: e.isEligible ? context.status.success : context.status.warning),
              label: Text(e.isEligible ? '${e.rule.certificate} eligible' : '${e.rule.certificate} pending'),
              backgroundColor: c.surfaceContainerLow,
            )
          : onTap == null
              ? null
              : const Icon(Icons.edit_outlined),
    );
  }
}

class _EditMemberSheet extends ConsumerStatefulWidget {
  const _EditMemberSheet({required this.member});

  final AppUser member;

  @override
  ConsumerState<_EditMemberSheet> createState() => _EditMemberSheetState();
}

class _EditMemberSheetState extends ConsumerState<_EditMemberSheet> {
  // null appointment + seniorCadet = senior cadet without an appointment.
  late AppRole _role = widget.member.role;
  late Appointment? _appointment = widget.member.appointment;
  late String? _rank = widget.member.rank;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(membersProvider.notifier).updateMember(widget.member, role: _role, rank: _rank, appointment: _appointment);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final ranks = {...cadetRanks, if (widget.member.rank != null) widget.member.rank!}.toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.member.fullName, style: t.titleLarge),
        const SizedBox(height: Space.lg),
        Text('Rank', style: t.labelLarge),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          for (final r in ranks)
            ChoiceChip(label: Text(r), selected: _rank == r, onSelected: (_) => setState(() => _rank = r)),
        ]),
        const SizedBox(height: Space.lg),
        Text('Appointment', style: t.labelLarge),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          ChoiceChip(
            label: const Text('Cadet'),
            selected: _role == AppRole.cadet,
            onSelected: (_) => setState(() {
              _role = AppRole.cadet;
              _appointment = null;
            }),
          ),
          for (final a in Appointment.values)
            ChoiceChip(
              label: Text(a.label),
              selected: _role == AppRole.seniorCadet && _appointment == a,
              onSelected: (_) => setState(() {
                _role = AppRole.seniorCadet;
                _appointment = a;
                if (cadetRanks.indexOf(_rank ?? 'CDT') < cadetRanks.indexOf(a.label)) _rank = a.label;
              }),
            ),
          ChoiceChip(
            label: const Text('Senior cadet, no appointment'),
            selected: _role == AppRole.seniorCadet && _appointment == null,
            onSelected: (_) => setState(() {
              _role = AppRole.seniorCadet;
              _appointment = null;
            }),
          ),
        ]),
        const SizedBox(height: Space.sm),
        Text(
          switch ((_role, _appointment)) {
            (AppRole.cadet, _) => 'Cadets use Learn, Ustaad, the diary and tests.',
            (_, Appointment a) when a.isCommand =>
              '${a.label}: full authority with the ANO. Manages the roster, publishes mocks and answers anonymous queries.',
            (_, Appointment a) =>
              '${a.label}: assists the CSUO / SUO. Opens the Command Center (notices, events, roll-call, mock drafts) '
                  'but cannot change the roster or publish mocks.',
            _ => 'Opens the Command Center to help out, without roster or publishing rights.',
          },
          style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
        ),
        if (_error != null) ...[
          const SizedBox(height: Space.md),
          Text(_error!, style: t.bodyMedium?.copyWith(color: c.error)),
        ],
        const SizedBox(height: Space.xl),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save changes')),
        ),
      ]),
    );
  }
}
