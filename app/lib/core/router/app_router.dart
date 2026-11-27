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
import '../../features/cadet/edit_profile_screen.dart';
import '../../features/cadet/learn_screen.dart';
import '../../features/cadet/profile_screen.dart';
import '../../features/cadet/quiz_screen.dart';
import '../../features/cadet/study_screens.dart';
import '../../features/cadet/today_screen.dart';
import '../../features/cadet/ustaad_screen.dart';
import '../../features/command/command_shell.dart';
import '../../features/command/knowledge_screen.dart';
import '../../features/command/overview_screen.dart';
import '../../features/command/review_screen.dart';
import '../../features/command/roster_screen.dart';
import '../../features/command/test_results_screen.dart';
import '../../features/omr/exam_screen.dart';
import '../../features/omr/progress_screens.dart';
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
  static String quiz(String testId) => '/quiz/${Uri.encodeComponent(testId)}';
  static const plan = '/study-plan';
  static const editProfile = '/profile/edit';
  static String exam(String testId) => '/exam/${Uri.encodeComponent(testId)}';
  static const progress = '/progress';
  static const unitPerformance = '/command-performance';
  static String subject(String name) => '/subject?name=${Uri.encodeQueryComponent(name)}';
  /// A chapter of one book; without [book], the book for the cadet's division is picked.
  static String chapter(String code, {String? book}) =>
      '/chapter?code=${Uri.encodeQueryComponent(code)}${book == null ? '' : '&book=${Uri.encodeQueryComponent(book)}'}';
  static String book(String title) => '/book?title=${Uri.encodeQueryComponent(title)}';

  static const overview = '/command/overview';
  static const cadets = '/command/cadets';
  static const tests = '/command/tests';
  static const commandCalendar = '/command/calendar';
  static const commandAnnouncements = '/command/announcements';
  static const knowledge = '/command/knowledge';
  static const review = '/command-review';
  static String testResults(String id) => '/command-results/${Uri.encodeComponent(id)}';

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
      if (loc.startsWith('/command') && !user.role.canAdminister) return Routes.today;  // includes /command-review
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
      GoRoute(path: Routes.review, builder: (_, _) => const ReviewScreen()),
      GoRoute(
        path: '/command-results/:id',
        builder: (_, s) => TestResultsScreen(testId: Uri.decodeComponent(s.pathParameters['id']!)),
      ),
      GoRoute(path: Routes.plan, builder: (_, _) => const StudyPlanScreen()),
      GoRoute(path: Routes.editProfile, builder: (_, _) => const EditProfileScreen()),
      GoRoute(path: Routes.progress, builder: (_, _) => const ProgressScreen()),
      GoRoute(path: Routes.unitPerformance, builder: (_, _) => const UnitPerformanceScreen()),
      GoRoute(path: '/exam/:id', builder: (_, s) => ExamScreen(testId: Uri.decodeComponent(s.pathParameters['id']!))),
      GoRoute(path: '/subject', builder: (_, s) => SubjectScreen(name: s.uri.queryParameters['name'] ?? '')),
      GoRoute(
        path: '/chapter',
        builder: (_, s) => ChapterScreen(code: s.uri.queryParameters['code'] ?? '', book: s.uri.queryParameters['book']),
      ),
      GoRoute(path: '/book', builder: (_, s) => BookScreen(title: s.uri.queryParameters['title'] ?? '')),
      GoRoute(path: Routes.calendar, builder: (_, _) => const CalendarScreen(editable: false)),
      GoRoute(path: Routes.announcements, builder: (_, _) => const AnnouncementsScreen(editable: false)),
      GoRoute(
        path: '/quiz/:testId',
        builder: (_, state) => QuizScreen(testId: Uri.decodeComponent(state.pathParameters['testId']!)),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
