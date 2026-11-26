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
  AppUser? build() => ref.read(initialUserProvider);

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> signInAs(AppRole role) async => state = await _repo.signInAs(role);

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
    await _repo.signOut();
    state = null;
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
// Unit content (demo data in Phase 0; Supabase-backed in Phase 1)
// ---------------------------------------------------------------------------
final announcementsProvider =
    NotifierProvider<AnnouncementsController, List<Announcement>>(AnnouncementsController.new);

class AnnouncementsController extends Notifier<List<Announcement>> {
  @override
  List<Announcement> build() => DemoData.announcements(ref.read(clockProvider)());

  void post({required String title, required String body, required String author, bool pinned = false}) {
    final a = Announcement(
      id: 'a${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      body: body,
      author: author,
      createdAt: ref.read(clockProvider)(),
      pinned: pinned,
    );
    state = [a, ...state];
  }
}

final eventsProvider = NotifierProvider<EventsController, List<CalendarEvent>>(EventsController.new);

class EventsController extends Notifier<List<CalendarEvent>> {
  @override
  List<CalendarEvent> build() => DemoData.events(ref.read(clockProvider)());

  void add(CalendarEvent e) =>
      state = [...state, e]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
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

final questionBankProvider = Provider<List<Question>>((ref) => DemoData.questions);

final testsProvider = NotifierProvider<TestsController, List<TestDefinition>>(TestsController.new);

class TestsController extends Notifier<List<TestDefinition>> {
  @override
  List<TestDefinition> build() => DemoData.tests(ref.read(clockProvider)());

  void add(TestDefinition t) => state = [t, ...state];
}

final rosterProvider = Provider<List<RosterCadet>>((ref) => DemoData.roster());

final documentsProvider = Provider<List<KnowledgeDocument>>((ref) => DemoData.documents());

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

class DiaryController extends Notifier<List<DiaryEntry>> {
  @override
  List<DiaryEntry> build() => DemoData.diary(ref.read(clockProvider)())
    ..sort((a, b) => b.date.compareTo(a.date));

  void add(DiaryEntry e) => state = [e, ...state]..sort((a, b) => b.date.compareTo(a.date));
}

final diaryStatsProvider = Provider<DiaryStats>(
  (ref) => computeDiaryStats(ref.watch(diaryProvider), today: ref.watch(clockProvider)()),
);
