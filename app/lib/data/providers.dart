import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/diary_stats.dart';
import '../domain/eligibility.dart';
import '../domain/hosted_tests.dart';
import '../domain/omr/progress.dart';
import 'auth_repository.dart';
import 'demo/demo_data.dart';
import 'models/comms.dart';
import 'models/diary.dart';
import 'models/roster.dart';
import 'models/test.dart';
import 'models/user.dart';
import 'exam/exam_data.dart';
import 'models/figure.dart';
import 'precis_pack.dart';
import 'unit_repository.dart';
import '../domain/precis_search.dart';

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

  /// Sample users edit a local copy; live members save to the backend.
  Future<void> updateProfile(AppUser updated) async =>
      state = updated.isSample ? updated : await _repo.updateProfile(updated);

  Future<void> signOut() async {
    try {
      await _repo.signOut();
    } finally {
      state = null;
      // The précis saved for offline use belongs to the signed-in member only.
      try {
        await ref.read(precisPackStoreProvider).clear();
      } catch (_) {}
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

/// The member's own roll-call replies, by event id.
final myResponsesProvider = NotifierProvider<MyResponsesController, List<EventResponse>>(MyResponsesController.new);

class MyResponsesController extends LiveListController<EventResponse> {
  @override
  List<EventResponse> demo() => const [];

  @override
  Future<List<EventResponse>> fetch(UnitRepository repo) => repo.myResponses();

  EventResponse? forEvent(String id) {
    for (final r in state) {
      if (r.eventId == id) return r;
    }
    return null;
  }

  /// Sends a reply (kept on the phone in sample mode). Throws UnitDataFailure.
  Future<void> respond(String eventId, Attendance status, {String? reason}) async {
    await repo?.respondToEvent(eventId, status, reason: reason);
    final me = ref.read(authControllerProvider);
    final reply = EventResponse(
      eventId: eventId,
      cadetId: me?.id ?? '',
      cadetName: me?.displayName ?? '',
      status: status,
      reason: status == Attendance.absent ? reason?.trim() : null,
      respondedAt: ref.read(clockProvider)(),
    );
    state = [for (final r in state) if (r.eventId != eventId) r, reply];
  }
}

/// Upcoming roll-calls the member hasn't answered yet, soonest first.
final pendingRollCallsProvider = Provider<List<CalendarEvent>>((ref) {
  final now = ref.watch(clockProvider)();
  final replied = {for (final r in ref.watch(myResponsesProvider)) r.eventId};
  return [
    for (final e in ref.watch(upcomingEventsProvider))
      if (e.repliesOpen(now) && !replied.contains(e.id)) e,
  ];
});

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

/// Tests hosted by the unit: sample tests in sample mode, the unit's when live.
final testsProvider = NotifierProvider<TestsController, List<TestDefinition>>(TestsController.new);

class TestsController extends LiveListController<TestDefinition> {
  @override
  List<TestDefinition> demo() => DemoData.tests(ref.read(clockProvider)());

  @override
  Future<List<TestDefinition>> fetch(UnitRepository repo) => repo.tests();

  /// Hosts a test. Throws [UnitDataFailure] with a message to show.
  Future<void> create(NewTest t) async {
    final live = repo;
    if (live == null) {
      state = [
        TestDefinition(
          id: 't${DateTime.now().microsecondsSinceEpoch}',
          title: t.title,
          description: t.description,
          durationMinutes: t.durationMinutes,
          marking: t.marking,
          questionIds: t.questionIds,
          opensAt: t.opensAt,
          closesAt: t.closesAt,
          mode: t.mode,
          pattern: t.pattern,
          sheetCode: t.sheetCode,
          uploadMinutes: t.uploadMinutes,
          setSeed: t.setSeed,
          numbers: t.numbers ?? const [],
        ),
        ...state,
      ];
      return;
    }
    await live.createTest(t);
    await reload(live);
  }

  Future<void> delete(String id) async {
    await repo?.deleteTest(id);
    state = [for (final t in state) if (t.id != id) t];
  }

  /// Starts an OMR mock now (sample mode starts it locally).
  Future<void> start(TestDefinition t) async {
    final live = repo;
    final now = ref.read(clockProvider)();
    final started = live == null
        ? t.copyWith(startedAt: now, opensAt: now, closesAt: now.add(Duration(minutes: t.durationMinutes + t.uploadMinutes)))
        : await live.startTest(t);
    state = [for (final x in state) x.id == t.id ? started : x];
  }

  /// Records the cadet's score after they submit.
  void markTaken(String id, double score) =>
      state = [for (final t in state) t.id == id ? t.withMyScore(score) : t];
}

/// The member's own submitted attempts, with every answer.
final myHistoryProvider = NotifierProvider<MyHistoryController, List<AttemptHistory>>(MyHistoryController.new);

class MyHistoryController extends LiveListController<AttemptHistory> {
  @override
  List<AttemptHistory> demo() => const [];

  @override
  Future<List<AttemptHistory>> fetch(UnitRepository repo) => repo.attemptHistory();
}

/// Every attempt in the unit (admins).
final unitHistoryProvider = NotifierProvider<UnitHistoryController, List<AttemptHistory>>(UnitHistoryController.new);

class UnitHistoryController extends LiveListController<AttemptHistory> {
  @override
  List<AttemptHistory> demo() => const [];

  @override
  Future<List<AttemptHistory>> fetch(UnitRepository repo) => repo.attemptHistory(wholeUnit: true);
}

/// Sample records with attendance and camp, used only in sample mode.
final rosterProvider = Provider<List<RosterCadet>>(
    (ref) => ref.watch(isLiveProvider) ? const [] : DemoData.roster());

/// Everyone in the unit.
final membersProvider = NotifierProvider<MembersController, List<AppUser>>(MembersController.new);

class MembersController extends LiveListController<AppUser> {
  @override
  List<AppUser> demo() => [for (final r in DemoData.roster()) r.user];

  @override
  Future<List<AppUser>> fetch(UnitRepository repo) => repo.members();

  /// ANO only. Sample mode changes the local list.
  Future<void> updateMember(AppUser m, {required AppRole role, String? rank}) async {
    await repo?.updateMember(m.id, role: role, rank: rank);
    state = [
      for (final u in state) u.id == m.id ? u.copyWith(role: role, rank: () => rank) : u,
    ];
  }
}

/// Every test score in the unit (admins see all, cadets their own).
final unitScoresProvider = NotifierProvider<UnitScoresController, List<ScoreRow>>(UnitScoresController.new);

class UnitScoresController extends LiveListController<ScoreRow> {
  @override
  List<ScoreRow> demo() => const [];

  @override
  Future<List<ScoreRow>> fetch(UnitRepository repo) => repo.unitScores();
}

/// Average test percentage per cadet id.
final testAveragesProvider = Provider<Map<String, double>>(
    (ref) => averagePercentByCadet(ref.watch(unitScoresProvider), ref.watch(testsProvider)));

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

// ---------------------------------------------------------------------------
// Offline précis for Ustaad
// ---------------------------------------------------------------------------
final precisPackStoreProvider = Provider<PrecisPackStore>((ref) => MemoryPrecisPackStore());

enum PrecisStatus { sample, loading, ready, error }

class PrecisState {
  const PrecisState(this.status, {this.search, this.error, this.refreshing = false, this.figures = const []});

  final PrecisStatus status;
  final PrecisSearch? search;

  /// Figures from the précis, by chapter and page.
  final List<PrecisFigure> figures;

  /// Figures for a chapter of [book] (chapter codes repeat across books, e.g. "AF I").
  List<PrecisFigure> figuresFor(String chapterCode, {String? book, int? fromPage, int? toPage}) => [
        for (final f in figures)
          if (f.chapterCode == chapterCode &&
              (book == null || f.title == book) &&
              (fromPage == null || (f.page != null && f.page! >= fromPage && f.page! <= (toPage ?? fromPage))))
            f,
      ];
  final String? error;

  /// A newer copy is downloading while the saved one is in use.
  final bool refreshing;

  int get passageCount => search?.passages.length ?? 0;

  /// Books in the downloaded précis, in the order they were loaded.
  List<String> get books => {for (final p in search?.passages ?? const <PrecisPassage>[]) p.title}.toList();

  /// (code, title, passage count) for each chapter of [book], in book order.
  List<(String, String, int)> chaptersOf(String book) {
    final out = <String, (String, int)>{};
    for (final p in search?.passages ?? const <PrecisPassage>[]) {
      if (p.title != book) continue;
      final parts = p.heading.split(' · ');
      final (title, n) = out[parts.first] ?? (parts.length > 1 ? parts[1] : parts.first, 0);
      out[parts.first] = (title, n + 1);
    }
    return [for (final e in out.entries) (e.key, e.value.$1, e.value.$2)];
  }
}

/// Downloads the précis once, keeps it on the phone, and refreshes it in the
/// background, so Ustaad can answer instantly and offline without any AI.
final precisProvider = NotifierProvider<PrecisController, PrecisState>(PrecisController.new);

class PrecisController extends Notifier<PrecisState> {
  @override
  PrecisState build() {
    final repo = ref.watch(unitRepositoryProvider);
    if (repo == null) return const PrecisState(PrecisStatus.sample);
    Future.microtask(() => _start(repo));
    return const PrecisState(PrecisStatus.loading);
  }

  Future<void> _start(UnitRepository repo) async {
    final store = ref.read(precisPackStoreProvider);
    final saved = await store.load();
    final savedFigures = await store.loadFigures();
    if (!ref.mounted) return;
    if (saved != null && saved.isNotEmpty) {
      state = PrecisState(PrecisStatus.ready, search: PrecisSearch(saved), refreshing: true, figures: savedFigures);
    }
    await refresh(repo);
  }

  Future<void> refresh([UnitRepository? r]) async {
    final repo = r ?? ref.read(unitRepositoryProvider);
    if (repo == null) return;
    try {
      final passages = await repo.precisPassages();
      // Figures are optional: the précis still works if they can't load.
      List<PrecisFigure> figures;
      try {
        figures = await repo.figures();
      } catch (_) {
        figures = state.figures;
      }
      if (!ref.mounted) return;
      if (passages.isEmpty && state.search != null) {
        state = PrecisState(PrecisStatus.ready, search: state.search, figures: figures);
        return;
      }
      final store = ref.read(precisPackStoreProvider);
      await store.save(passages);
      await store.saveFigures(figures);
      if (!ref.mounted) return;
      state = PrecisState(PrecisStatus.ready, search: PrecisSearch(passages), figures: figures);
    } catch (e) {
      if (!ref.mounted) return;
      // Offline with a saved copy: keep answering from it.
      state = state.search != null
          ? PrecisState(PrecisStatus.ready, search: state.search, figures: state.figures)
          : PrecisState(PrecisStatus.error,
              error: e is UnitDataFailure ? e.message : "Couldn't download the study material.");
    }
  }
}

// ---------------------------------------------------------------------------
// Exam prep: track, exam date and study-plan progress (saved on the phone)
// ---------------------------------------------------------------------------
final certTrackProvider = NotifierProvider<CertTrackController, CertTrack>(CertTrackController.new);

class CertTrackController extends Notifier<CertTrack> {
  static const _key = 'cert_track';

  @override
  CertTrack build() {
    final saved = ref.read(sharedPreferencesProvider)?.getString(_key);
    if (saved != null) return CertTrack.values.firstWhere((t) => t.name == saved, orElse: () => CertTrack.b);
    final user = ref.read(authControllerProvider);
    return (user?.trainingYear ?? 2) >= 3 ? CertTrack.c : CertTrack.b;
  }

  void set(CertTrack t) {
    state = t;
    ref.read(sharedPreferencesProvider)?.setString(_key, t.name);
  }
}

/// The exam date the cadet plans for: their own choice, else the next exam on
/// the unit calendar, else null.
final examDateProvider = NotifierProvider<ExamDateController, DateTime?>(ExamDateController.new);

class ExamDateController extends Notifier<DateTime?> {
  static const _key = 'exam_date';

  @override
  DateTime? build() {
    final saved = ref.read(sharedPreferencesProvider)?.getString(_key);
    if (saved != null) return DateTime.tryParse(saved);
    return ref.watch(nextExamProvider)?.startsAt;
  }

  void set(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    state = day;
    ref.read(sharedPreferencesProvider)?.setString(_key, day.toIso8601String());
  }
}

/// Plan items ticked off, keyed "yyyy-mm-dd|item".
/// Chapters the cadet has marked as studied ("book|code"), kept on the phone.
final studiedChaptersProvider = NotifierProvider<StudiedChaptersController, Set<String>>(StudiedChaptersController.new);

class StudiedChaptersController extends Notifier<Set<String>> {
  static const _key = 'chapters_studied';

  @override
  Set<String> build() => (ref.read(sharedPreferencesProvider)?.getStringList(_key) ?? const []).toSet();

  void toggle(String id) {
    final next = {...state};
    if (!next.remove(id)) next.add(id);
    state = next;
    ref.read(sharedPreferencesProvider)?.setStringList(_key, next.toList());
  }
}

final planProgressProvider = NotifierProvider<PlanProgressController, Set<String>>(PlanProgressController.new);

class PlanProgressController extends Notifier<Set<String>> {
  static const _key = 'plan_done';

  @override
  Set<String> build() => (ref.read(sharedPreferencesProvider)?.getStringList(_key) ?? const []).toSet();

  void toggle(String id) {
    final next = {...state};
    if (!next.remove(id)) next.add(id);
    state = next;
    ref.read(sharedPreferencesProvider)?.setStringList(_key, next.toList());
  }
}

/// Signed links to figure files, fetched in batches and kept for the session.
final figureUrlsProvider = NotifierProvider<FigureUrlsController, Map<String, String>>(FigureUrlsController.new);

class FigureUrlsController extends Notifier<Map<String, String>> {
  final _pending = <String>{};

  @override
  Map<String, String> build() {
    ref.watch(unitRepositoryProvider);
    return const {};
  }

  Future<void> ensure(List<String> paths) async {
    final repo = ref.read(unitRepositoryProvider);
    final missing = [for (final p in paths) if (!state.containsKey(p) && !_pending.contains(p)) p];
    if (repo == null || missing.isEmpty) return;
    _pending.addAll(missing);
    try {
      final urls = await repo.figureUrls(missing);
      if (ref.mounted) state = {...state, ...urls};
    } catch (_) {
      // Leave them missing; the figure shows a placeholder.
    } finally {
      _pending.removeAll(missing);
    }
  }
}
