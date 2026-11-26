import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/user.dart';
import '../../data/providers.dart';
import '../../features/auth/join_unit_screen.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/cadet/cadet_shell.dart';
import '../../features/cadet/diary_entry_screen.dart';
import '../../features/cadet/diary_screen.dart';
import '../../features/cadet/learn_screen.dart';
import '../../features/cadet/profile_screen.dart';
import '../../features/cadet/quiz_screen.dart';
import '../../features/cadet/today_screen.dart';
import '../../features/cadet/ustaad_screen.dart';
import '../../features/command/command_shell.dart';
import '../../features/command/knowledge_screen.dart';
import '../../features/command/overview_screen.dart';
import '../../features/command/roster_screen.dart';
import '../../features/command/tests_screen.dart';
import '../../features/shared/announcements_screen.dart';
import '../../features/shared/calendar_screen.dart';

abstract final class Routes {
  static const signIn = '/sign-in';
  static const joinUnit = '/join';
  static const today = '/cadet/today';
  static const learn = '/cadet/learn';
  static const ustaad = '/cadet/ustaad';
  static const diary = '/cadet/diary';
  static const me = '/cadet/me';
  static const newDiaryEntry = '/diary/new';
  static const calendar = '/calendar';
  static const announcements = '/announcements';
  static String quiz(String testId) => '/quiz/$testId';

  static const overview = '/command/overview';
  static const cadets = '/command/cadets';
  static const tests = '/command/tests';
  static const commandCalendar = '/command/calendar';
  static const commandAnnouncements = '/command/announcements';
  static const knowledge = '/command/knowledge';

  static String home(AppUser user) => user.role.canAdminister ? overview : today;
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier<AppUser?>(ref.read(authControllerProvider));
  ref.listen(authControllerProvider, (_, next) => auth.value = next);
  ref.onDispose(auth.dispose);

  final router = GoRouter(
    initialLocation: Routes.signIn,
    refreshListenable: auth,
    redirect: (context, state) {
      final user = auth.value;
      final loc = state.matchedLocation;
      if (user == null) return loc == Routes.signIn ? null : Routes.signIn;
      if (!user.hasUnit) return loc == Routes.joinUnit ? null : Routes.joinUnit;
      if (loc == Routes.signIn || loc == Routes.joinUnit) return Routes.home(user);
      if (loc.startsWith('/command') && !user.role.canAdminister) return Routes.today;
      return null;
    },
    routes: [
      GoRoute(path: Routes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: Routes.joinUnit, builder: (_, _) => const JoinUnitScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => CadetShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.today, builder: (_, _) => const TodayScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.learn, builder: (_, _) => const LearnScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.ustaad, builder: (_, _) => const UstaadScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.diary, builder: (_, _) => const DiaryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.me, builder: (_, _) => const ProfileScreen())]),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => CommandShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.overview, builder: (_, _) => const OverviewScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.cadets, builder: (_, _) => const RosterScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.tests, builder: (_, _) => const TestsScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.commandCalendar, builder: (_, _) => const CalendarScreen(editable: true)),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: Routes.commandAnnouncements,
                builder: (_, _) => const AnnouncementsScreen(editable: true)),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.knowledge, builder: (_, _) => const KnowledgeScreen())]),
        ],
      ),
      GoRoute(path: Routes.newDiaryEntry, builder: (_, _) => const DiaryEntryScreen()),
      GoRoute(path: Routes.calendar, builder: (_, _) => const CalendarScreen(editable: false)),
      GoRoute(path: Routes.announcements, builder: (_, _) => const AnnouncementsScreen(editable: false)),
      GoRoute(
        path: '/quiz/:testId',
        builder: (_, state) => QuizScreen(testId: state.pathParameters['testId']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
