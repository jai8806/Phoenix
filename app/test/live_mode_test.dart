import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phoenix/app.dart';
import 'package:phoenix/core/router/app_router.dart';
import 'package:phoenix/data/auth_repository.dart';
import 'package:phoenix/data/models/comms.dart';
import 'package:phoenix/data/models/diary.dart';
import 'package:phoenix/data/models/test.dart';
import 'package:phoenix/data/models/user.dart';
import 'package:phoenix/data/models/ustaad.dart';
import 'package:phoenix/data/providers.dart';
import 'package:phoenix/data/unit_repository.dart';
import 'package:phoenix/features/cadet/diary_entry_screen.dart';

final now = DateTime(2026, 11, 26, 9);

class FakeUnitRepo implements UnitRepository {
  final announcementsList = <Announcement>[
    Announcement(id: 'x1', title: 'Real unit notice', body: 'From the database', author: 'Lt Real', createdAt: now),
  ];
  final eventsList = <CalendarEvent>[];
  final diaryList = <DiaryEntry>[];
  final bank = <Question>[];
  final queue = <ReviewItem>[
    const ReviewItem(id: 'r1', prompt: 'Who is the Supreme Commander?', options: ['PM', 'President', 'CDS', 'RM'],
        source: 'Special Subject (Army) JD/JW (2025) · AF I · Q1', page: 12),
  ];
  final approvals = <(String, int)>[];
  bool failAnnouncements = false;
  bool failPost = false;

  @override
  Future<List<Announcement>> announcements() async {
    if (failAnnouncements) throw const UnitDataFailure("Couldn't load announcements. Check your connection and try again.");
    return List.of(announcementsList);
  }

  @override
  Future<void> postAnnouncement({required String title, required String body, bool pinned = false}) async {
    if (failPost) throw const UnitDataFailure("You don't have permission to post the announcement.");
    announcementsList.insert(0, Announcement(id: 'n', title: title, body: body, author: 'Me', createdAt: now));
  }

  @override
  Future<List<CalendarEvent>> events() async => List.of(eventsList);

  @override
  Future<void> addEvent(CalendarEvent event) async => eventsList.add(event);

  @override
  Future<List<DiaryEntry>> diary() async => List.of(diaryList);

  @override
  Future<void> addDiaryEntry(DiaryEntry entry) async => diaryList.insert(0, entry);

  @override
  Future<List<Question>> approvedQuestions() async => List.of(bank);

  @override
  Future<List<ReviewItem>> reviewQueue() async => List.of(queue);

  @override
  Future<void> approveQuestion(String id, int answer) async {
    approvals.add((id, answer));
    final item = queue.firstWhere((q) => q.id == id);
    queue.remove(item);
    bank.add(Question(id: 'a$id', subject: 'AF I', prompt: item.prompt, options: item.options, correctIndex: answer));
  }

  @override
  Future<List<KnowledgeDocument>> documents() async => const [];

  @override
  Future<UstaadReply> askUstaad(String question) async => const UstaadReply(
        answer: 'The President of India is the Supreme Commander [1].',
        covered: true,
        sources: [UstaadSource(n: 1, title: 'Special Subject (Army) JD/JW (2025)', heading: 'AF I · Introduction', pages: '2')],
      );
}

class LiveAuth implements AuthRepository {
  LiveAuth(this.user);
  final AppUser user;
  @override
  bool get isDemo => false;
  @override
  Stream<AppUser> get externalSignIns => const Stream.empty();
  @override
  Future<AppUser?> restoreSession() async => user;
  @override
  Future<AppUser> signInAs(AppRole role) => throw UnsupportedError('');
  @override
  Future<AppUser> signInWithPassword({required String email, required String password}) async => user;
  @override
  Future<AppUser?> signUp({required String email, required String password, required String fullName}) async => user;
  @override
  Future<AppUser> joinUnit(String code) async => user;
  @override
  Future<void> signOut() async {}
}

const cadet = AppUser(id: 'u1', fullName: 'Meera Nair', role: AppRole.cadet, wing: Wing.army,
    division: Division.sd, unitName: 'Test Unit', unitId: 'unit-1');
const ano = AppUser(id: 'u2', fullName: 'Kavitha Iyer', role: AppRole.ano, rank: 'Lt',
    unitName: 'Test Unit', unitId: 'unit-1');

Future<(ProviderContainer, FakeUnitRepo)> pumpLive(WidgetTester tester, AppUser user,
    {FakeUnitRepo? repo, Size size = const Size(420, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = repo ?? FakeUnitRepo();
  final c = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(LiveAuth(user)),
    initialUserProvider.overrideWithValue(user),
    unitRepositoryFactoryProvider.overrideWithValue((_) => fake),
    clockProvider.overrideWithValue(() => now),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const PhoenixApp()));
  await tester.pumpAndSettle();
  return (c, fake);
}

void main() {
  testWidgets('live cadet sees the unit\'s real announcements, not samples', (tester) async {
    final (c, _) = await pumpLive(tester, cadet);
    expect(c.read(isLiveProvider), isTrue);
    expect(find.text('Real unit notice'), findsOneWidget);
    expect(find.textContaining('uniform check'), findsNothing); // sample announcement
    expect(find.text('B CERTIFICATE EXAM'), findsNothing); // no sample exam countdown
  });

  testWidgets('sample users never touch the backend, even with one configured', (tester) async {
    final (c, _) = await pumpLive(tester, cadet.copyForTest(isSample: true));
    expect(c.read(isLiveProvider), isFalse);
    expect(find.text('Real unit notice'), findsNothing);
  });

  testWidgets('a failed load shows a banner with retry', (tester) async {
    final repo = FakeUnitRepo()..failAnnouncements = true;
    await pumpLive(tester, cadet, repo: repo);
    expect(find.text("Couldn't load announcements. Check your connection and try again."), findsOneWidget);
    repo.failAnnouncements = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Real unit notice'), findsOneWidget);
  });

  testWidgets('ANO posting goes to the backend; a refusal is shown in the dialog', (tester) async {
    final (c, repo) = await pumpLive(tester, ano, size: const Size(1280, 900));
    c.read(routerProvider).go(Routes.commandAnnouncements);
    await tester.pumpAndSettle();

    Finder inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);
    Future<void> compose(String title) async {
      await tester.tap(find.text('Post announcement'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Title'), title);
      await tester.enterText(find.widgetWithText(TextField, 'Message'), 'Body');
      await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Post announcement')));
      await tester.pumpAndSettle();
    }

    repo.failPost = true;
    await compose('Will fail');
    expect(find.text("You don't have permission to post the announcement."), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget); // stays open so nothing is lost
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    repo.failPost = false;
    await compose('Parade moved to 0800');
    expect(repo.announcementsList.first.title, 'Parade moved to 0800');
    expect(find.text('Parade moved to 0800'), findsOneWidget);
  });

  testWidgets('diary sessions are saved to the backend', (tester) async {
    final (c, repo) = await pumpLive(tester, cadet);
    c.read(routerProvider).push(Routes.newDiaryEntry);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Score'), '47');
    await tester.scrollUntilVisible(find.text('Save session'), 300,
        scrollable: find.descendant(of: find.byType(DiaryEntryScreen), matching: find.byType(Scrollable)).first);
    await tester.tap(find.text('Save session'));
    await tester.pumpAndSettle();
    expect(repo.diaryList.single.shooting?.score, 47);
    expect(c.read(diaryProvider).single.shooting?.score, 47);
  });

  testWidgets('Ustaad answers live with its sources', (tester) async {
    await pumpLive(tester, cadet);
    await tester.tap(find.text('Ustaad'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Ask a question'), 'Who is the supreme commander?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('The President of India is the Supreme Commander [1].'), findsOneWidget);
    expect(find.text('[1] Special Subject (Army) JD/JW (2025) · AF I · Introduction · p. 2'), findsOneWidget);
  });

  testWidgets('ANO approves a précis question and it joins the practice bank', (tester) async {
    final (c, repo) = await pumpLive(tester, ano, size: const Size(1280, 900));
    expect(c.read(questionBankProvider), isEmpty);
    c.read(routerProvider).push(Routes.review);
    await tester.pumpAndSettle();
    expect(find.text('Who is the Supreme Commander?'), findsOneWidget);
    expect(find.text('Special Subject (Army) JD/JW (2025) · AF I · Q1 · p. 12'), findsOneWidget);
    // Approve is disabled until an answer is picked.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Approve answer')).onPressed, isNull);
    await tester.tap(find.text('President'));
    await tester.pump();
    await tester.tap(find.text('Approve answer'));
    await tester.pumpAndSettle();
    expect(repo.approvals, [('r1', 1)]);
    expect(find.text('All caught up'), findsOneWidget);
    expect(c.read(questionBankProvider).single.correctIndex, 1);
  });

  testWidgets('cadets cannot open the review screen', (tester) async {
    final (c, _) = await pumpLive(tester, cadet);
    c.read(routerProvider).go(Routes.review);
    await tester.pumpAndSettle();
    expect(c.read(routerProvider).state.matchedLocation, Routes.today);
  });

  group('row mapping', () {
    test('diary entries round-trip through database rows', () {
      final e = DiaryEntry(
        id: 'd1',
        type: SessionType.shooting,
        date: DateTime(2026, 3, 7, 18, 30),
        durationMinutes: 45,
        toImprove: 'Trigger control',
        mood: 4,
        sleepHours: 6.5,
        sharedWithUnit: true,
        shooting: const ShootingMetrics(rifle: '.22', position: ShootingPosition.kneeling, distanceMetres: 25,
            rounds: 5, score: 41, groupMm: 12.5),
      );
      final row = diaryToRow(e);
      expect(row['happened_on'], '2026-03-07');
      expect(row['session_type'], 'shooting');
      expect(row['visibility'], 'shared_with_unit');
      final back = diaryFromRow({...row, 'id': 'd1'});
      expect(back.date, DateTime(2026, 3, 7));
      expect(back.shooting!.position, ShootingPosition.kneeling);
      expect(back.shooting!.groupMm, 12.5);
      expect(back.sharedWithUnit, isTrue);
      expect(back.toImprove, 'Trigger control');
      expect(diaryToRow(DiaryEntry(id: 'x', type: SessionType.mapReading, date: DateTime(2026, 1, 2)))['session_type'],
          'map_reading');
    });

    test('announcement author shows rank and name; precis questions show their chapter', () {
      final a = announcementFromRow({
        'id': 'a', 'title': 'T', 'body': 'B', 'pinned': true, 'created_at': '2026-11-26T03:30:00Z',
        'author': {'full_name': 'Kavitha Iyer', 'rank': 'Lt'},
      });
      expect(a.author, 'Lt Kavitha Iyer');
      expect(a.pinned, isTrue);
      final q = questionFromRow({
        'id': 'q', 'subject': 'Special Subject (Army) JD/JW (2025)', 'prompt': 'P?', 'options': ['a', 'b'],
        'correct_index': 1, 'explanation': 'MR IV · Q14',
      });
      expect(q.subject, 'MR IV');
      final r = reviewItemFromRow({
        'id': 'r', 'prompt': 'P?', 'options': ['a', 'b'], 'subject': 'Book', 'explanation': 'AF I · Q3', 'source_page': 12,
      });
      expect(r.source, 'Book · AF I · Q3');
      expect(r.page, 12);
    });

    test('Ustaad replies parse from the function response', () {
      final r = UstaadReply.fromJson({
        'answer': 'A [1]', 'covered': true,
        'sources': [{'n': 1, 'title': 'Book', 'heading': 'AF I · Intro', 'pages': '2–3'}],
      });
      expect(r.sources.single.label, 'Book · AF I · Intro · p. 2–3');
      expect(UstaadReply.fromJson({'answer': 'x'}).covered, isFalse);
    });
  });
}

extension on AppUser {
  AppUser copyForTest({required bool isSample}) => AppUser(
        id: id, fullName: fullName, role: role, rank: rank, wing: wing, division: division,
        unitName: unitName, unitId: unitId, isSample: isSample);
}
