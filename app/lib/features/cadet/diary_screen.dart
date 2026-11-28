import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/diary.dart';
import '../../data/providers.dart';
import '../../domain/diary_stats.dart';
import '../shared/widgets.dart';

class DiaryScreen extends ConsumerWidget {
  const DiaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(diaryProvider);
    final stats = ref.watch(diaryStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Training diary'),
        actions: [
          TextButton.icon(
            onPressed: entries.isEmpty ? null : () => _showBrief(context, stats),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Brief'),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newDiaryEntry),
        icon: const Icon(Icons.add),
        label: const Text('Log session'),
      ),
      body: entries.isEmpty
          ? PageBody(children: [
              EmptyState(
                icon: Icons.edit_note,
                title: 'Your diary is empty',
                message: 'Log each training session in under a minute. Before competitions, '
                    'Phoenix turns your entries into a brief.',
                action: FilledButton(
                    onPressed: () => context.push(Routes.newDiaryEntry), child: const Text('Log first session')),
              ),
            ])
          : PageBody(children: [
              TileGrid(minTileWidth: 150, children: [
                StatTile(label: 'Last 30 days', value: '${stats.sessionsLast30Days}', caption: 'sessions',
                    icon: Icons.calendar_today_outlined),
                StatTile(label: 'Streak', value: '${stats.streakDays}', caption: 'days in a row',
                    icon: Icons.local_fire_department_outlined),
                if (stats.averageScore != null)
                  StatTile(label: 'Avg shooting score', value: stats.averageScore!.toStringAsFixed(1),
                      caption: 'best ${stats.bestScore}', icon: Icons.adjust),
                if (stats.groupImprovementMm != null)
                  StatTile(
                    label: 'Group size',
                    value: '${stats.latestGroupMm!.toStringAsFixed(0)} mm',
                    caption: stats.groupImprovementMm! >= 0
                        ? '${stats.groupImprovementMm!.toStringAsFixed(0)} mm tighter than at start'
                        : '${(-stats.groupImprovementMm!).toStringAsFixed(0)} mm wider than at start',
                    icon: Icons.center_focus_strong_outlined,
                  ),
              ]),
              const SectionHeader('Entries'),
              for (final e in entries)
                Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: _EntryCard(e)),
              const SizedBox(height: 72), // room for the floating button
            ]),
    );
  }

  void _showBrief(BuildContext context, DiaryStats stats) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _BriefSheet(stats: stats),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard(this.entry);

  final DiaryEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final s = entry.shooting;
    final details = <String>[
      if (entry.durationMinutes != null) '${entry.durationMinutes} min',
      if (s != null) ...[
        '${s.rifle} · ${s.position.label} · ${s.distanceMetres} m',
        if (s.score != null) 'score ${s.score}',
        if (s.groupMm != null) 'group ${s.groupMm!.toStringAsFixed(0)} mm',
      ],
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(entry.type.icon, size: 20, color: c.primary),
            const SizedBox(width: Space.sm),
            Text(entry.type.label, style: t.titleSmall),
            const Spacer(),
            if (entry.sharedWithUnit) ...[
              Icon(Icons.group_outlined, size: 16, color: c.onSurfaceVariant),
              const SizedBox(width: Space.xs),
            ],
            Text(DateFormat('EEE d MMM').format(entry.date), style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
          ]),
          if (details.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(details.join(' · '), style: t.bodyMedium),
          ],
          if (entry.wentWell != null) _Note(icon: Icons.thumb_up_outlined, text: entry.wentWell!, color: context.status.success),
          if (entry.toImprove != null) _Note(icon: Icons.trending_up, text: entry.toImprove!, color: context.status.warning),
          if (entry.instructorNotes != null)
            _Note(icon: Icons.record_voice_over_outlined, text: entry.instructorNotes!, color: c.secondary),
        ]),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: Space.sm),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ]),
    );
  }
}

/// Preview of the pre-competition brief. Today it is built from plain
/// statistics; in Phase 2 Claude writes it from the full diary, citing entries.
class _BriefSheet extends StatelessWidget {
  const _BriefSheet({required this.stats});

  final DiaryStats stats;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final points = <String>[
      'You logged ${stats.sessionsLast30Days} sessions in the last 30 days'
          '${stats.streakDays > 1 ? ', with a ${stats.streakDays}-day streak going' : ''}.',
      for (final e in stats.sessionsByType.entries) '${e.key.label}: ${e.value} session${e.value == 1 ? '' : 's'} logged.',
      if (stats.averageScore != null)
        'Shooting: average score ${stats.averageScore!.toStringAsFixed(1)}, best ${stats.bestScore}.',
      if (stats.groupImprovementMm != null && stats.groupImprovementMm! > 0)
        'Your groups tightened from about ${stats.firstGroupMm!.toStringAsFixed(0)} mm to '
            '${stats.latestGroupMm!.toStringAsFixed(0)} mm.',
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your brief', style: t.titleLarge),
          const SizedBox(height: Space.xs),
          Text('A summary of your diary so far.', style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
          const SizedBox(height: Space.lg),
          for (final p in points)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.check, size: 18, color: c.primary),
                const SizedBox(width: Space.sm),
                Expanded(child: Text(p, style: t.bodyMedium)),
              ]),
            ),
          const SizedBox(height: Space.md),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: c.secondaryContainer,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Row(children: [
              Icon(Icons.auto_awesome, size: 18, color: c.onSecondaryContainer),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'Coming next: AI briefs with strengths, weak spots, a 7-day focus plan and interview talking points, '
                  'each linked to the entries it came from.',
                  style: t.bodySmall?.copyWith(color: c.onSecondaryContainer),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
