import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/user.dart';
import '../../data/providers.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Dest('Overview', Icons.space_dashboard_outlined, Icons.space_dashboard),
  _Dest('Cadets', Icons.groups_outlined, Icons.groups),
  _Dest('Tests', Icons.quiz_outlined, Icons.quiz),
  _Dest('Calendar', Icons.calendar_month_outlined, Icons.calendar_month),
  _Dest('Announcements', Icons.campaign_outlined, Icons.campaign),
  _Dest('Knowledge base', Icons.library_books_outlined, Icons.library_books),
];

/// Command Center layout: side rail on wide screens, drawer on phones.
class CommandShell extends ConsumerWidget {
  const CommandShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    final wide = MediaQuery.sizeOf(context).width >= wideLayoutBreakpoint;
    void go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

    final title = Text(_destinations[shell.currentIndex].label);
    final actions = [
      if (user?.role == AppRole.seniorCadet)
        IconButton(
          tooltip: 'Switch to cadet view',
          icon: const Icon(Icons.swap_horiz),
          onPressed: () => context.go(Routes.today),
        ),
      IconButton(
        tooltip: 'Sign out',
        icon: const Icon(Icons.logout),
        onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
      ),
      const SizedBox(width: Space.sm),
    ];

    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: MediaQuery.sizeOf(context).width >= 1100,
            selectedIndex: shell.currentIndex,
            onDestinationSelected: go,
            leading: const Padding(padding: EdgeInsets.symmetric(vertical: Space.lg), child: _RailHeader()),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                    icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Scaffold(appBar: AppBar(title: title, actions: actions), body: shell),
          ),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(title: title, actions: actions),
      drawer: NavigationDrawer(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) {
          Navigator.of(context).pop();
          go(i);
        },
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(28, Space.xl, Space.lg, Space.lg), child: _RailHeader()),
          for (final d in _destinations)
            NavigationDrawerDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
        ],
      ),
      body: shell,
    );
  }
}

class _RailHeader extends StatelessWidget {
  const _RailHeader();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(Radii.sm)),
        child: Icon(Icons.local_fire_department, color: c.onPrimary, size: 22),
      ),
      const SizedBox(width: Space.sm),
      Text('COMMAND', style: Theme.of(context).textTheme.titleLarge?.copyWith(letterSpacing: 1.5)),
    ]);
  }
}
