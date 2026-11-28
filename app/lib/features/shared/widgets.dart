import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/comms.dart';
import '../../data/providers.dart';

/// Centres page content and caps its width on large screens.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxContentWidth),
        child: ListView(
          padding: padding ?? const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xxl),
          children: children,
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.xl, bottom: Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(title.toUpperCase(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      letterSpacing: 1.1,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// A single number with a label, for dashboards.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.caption, this.icon});

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 18, color: c.onSurfaceVariant), const SizedBox(width: Space.sm)],
              Expanded(child: Text(label, style: t.labelMedium?.copyWith(color: c.onSurfaceVariant))),
            ]),
            const SizedBox(height: Space.sm),
            Text(value, style: t.headlineMedium),
            if (caption != null) ...[
              const SizedBox(height: Space.xs),
              Text(caption!, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lays children out in a responsive grid of equal-width tiles.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.minTileWidth = 200});

  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cols = (box.maxWidth / minTileWidth).floor().clamp(1, 4);
      final w = (box.maxWidth - Space.md * (cols - 1)) / cols;
      return Wrap(
        spacing: Space.md,
        runSpacing: Space.md,
        children: [for (final child in children) SizedBox(width: w, child: child)],
      );
    });
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xxl),
      child: Column(children: [
        Icon(icon, size: 40, color: c.onSurfaceVariant),
        const SizedBox(height: Space.md),
        Text(title, style: t.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: Space.xs),
        Text(message, style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant), textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: Space.lg), action!],
      ]),
    );
  }
}

/// Small label shown on screens that still run on sample data.
class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key, this.text = 'Sample data'});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
      decoration: BoxDecoration(
        color: c.secondaryContainer,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.onSecondaryContainer)),
    );
  }
}

IconData eventIcon(EventKind k) => switch (k) {
      EventKind.parade => Icons.groups_outlined,
      EventKind.camp => Icons.cabin_outlined,
      EventKind.exam => Icons.school_outlined,
      EventKind.test => Icons.quiz_outlined,
      EventKind.event => Icons.event_outlined,
    };

class EventTile extends ConsumerWidget {
  const EventTile(this.event, {super.key});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).colorScheme;
    final isAno = ref.watch(authControllerProvider)?.role.isAno ?? false;
    final reply = isAno ? null : ref.watch(myResponsesProvider).where((r) => r.eventId == event.id).firstOrNull?.status;
    final asks = event.needsResponse && !isAno;
    final day = DateFormat('d').format(event.startsAt);
    final month = DateFormat('MMM').format(event.startsAt).toUpperCase();
    final when = event.endsAt == null
        ? DateFormat('EEE, h:mm a').format(event.startsAt)
        : '${DateFormat('d MMM').format(event.startsAt)} – ${DateFormat('d MMM').format(event.endsAt!)}';
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: c.primaryContainer,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(month,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: c.onPrimaryContainer, fontSize: 10, height: 1.1)),
          Text(day,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: c.onPrimaryContainer, fontSize: 20, height: 1.0)),
        ]),
      ),
      title: Text(event.title),
      subtitle: Text([
        when,
        if (event.location != null) event.location!,
        if (event.needsResponse && isAno) 'roll-call',
        if (asks) reply == null ? 'reply needed' : (reply == Attendance.coming ? "you're coming" : "you can't come"),
      ].join(' · ')),
      trailing: Icon(
        asks ? (reply == null ? Icons.how_to_vote_outlined : Icons.check_circle_outline) : eventIcon(event.kind),
        color: asks && reply == null ? c.primary : c.onSurfaceVariant,
      ),
      onTap: () => GoRouter.of(context).push('/event/${Uri.encodeComponent(event.id)}'),
    );
  }
}

class AnnouncementTile extends StatelessWidget {
  const AnnouncementTile(this.announcement, {super.key, required this.now});

  final Announcement announcement;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (announcement.pinned) ...[
            Icon(Icons.push_pin, size: 16, color: c.tertiary),
            const SizedBox(width: Space.xs),
          ],
          Expanded(child: Text(announcement.title, style: t.titleSmall)),
        ]),
        const SizedBox(height: Space.xs),
        Text(announcement.body, style: t.bodyMedium),
        const SizedBox(height: Space.sm),
        Text('${announcement.author} · ${timeAgo(announcement.createdAt, now)}',
            style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
      ]),
    );
  }
}

String timeAgo(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return DateFormat('d MMM').format(then);
}

/// Wraps a list of widgets in a card with dividers between them.
class ListCard extends StatelessWidget {
  const ListCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(),
          children[i],
        ],
      ]),
    );
  }
}
