import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../data/providers.dart';
import '../shared/widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    final record = ref.watch(myRecordProvider);
    final mode = ref.watch(themeModeProvider);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    if (user == null) return const SizedBox.shrink();

    final initials = user.fullName.split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join();

    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: PageBody(children: [
        Row(children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: c.primaryContainer,
            child: Text(initials, style: t.titleLarge?.copyWith(color: c.onPrimaryContainer)),
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user.displayName, style: t.titleLarge),
              Text(
                [user.role.label, if (user.wing != null) user.wing!.label, if (user.division != null) user.division!.label]
                    .join(' · '),
                style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: Space.lg),
        OutlinedButton.icon(
          onPressed: () => context.push(Routes.editProfile),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit profile'),
        ),
        const SectionHeader('Service record'),
        ListCard(children: [
          ListTile(title: const Text('Rank'), trailing: Text(user.rank ?? '—')),
          ListTile(title: const Text('Regimental number'), trailing: Text(user.regimentalNo ?? '—')),
          ListTile(title: const Text('Unit'), subtitle: Text(user.unitName ?? '—')),
          ListTile(title: const Text('Training year'), trailing: Text(user.trainingYear?.toString() ?? '—')),
          if (record != null) ...[
            ListTile(
              title: const Text('Attendance'),
              trailing: Text('${record.periodsAttended} / ${record.periodsHeld} periods'),
            ),
            ListTile(title: const Text('Annual Training Camp'), trailing: Text(record.campDone ? 'Attended' : 'Not yet')),
            ListTile(
              title: const Text('Certificates'),
              trailing: Text(record.certificatesHeld.isEmpty ? 'None yet' : record.certificatesHeld.join(', ')),
            ),
          ],
        ]),
        const SectionHeader('Appearance'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {mode},
              onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
            ),
          ),
        ),
        const SectionHeader('Help'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Ask a senior anonymously'),
            subtitle: const Text('Only the CSUO / SUO read it. Your name is never stored; the ANO does not see it.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.askSeniors),
          ),
        ),
        const SectionHeader('Account'),
        ListCard(children: [
          if (user.role.canAdminister)
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Open Command Center'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(Routes.overview),
            ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ]),
      ]),
    );
  }
}
