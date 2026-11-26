import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/providers.dart';
import '../shared/widgets.dart';

class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    final roster = ref.watch(rosterProvider);
    final upcoming = ref.watch(upcomingEventsProvider).take(4).toList();
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;

    final eligible = roster.where((r) => r.eligibility.isEligible).length;
    final avgAttendance = roster.isEmpty
        ? 0
        : roster.map((r) => r.attendance).reduce((a, b) => a + b) / roster.length * 100;
    final mocks = [for (final r in roster) if (r.mockAverage != null) r.mockAverage!];
    final avgMock = mocks.isEmpty ? null : mocks.reduce((a, b) => a + b) / mocks.length;
    final atRisk = roster.where((r) => !r.eligibility.isEligible).toList()
      ..sort((a, b) => b.eligibility.periodsNeeded.compareTo(a.eligibility.periodsNeeded));

    return PageBody(children: [
      Row(children: [
        Expanded(child: Text('Welcome, ${user?.displayName ?? ''}', style: t.headlineSmall)),
        const DemoBadge(text: 'Sample roster'),
      ]),
      if (user?.unitName != null) Text(user!.unitName!, style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
      const SizedBox(height: Space.xl),
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
      const SectionHeader('Coming up'),
      if (upcoming.isEmpty)
        const EmptyState(icon: Icons.event_available, title: 'Nothing scheduled',
            message: 'Add parades, camps and exams from the Calendar.')
      else
        ListCard(children: [for (final e in upcoming) EventTile(e)]),
    ]);
  }
}
