import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/diary_stats.dart';
import '../domain/eligibility.dart';
import 'auth_repository.dart';
import 'demo/demo_data.dart';
import 'models/comms.dart';
import 'models/diary.dart';
import 'models/roster.dart';
import 'models/test.dart';
import 'models/user.dart';
import 'unit_repository.dart';

/// Overridden in main() and in tests.
final authRepositoryProvider = Provider<AuthRepository>((ref) => DemoAuthRepository());
final initialUserProvider = Provider<AppUser?>((ref) => null);
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

/// The clock, injectable so tests can freeze time.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------
final authControllerProvider = NotifierProvider<AuthController, AppUser?>(AuthController.new);

class AuthController extends Notifier<AppUser?> {
  @override
  AppUser? build() {
    // Opening the confirmation link signs the user in behind the scenes.
    final sub = ref.read(authRepositoryProvider).externalSignIns.listen(
      (user) {
        if (state?.id != user.id) state = user;
      },
      onError: (_) {}, // the sign-in screen still works if this fails
    );
    ref.onDispose(sub.cancel);
    return ref.read(initialUserProvider);
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> signInAs(AppRole role) async => state = await _repo.signInAs(role);

  /// Look around with sample data, even when a backend is configured.
  void exploreDemo(AppRole role) => state = DemoData.forRole(role);

  Future<void> signInWithPassword(String email, String password) async =>
      state = await _repo.signInWithPassword(email: email, password: password);

  /// Returns false when the account needs its email confirmed before signing in.
  Future<bool> signUp(String email, String password, String fullName) async {
    final user = await _repo.signUp(email: email, password: password, fullName: fullName);
    if (user != null) state = user;
    return user != null;
  }

  Future<void> joinUnit(String code) async => state = await _repo.joinUnit(code);

  Future<void> signOut() async {
    try {
      await _repo.signOut();
    } finally {
      state = null;
    }
  }
}

// ---------------------------------------------------------------------------
// Appearance
// ---------------------------------------------------------------------------
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    final saved = ref.read(sharedPreferencesProvider)?.getString(_key);
    return ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
  }

  void set(ThemeMode mode) {
    state = mode;
    ref.read(sharedPreferencesProvider)?.setString(_key, mode.name);
  }
}

// ---------------------------------------------------------------------------
// Live data
// ---------------------------------------------------------------------------

/// Builds the live repository for a signed-in member. Overridden in main()
/// when a backend is configured, and in tests with a fake.
final unitRepositoryFactoryProvider = Provider<UnitRepository Function(AppUser user)?>((ref) => null);

/// The live repository, or null in sample mode (demo build, "Explore with
/// sample data", or a member who hasn't joined a unit yet).
final unitRepositoryProvider = Provider<UnitRepository?>((ref) {
  final factory = ref.watch(unitRepositoryFactoryProvider);
  final user = ref.watch(authControllerProvider);
  if (factory == null || user == null || user.isSample || user.unitId == null) return null;
  return factory(user);
});

/// True when the screens show the unit's real data.
final isLiveProvider = Provider<bool>((ref) => ref.watch(unitRepositoryProvider) != null);

/// The latest problem loading live data, shown as a banner until it clears.
final syncIssueProvider = NotifierProvider<SyncIssueController, String?>(SyncIssueController.new);

class SyncIssueController extends Notifier<String?> {
  @override
  String? build() => null;

  void report(Object error) => state = error is UnitDataFailure ? error.message : 'Some data could not be loaded.';
  void clear() => state = null;
}

/// Shared shape for lists that come from demo data or from Supabase.
abstract class LiveListController<T> extends Notifier<List<T>> {
  List<T> demo();
  Future<List<T>> fetch(UnitRepository repo);

  UnitRepository? get repo => ref.read(unitRepositoryProvider);

  @override
  List<T> build() {
    final live = ref.watch(unitRepositoryProvider);
    if (live == null) return demo();
    Future.microtask(() => reload(live));
    return const [];
  }

  Future<void> reload([UnitRepository? r]) async {
    final live = r ?? repo;
    if (live == null) return;
    try {
      final items = await fetch(live);
      if (ref.mounted) state = items;
    } catch (e) {
      if (ref.mounted) ref.read(syncIssueProvider.notifier).report(e);
    }
  }
}

// ---------------------------------------------------------------------------
// Unit content
// ---------------------------------------------------------------------------
final announcementsProvider =
    NotifierProvider<AnnouncementsController, List<Announcement>>(AnnouncementsController.new);

class AnnouncementsController extends LiveListController<Announcement> {
  @override
  List<Announcement> demo() => DemoData.announcements(ref.read(clockProvider)());

  @override
  Future<List<Announcement>> fetch(UnitRepository repo) => repo.announcements();

  /// Posts to the unit (live) or adds locally (sample). Throws [UnitDataFailure] on failure.
  Future<void> post({required String title, required String body, required String author, bool pinned = false}) async {
    final live = repo;
    if (live != null) {
      await live.postAnnouncement(title: title, body: body, pinned: pinned);
      await reload(live);
      return;
    }
    state = [
      Announcement(
        id: 'a${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        body: body,
        author: author,
        createdAt: ref.read(clockProvider)(),
        pinned: pinned,
      ),
      ...state,
    ];
  }
}

final eventsProvider = NotifierProvider<EventsController, List<CalendarEvent>>(EventsController.new);

class EventsController extends LiveListController<CalendarEvent> {
  @override
  List<CalendarEvent> demo() => DemoData.events(ref.read(clockProvider)());

  @override
  Future<List<CalendarEvent>> fetch(UnitRepository repo) => repo.events();

  Future<void> add(CalendarEvent e) async {
    final live = repo;
    if (live != null) {
      await live.addEvent(e);
      await reload(live);
      return;
    }
    state = [...state, e]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }
}

/// Upcoming events, soonest first.
final upcomingEventsProvider = Provider<List<CalendarEvent>>((ref) {
  final now = ref.watch(clockProvider)();
  return ref.watch(eventsProvider).where((e) => !e.startsAt.isBefore(now)).toList()
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
});

final nextExamProvider = Provider<CalendarEvent?>((ref) {
  for (final e in ref.watch(upcomingEventsProvider)) {
    if (e.kind == EventKind.exam) return e;
  }
  return null;
});

/// Questions cadets practise with: the starter set in sample mode, the
/// unit's approved questions when live.
final questionBankProvider =
    NotifierProvider<QuestionBankController, List<Question>>(QuestionBankController.new);

class QuestionBankController extends LiveListController<Question> {
  @override
  List<Question> demo() => DemoData.questions;

  @override
  Future<List<Question>> fetch(UnitRepository repo) => repo.approvedQuestions();
}

/// Tests hosted by the unit. Sample only for now; live hosted tests come next.
final testsProvider = NotifierProvider<TestsController, List<TestDefinition>>(TestsController.new);

class TestsController extends Notifier<List<TestDefinition>> {
  @override
  List<TestDefinition> build() =>
      ref.watch(isLiveProvider) ? const [] : DemoData.tests(ref.read(clockProvider)());

  void add(TestDefinition t) => state = [t, ...state];
}

final rosterProvider = Provider<List<RosterCadet>>((ref) => DemoData.roster());

final documentsProvider =
    NotifierProvider<DocumentsController, List<KnowledgeDocument>>(DocumentsController.new);

class DocumentsController extends LiveListController<KnowledgeDocument> {
  @override
  List<KnowledgeDocument> demo() => DemoData.documents();

  @override
  Future<List<KnowledgeDocument>> fetch(UnitRepository repo) => repo.documents();
}

/// The signed-in cadet's own record, if they are on the roster.
final myRecordProvider = Provider<RosterCadet?>((ref) {
  final me = ref.watch(authControllerProvider);
  if (me == null) return null;
  for (final r in ref.watch(rosterProvider)) {
    if (r.user.id == me.id) return r;
  }
  return null;
});

final myEligibilityProvider = Provider<EligibilityStatus?>((ref) => ref.watch(myRecordProvider)?.eligibility);

// ---------------------------------------------------------------------------
// Training diary
// ---------------------------------------------------------------------------
final diaryProvider = NotifierProvider<DiaryController, List<DiaryEntry>>(DiaryController.new);

class DiaryController extends LiveListController<DiaryEntry> {
  @override
  List<DiaryEntry> demo() => DemoData.diary(ref.read(clockProvider)())..sort((a, b) => b.date.compareTo(a.date));

  @override
  Future<List<DiaryEntry>> fetch(UnitRepository repo) => repo.diary();

  Future<void> add(DiaryEntry e) async {
    final live = repo;
    if (live != null) {
      await live.addDiaryEntry(e);
      await reload(live);
      return;
    }
    state = [e, ...state]..sort((a, b) => b.date.compareTo(a.date));
  }
}

final diaryStatsProvider = Provider<DiaryStats>(
  (ref) => computeDiaryStats(ref.watch(diaryProvider), today: ref.watch(clockProvider)()),
);
