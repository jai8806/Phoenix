import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/user.dart';
import '../../data/models/queries.dart';
import '../../data/providers.dart';
import '../shared/widgets.dart';

class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    final live = ref.watch(isLiveProvider);
    final upcoming = ref.watch(upcomingEventsProvider).take(4).toList();
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;

    return PageBody(children: [
      Row(children: [
        Expanded(child: Text('Welcome, ${user?.displayName ?? ''}', style: t.headlineSmall)),
        if (!live) const DemoBadge(text: 'Sample unit'),
      ]),
      if (user?.unitName != null) Text(user!.unitName!, style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
      const SizedBox(height: Space.xl),
      if (live) const _LiveSummary() else const _SampleSummary(),
      if (live && (user?.canHandleQueries(toAllSeniors: true) ?? false)) const _QueriesCard(),
      const SectionHeader('Coming up'),
      if (upcoming.isEmpty)
        const EmptyState(icon: Icons.event_available, title: 'Nothing scheduled',
            message: 'Add parades, camps and exams from the Calendar.')
      else
        ListCard(children: [for (final e in upcoming) EventTile(e)]),
    ]);
  }
}

/// Live unit: who has joined, how tests are going, who needs help.
class _LiveSummary extends ConsumerWidget {
  const _LiveSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider);
    final tests = ref.watch(testsProvider);
    final averages = ref.watch(testAveragesProvider);
    final bank = ref.watch(questionBankProvider);
    final now = ref.watch(clockProvider)();
    final cadets = members.where((m) => !m.role.isAno).toList();
    final seniors = members.where((m) => m.role == AppRole.seniorCadet).length;
    final open = tests.where((t) => t.isOpen(now)).length;
    final avg = averages.isEmpty ? null : averages.values.reduce((a, b) => a + b) / averages.length;
    final byId = {for (final m in members) m.id: m};
    final struggling = [
      for (final e in averages.entries)
        if (e.value < 50 && byId[e.key] != null) (byId[e.key]!, e.value),
    ]..sort((a, b) => a.$2.compareTo(b.$2));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TileGrid(minTileWidth: 170, children: [
        StatTile(label: 'Cadets joined', value: '${cadets.length}', icon: Icons.groups_outlined),
        StatTile(label: 'Senior cadets', value: '$seniors', icon: Icons.military_tech_outlined),
        StatTile(label: 'Tests open', value: '$open / ${tests.length}', icon: Icons.assignment_outlined),
        StatTile(label: 'Avg test score', value: avg == null ? '—' : '${avg.round()}%', icon: Icons.quiz_outlined),
      ]),
      const SectionHeader('Needs attention'),
      if (bank.isEmpty)
        Card(
          child: ListTile(
            leading: Icon(Icons.fact_check_outlined, color: context.status.warning),
            title: const Text('Approve questions to start testing'),
            subtitle: const Text('Practice, mocks and hosted tests all draw from approved questions.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.review),
          ),
        )
      else if (struggling.isEmpty)
        EmptyState(
          icon: Icons.check_circle_outline,
          title: tests.isEmpty ? 'Host your first test' : 'No one is below 50%',
          message: tests.isEmpty
              ? 'Create a test from the Tests tab; cadets averaging under 50% will show up here.'
              : 'Cadets averaging under 50% across your tests will show up here.',
        )
      else
        ListCard(children: [
          for (final (m, pct) in struggling.take(8))
            ListTile(
              leading: Icon(Icons.trending_down, color: context.status.warning),
              title: Text(m.displayName),
              subtitle: const Text('Averaging under 50% in unit tests'),
              trailing: Text('${pct.round()}%'),
            ),
        ]),
    ]);
  }
}

/// Sample unit with attendance-based eligibility, to show what a full unit looks like.
class _SampleSummary extends ConsumerWidget {
  const _SampleSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(rosterProvider);
    final eligible = roster.where((r) => r.eligibility.isEligible).length;
    final avgAttendance = roster.isEmpty
        ? 0
        : roster.map((r) => r.attendance).reduce((a, b) => a + b) / roster.length * 100;
    final mocks = [for (final r in roster) if (r.mockAverage != null) r.mockAverage!];
    final avgMock = mocks.isEmpty ? null : mocks.reduce((a, b) => a + b) / mocks.length;
    final atRisk = roster.where((r) => !r.eligibility.isEligible).toList()
      ..sort((a, b) => b.eligibility.periodsNeeded.compareTo(a.eligibility.periodsNeeded));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TileGrid(minTileWidth: 170, children: [
        StatTile(label: 'Cadets', value: '${roster.length}', icon: Icons.groups_outlined),
        StatTile(label: 'Avg attendance', value: '${avgAttendance.round()}%', icon: Icons.how_to_reg_outlined),
        StatTile(label: 'Exam eligible', value: '$eligible / ${roster.length}', icon: Icons.verified_outlined),
        StatTile(label: 'Avg mock score', value: avgMock == null ? '—' : '${avgMock.round()}%', icon: Icons.quiz_outlined),
      ]),
      const SectionHeader('Needs attention'),
      if (atRisk.isEmpty)
        const EmptyState(icon: Icons.check_circle_outline, title: 'Everyone is on track',
            message: 'All cadets currently meet their certificate requirements.')
      else
        ListCard(children: [
          for (final r in atRisk)
            ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: context.status.warning),
              title: Text(r.user.displayName),
              subtitle: Text(r.eligibility.blockers.join(' · ')),
              trailing: Text('${(r.attendance * 100).round()}%'),
            ),
        ]),
    ]);
  }
}


/// CSUO / SUO (and JUO / CSM / CQMS): anonymous queries waiting for them.
class _QueriesCard extends ConsumerWidget {
  const _QueriesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(queryInboxProvider).value ?? const <AnonQuery>[];
    final waiting = list.where((q) => q.awaitingSenior).length;
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Card(
        child: ListTile(
          leading: Badge(
            isLabelVisible: waiting > 0,
            label: Text('$waiting'),
            child: const Icon(Icons.forum_outlined),
          ),
          title: const Text('Anonymous queries'),
          subtitle: Text(waiting == 0
              ? 'Nothing waiting. Cadets ask here without their names; the ANO does not see them.'
              : '$waiting waiting for a reply'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.queryInbox),
        ),
      ),
    );
  }
}
