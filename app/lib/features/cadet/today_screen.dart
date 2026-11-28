import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/providers.dart';
import '../shared/event_screen.dart';
import '../shared/widgets.dart';
import 'study_screens.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    final now = ref.watch(clockProvider)();
    final upcoming = ref.watch(upcomingEventsProvider).take(3).toList();
    final announcements = ref.watch(announcementsProvider).take(2).toList();
    final toReply = ref.watch(pendingRollCallsProvider);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final greeting = now.hour < 12 ? 'Good morning' : (now.hour < 17 ? 'Good afternoon' : 'Good evening');

    return Scaffold(
      body: SafeArea(
        child: PageBody(children: [
          const SizedBox(height: Space.md),
          Text(DateFormat('EEEE, d MMMM').format(now).toUpperCase(),
              style: t.labelMedium?.copyWith(color: c.onSurfaceVariant, letterSpacing: 1.1)),
          const SizedBox(height: Space.xs),
          Text('$greeting, ${user?.firstName ?? 'Cadet'}', style: t.headlineMedium),
          if (user?.unitName != null)
            Text(user!.unitName!, style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
          const SizedBox(height: Space.xl),
          const _SyncBanner(),
          if (toReply.isNotEmpty) ...[
            SectionHeader(toReply.length == 1 ? 'Needs your reply' : 'Needs your reply (${toReply.length})'),
            for (final e in toReply.take(3)) ReplyCard(key: ValueKey('reply-${e.id}'), event: e, compact: true),
            const SizedBox(height: Space.md),
          ],
          const _ExamCountdownCard(),
          const SizedBox(height: Space.md),
          const _TodayPlanCard(),
          const _EligibilityCard(),
          const SizedBox(height: Space.md),
          const _FallInCard(),
          SectionHeader('Coming up', action: 'Calendar', onAction: () => context.push(Routes.calendar)),
          if (upcoming.isEmpty)
            const EmptyState(icon: Icons.event_available, title: 'Nothing scheduled',
                message: 'Parades, camps and exams your unit adds will show here.')
          else
            ListCard(children: [for (final e in upcoming) EventTile(e)]),
          SectionHeader('Announcements', action: 'See all', onAction: () => context.push(Routes.announcements)),
          if (announcements.isEmpty)
            const EmptyState(icon: Icons.campaign_outlined, title: 'No announcements yet',
                message: 'Notices from your ANO and senior cadets will appear here.')
          else
            ListCard(children: [for (final a in announcements) AnnouncementTile(a, now: now)]),
          const SizedBox(height: Space.lg),
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Something bothering you?'),
              subtitle: const Text('Ask a senior anonymously. Your name is never stored.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.askSeniors),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ExamCountdownCard extends ConsumerWidget {
  const _ExamCountdownCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exam = ref.watch(nextExamProvider);
    if (exam == null) return const SizedBox.shrink();
    final now = ref.watch(clockProvider)();
    final days = DateTime(exam.startsAt.year, exam.startsAt.month, exam.startsAt.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Card(
      color: c.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(exam.title.toUpperCase(),
                  style: t.labelMedium?.copyWith(color: c.onPrimary.withValues(alpha: 0.8), letterSpacing: 1.1)),
              const SizedBox(height: Space.xs),
              Text(DateFormat('d MMMM yyyy').format(exam.startsAt),
                  style: t.titleMedium?.copyWith(color: c.onPrimary)),
              const SizedBox(height: Space.md),
              FilledButton.tonal(
                onPressed: () => context.go(Routes.learn),
                child: const Text('Start preparing'),
              ),
            ]),
          ),
          Column(children: [
            Text('$days', style: t.displayMedium?.copyWith(color: c.onPrimary, height: 1)),
            Text(days == 1 ? 'DAY TO GO' : 'DAYS TO GO',
                style: t.labelSmall?.copyWith(color: c.onPrimary.withValues(alpha: 0.8), letterSpacing: 1.1)),
          ]),
        ]),
      ),
    );
  }
}

class _EligibilityCard extends ConsumerWidget {
  const _EligibilityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(myRecordProvider);
    final status = ref.watch(myEligibilityProvider);
    if (record == null || status == null) return const SizedBox.shrink();
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final good = status.isEligible;
    final accent = good ? context.status.success : context.status.warning;
    final pct = (status.attendance * 100).round();
    final target = (status.rule.minAttendance * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(good ? Icons.verified_outlined : Icons.pending_outlined, color: accent),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                good
                    ? "You're eligible for the ${status.rule.certificate} Certificate exam"
                    : '${status.rule.certificate} Certificate eligibility',
                style: t.titleSmall,
              ),
            ),
          ]),
          const SizedBox(height: Space.md),
          Row(children: [
            Text('Attendance $pct%', style: t.bodyMedium),
            const Spacer(),
            Text('Needed $target%', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
          ]),
          const SizedBox(height: Space.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: (status.attendance / status.rule.minAttendance).clamp(0, 1),
              minHeight: 8,
              color: accent,
              backgroundColor: c.surfaceContainerHighest,
            ),
          ),
          for (final b in status.blockers) ...[
            const SizedBox(height: Space.sm),
            Row(children: [
              Icon(Icons.arrow_right, size: 18, color: c.onSurfaceVariant),
              Expanded(child: Text(b, style: t.bodyMedium)),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _FallInCard extends StatelessWidget {
  const _FallInCard();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        onTap: () => context.push(Routes.quiz('fall-in')),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: c.tertiaryContainer, borderRadius: BorderRadius.circular(Radii.md)),
              child: Icon(Icons.bolt, color: c.onTertiaryContainer),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Daily Fall-In', style: t.titleSmall),
                Text('5 quick questions to keep your streak going',
                    style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}


class _SyncBanner extends ConsumerWidget {
  const _SyncBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issue = ref.watch(syncIssueProvider);
    if (issue == null) return const SizedBox.shrink();
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Card(
        color: c.errorContainer,
        child: ListTile(
          leading: Icon(Icons.cloud_off_outlined, color: c.onErrorContainer),
          title: Text(issue, style: TextStyle(color: c.onErrorContainer)),
          trailing: TextButton(
            onPressed: () {
              ref.read(syncIssueProvider.notifier).clear();
              for (final p in [announcementsProvider, eventsProvider, diaryProvider, questionBankProvider]) {
                ref.invalidate(p);
              }
            },
            child: const Text('Retry'),
          ),
        ),
      ),
    );
  }
}


class _TodayPlanCard extends ConsumerWidget {
  const _TodayPlanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(studyPlanProvider);
    final done = ref.watch(planProgressProvider);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final today = plan == null || plan.isEmpty ? null : plan.days.first;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Card(
        child: InkWell(
          onTap: () => context.push(Routes.plan),
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.event_note_outlined, color: c.primary),
                const SizedBox(width: Space.sm),
                Expanded(child: Text("Today's study", style: t.titleSmall)),
                if (today != null)
                  Text(
                    '${today.items.where((i) => done.contains(planItemId(today, i))).length}/${today.items.length} done',
                    style: t.labelMedium?.copyWith(color: c.onSurfaceVariant),
                  ),
                const Icon(Icons.chevron_right),
              ]),
              const SizedBox(height: Space.sm),
              if (today == null)
                Text('Set your exam date to get a plan weighted by marks, with revision built in.',
                    style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant))
              else
                for (final item in today.items.take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Row(children: [
                      Icon(
                        done.contains(planItemId(today, item))
                            ? Icons.check_circle
                            : (item.revision ? Icons.replay : Icons.radio_button_unchecked),
                        size: 18,
                        color: done.contains(planItemId(today, item)) ? c.primary : c.onSurfaceVariant,
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          item.chapter == null
                              ? item.label!
                              : '${item.revision ? 'Revise' : 'Study'} ${item.chapter!.title}',
                          style: t.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                  ),
            ]),
          ),
        ),
      ),
    );
  }
}
