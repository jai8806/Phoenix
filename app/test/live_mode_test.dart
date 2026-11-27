import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phoenix/app.dart';
import 'package:phoenix/core/router/app_router.dart';
import 'package:phoenix/data/auth_repository.dart';
import 'package:phoenix/data/models/comms.dart';
import 'package:phoenix/data/models/diary.dart';
import 'package:phoenix/data/models/figure.dart';
import 'package:phoenix/data/models/test.dart';
import 'package:phoenix/data/models/user.dart';
import 'package:phoenix/data/models/ustaad.dart';
import 'package:phoenix/data/providers.dart';
import 'package:phoenix/data/unit_repository.dart';
import 'package:phoenix/data/precis_pack.dart';
import 'package:phoenix/domain/precis_search.dart';
import 'package:phoenix/domain/omr/progress.dart';
import 'package:phoenix/features/cadet/diary_entry_screen.dart';
import 'package:phoenix/features/cadet/edit_profile_screen.dart';

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
  bool offline = false;
  int aiCalls = 0;

  static const demoPassages = [
    PrecisPassage(id: 1, title: 'Demo Army Book', heading: 'AF I · Introduction', page: 2,
        content: 'The responsibility for national defence rests with the cabinet. '
            'The President of India is the Supreme Commander of the Indian Armed Forces.'),
    PrecisPassage(id: 2, title: 'Demo Map Book', heading: 'MR III · Types of North', page: 185,
        content: 'There are three types of north. (a) True north points to the geographic pole. '
            '(b) Magnetic north is shown by the compass needle. (c) Grid north follows the grid lines.'),
  ];

  static const demoFigures = [
    PrecisFigure(id: 'f1', title: 'Demo Army Book', chapterCode: 'AF I', page: 2, path: 'demo/f1.webp', width: 400, height: 300),
    PrecisFigure(id: 'f2', title: 'Demo Map Book', chapterCode: 'MR III', page: 185, path: 'demo/f2.webp', width: 300, height: 300),
  ];
  final urlRequests = <String>[];

  @override
  Future<List<PrecisFigure>> figures() async => demoFigures;

  @override
  Future<Map<String, String>> figureUrls(List<String> paths) async {
    urlRequests.addAll(paths);
    return const {}; // no network in tests: placeholders are shown
  }

  @override
  Future<List<PrecisPassage>> precisPassages() async {
    if (offline) throw const UnitDataFailure("Couldn't download the study material. Check your connection and try again.");
    return demoPassages;
  }

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

  // Hosted tests --------------------------------------------------------------
  final testsList = <TestDefinition>[];
  final testQs = <String, List<Question>>{};
  final attemptsByTest = <String, List<AttemptRecord>>{};
  final myScores = <String, double>{};
  final submissions = <(String, Map<String, int>)>[];
  bool failSubmit = false;
  final membersList = <AppUser>[cadet, ano];
  final memberUpdates = <(String, AppRole, String?)>[];

  @override
  Future<List<TestDefinition>> tests() async => [
        for (final t in testsList)
          myScores.containsKey(t.id)
              ? t.withMyScore(myScores[t.id]!)
              : t,
      ];

  @override
  Future<List<Question>> testQuestions(String testId) async => testQs[testId] ?? const [];

  @override
  Future<void> createTest(NewTest t) async {
    final id = 'h${testsList.length + 1}';
    testsList.insert(0, TestDefinition(id: id, title: t.title, durationMinutes: t.durationMinutes, marking: t.marking,
        questionIds: t.questionIds, opensAt: t.opensAt, closesAt: t.closesAt));
    testQs[id] = [for (final qid in t.questionIds) bank.firstWhere((q) => q.id == qid)];
  }

  @override
  Future<void> deleteTest(String testId) async => testsList.removeWhere((t) => t.id == testId);

  final uploads = <String, int>{};
  String? lastSetLabel;
  int lastScanFlags = 0;

  @override
  Future<TestDefinition> startTest(TestDefinition test) async {
    final started = test.copyWith(startedAt: now, opensAt: now,
        closesAt: now.add(Duration(minutes: test.durationMinutes + test.uploadMinutes)));
    final i = testsList.indexWhere((t) => t.id == test.id);
    if (i >= 0) testsList[i] = started;
    return started;
  }

  @override
  Future<String> uploadSheet(String testId, Uint8List jpeg) async {
    uploads[testId] = jpeg.length;
    return 'unit-1/$testId/u1.jpg';
  }

  @override
  Future<String?> sheetUrl(String path) async => null;

  final history = <AttemptHistory>[];

  @override
  Future<List<AttemptHistory>> attemptHistory({bool wholeUnit = false}) async =>
      wholeUnit ? List.of(history) : [for (final h in history) if (h.cadetId == 'u1') h];

  @override
  Future<double> submitAttempt(String testId, Map<String, int> answers,
      {int focusLost = 0, String? sheetPath, String? setLabel, int scanFlags = 0, int corrected = 0}) async {
    lastSetLabel = setLabel;
    lastScanFlags = scanFlags;
    if (failSubmit) {
      throw const UnitDataFailure("Couldn't submit your answers. Check your connection and try again; your answers are kept.");
    }
    final t = testsList.firstWhere((t) => t.id == testId);
    final score = scoreTest(questions: testQs[testId]!, answers: answers, marking: t.marking).score;
    submissions.add((testId, answers));
    myScores[testId] = score;
    attemptsByTest.putIfAbsent(testId, () => []).add(
        AttemptRecord(cadetId: 'u1', cadetName: 'Meera Nair', score: score, answers: answers, focusLost: focusLost));
    return score;
  }

  @override
  Future<Map<String, int?>> myAnswers(String testId) async => {
        for (final a in attemptsByTest[testId] ?? const <AttemptRecord>[])
          if (a.cadetId == 'u1') ...a.answers,
      };

  @override
  Future<List<AttemptRecord>> testAttempts(String testId) async => attemptsByTest[testId] ?? const [];

  @override
  Future<List<ScoreRow>> unitScores() async => [
        for (final e in attemptsByTest.entries)
          for (final a in e.value) ScoreRow(testId: e.key, cadetId: a.cadetId, score: a.score),
      ];

  @override
  Future<List<AppUser>> members() async => List.of(membersList);

  @override
  Future<void> updateMember(String id, {required AppRole role, String? rank}) async =>
      memberUpdates.add((id, role, rank));

  @override
  Future<UstaadReply> askUstaad(String question, {List<int> chunkIds = const [], List<String> facts = const []}) async {
    aiCalls++;
    return const UstaadReply(
        answer: 'The President of India is the Supreme Commander [1].',
        covered: true,
        sources: [UstaadSource(n: 1, title: 'Special Subject (Army) JD/JW (2025)', heading: 'AF I · Introduction', pages: '2')],
      );
  }
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
  final profileSaves = <AppUser>[];
  @override
  Future<AppUser> updateProfile(AppUser updated) async {
    profileSaves.add(updated);
    return updated;
  }
  @override
  Future<void> signOut() async {}
}

const cadet = AppUser(id: 'u1', fullName: 'Meera Nair', role: AppRole.cadet, wing: Wing.army,
    division: Division.sd, unitName: 'Test Unit', unitId: 'unit-1');
const ano = AppUser(id: 'u2', fullName: 'Kavitha Iyer', role: AppRole.ano, rank: 'Lt',
    unitName: 'Test Unit', unitId: 'unit-1');

Future<(ProviderContainer, FakeUnitRepo)> pumpLive(WidgetTester tester, AppUser user,
    {FakeUnitRepo? repo, Size size = const Size(420, 900), PrecisPackStore? store}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = repo ?? FakeUnitRepo();
  final c = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(LiveAuth(user)),
    initialUserProvider.overrideWithValue(user),
    unitRepositoryFactoryProvider.overrideWithValue((_) => fake),
    clockProvider.overrideWithValue(() => now),
    precisPackStoreProvider.overrideWithValue(store ?? MemoryPrecisPackStore()),
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

  Future<void> ask(WidgetTester tester, String q) async {
    await tester.enterText(find.widgetWithText(TextField, 'Ask a question'), q);
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
  }

  testWidgets('Ustaad answers from the précis without AI; Explain simply calls the AI', (tester) async {
    final (c, repo) = await pumpLive(tester, cadet);
    await tester.tap(find.text('Ustaad'));
    await tester.pumpAndSettle();
    expect(find.text('Offline ready'), findsOneWidget);

    await ask(tester, 'Who is the supreme commander?');
    expect(find.text('FROM YOUR PRÉCIS'), findsOneWidget);
    expect(find.text('The President of India is the Supreme Commander of the Indian Armed Forces.'), findsOneWidget);
    expect(find.text('Demo Army Book · AF I · Introduction · p. 2'), findsWidgets);
    expect(repo.aiCalls, 0); // no AI for the main answer

    await tester.tap(find.text('Explain simply'));
    await tester.pumpAndSettle();
    expect(repo.aiCalls, 1);
    expect(find.text('AI EXPLANATION'), findsOneWidget);
    expect(find.text('[1] Special Subject (Army) JD/JW (2025) · AF I · Introduction · p. 2'), findsOneWidget);
    expect(c.read(precisPackStoreProvider), isA<MemoryPrecisPackStore>());
  });

  testWidgets('Ustaad says plainly when the précis does not cover a question', (tester) async {
    await pumpLive(tester, cadet);
    await tester.tap(find.text('Ustaad'));
    await tester.pumpAndSettle();
    await ask(tester, 'who won the football league');
    expect(find.textContaining("isn't in your précis"), findsOneWidget);
  });

  testWidgets('offline, Ustaad answers from the copy saved on the phone', (tester) async {
    final store = MemoryPrecisPackStore()..saved = FakeUnitRepo.demoPassages;
    await pumpLive(tester, cadet, repo: FakeUnitRepo()..offline = true, store: store);
    await tester.tap(find.text('Ustaad'));
    await tester.pumpAndSettle();
    await ask(tester, 'what is magnetic north');
    expect(find.text('(b)'), findsOneWidget); // the list marker, shown on its own
    expect(find.textContaining('Magnetic north is shown by the compass needle.', findRichText: true), findsOneWidget);
  });

  testWidgets('first launch offline explains the download failed and offers retry', (tester) async {
    final repo = FakeUnitRepo()..offline = true;
    await pumpLive(tester, cadet, repo: repo);
    await tester.tap(find.text('Ustaad'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't download the study material. Check your connection and try again."), findsOneWidget);
    repo.offline = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Offline ready'), findsOneWidget);
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

  testWidgets('Ustaad shows figures from the pages it quotes, and asks for their links', (tester) async {
    final (c, repo) = await pumpLive(tester, cadet);
    await tester.tap(find.text('Ustaad'));
    await tester.pumpAndSettle();
    await ask(tester, 'what is magnetic north');
    expect(find.bySemanticsLabel('Figure from MR III, page 185'), findsOneWidget);
    expect(repo.urlRequests, contains('demo/f2.webp'));
    expect(c.read(precisProvider).figures, hasLength(2));
  });

  testWidgets('signing out deletes the précis saved on the phone', (tester) async {
    final store = MemoryPrecisPackStore();
    final (c, _) = await pumpLive(tester, cadet, store: store);
    await tester.tap(find.text('Ustaad'));
    await tester.pumpAndSettle();
    expect(store.saved, isNotEmpty);
    expect(store.savedFigures, isNotEmpty);
    await c.read(authControllerProvider.notifier).signOut();
    await tester.pumpAndSettle();
    expect(store.saved, isNull);
    expect(store.savedFigures, isEmpty);
  });

  List<Question> wtBank(int n) => [
        for (var i = 0; i < n; i++)
          Question(id: 'b$i', subject: i.isEven ? 'Weapon Training' : 'Leadership', prompt: 'Question $i?',
              options: const ['Alpha', 'Bravo', 'Charlie', 'Delta'], correctIndex: 0),
      ];

  testWidgets('ANO hosts a test from approved questions and sees it listed', (tester) async {
    final repo = FakeUnitRepo()..bank.addAll(wtBank(30));
    final (c, _) = await pumpLive(tester, ano, repo: repo, size: const Size(1280, 1000));
    c.read(routerProvider).go(Routes.tests);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New test'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Test name'), 'Weekly test 1');
    await tester.tap(find.text('In-app test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chosen subjects'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weapon Training · 15'));
    await tester.enterText(find.widgetWithText(TextField, 'Questions'), '10');
    await tester.tap(find.text('Create test'));
    await tester.pumpAndSettle();
    final created = repo.testsList.single;
    expect(created.title, 'Weekly test 1');
    expect(created.questionIds, hasLength(10));
    expect(repo.testQs['h1']!.every((q) => q.subject == 'Weapon Training'), isTrue);
    expect(created.marking.wrong, 0.5); // B Cert negative marking by default
    expect(created.closesAt, now.add(const Duration(days: 7)));
    expect(find.text('Weekly test 1'), findsOneWidget);
  });

  Future<FakeUnitRepo> repoWithTest() async {
    final repo = FakeUnitRepo()..bank.addAll(wtBank(4));
    await repo.createTest(NewTest(title: 'Unit test 1', durationMinutes: 10, marking: const MarkingScheme(wrong: 0.5),
        questionIds: const ['b0', 'b1', 'b2'], opensAt: now.subtract(const Duration(hours: 1)),
        closesAt: now.add(const Duration(days: 2))));
    return repo;
  }

  Future<void> answerAll(WidgetTester tester, List<String> picks) async {
    for (final (i, pick) in picks.indexed) {
      await tester.tap(find.text(pick));
      await tester.pump();
      await tester.tap(find.text(i == picks.length - 1 ? 'Submit test' : 'Next question'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('cadet takes a hosted test once; the server marks it and the key stays locked', (tester) async {
    final repo = await repoWithTest();
    final (c, _) = await pumpLive(tester, cadet, repo: repo);
    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();
    expect(c.read(testsProvider).single.title, 'Unit test 1');
    c.read(routerProvider).push(Routes.quiz('h1'));
    await tester.pumpAndSettle();
    await answerAll(tester, ['Alpha', 'Bravo', 'Alpha']); // 2 right, 1 wrong: 2 + 2 - 0.5
    expect(repo.submissions.single.$2.length, 3);
    expect(find.text('3.5 / 6'), findsOneWidget);
    expect(find.text('REVIEW ANSWERS'), findsNothing);
    expect(find.textContaining('answer key unlocks'), findsOneWidget);
    expect(c.read(testsProvider).single.myScore, 3.5);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    c.read(routerProvider).push(Routes.quiz('h1'));
    await tester.pumpAndSettle();
    expect(find.text('Submitted'), findsOneWidget); // no second attempt
  });

  testWidgets('a failed submission keeps the answers and can be sent again', (tester) async {
    final repo = (await repoWithTest())..failSubmit = true;
    final (c, _) = await pumpLive(tester, cadet, repo: repo);
    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();
    c.read(routerProvider).push(Routes.quiz('h1'));
    await tester.pumpAndSettle();
    await answerAll(tester, ['Alpha', 'Alpha', 'Alpha']);
    expect(find.text('Not submitted yet'), findsOneWidget);
    repo.failSubmit = false;
    await tester.tap(find.text('Submit again'));
    await tester.pumpAndSettle();
    expect(find.text('6 / 6'), findsOneWidget);
  });

  testWidgets('after the test closes, the cadet can review their answers', (tester) async {
    final repo = await repoWithTest();
    await repo.submitAttempt('h1', {'b0': 0, 'b1': 2});
    final closed = repo.testsList.single;
    repo.testsList[0] = TestDefinition(id: closed.id, title: closed.title, durationMinutes: 10,
        marking: closed.marking, questionIds: closed.questionIds, opensAt: closed.opensAt,
        closesAt: now.subtract(const Duration(minutes: 1)));
    final (c, _) = await pumpLive(tester, cadet, repo: repo, size: const Size(420, 2400));
    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();
    c.read(routerProvider).push(Routes.quiz('h1'));
    await tester.pumpAndSettle();
    expect(find.text('1.5 / 6'), findsOneWidget);
    expect(find.text('REVIEW ANSWERS'), findsOneWidget);
    expect(find.text('You chose: Charlie'), findsOneWidget);
  });

  testWidgets('ANO sees who submitted, scores and weak subjects', (tester) async {
    final repo = await repoWithTest();
    await repo.submitAttempt('h1', {'b0': 0, 'b1': 3, 'b2': 0});
    final (c, _) = await pumpLive(tester, ano, repo: repo, size: const Size(1280, 2400));
    c.read(routerProvider).push(Routes.testResults('h1'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget); // submitted / cadets
    expect(find.text('58%'), findsWidgets); // 3.5 of 6
    expect(find.text('Meera Nair'), findsOneWidget);
    expect(find.text('WEAK SUBJECTS ACROSS THE UNIT'), findsOneWidget);
    expect(find.text('0% right'), findsOneWidget); // the Leadership question
  });

  testWidgets('ANO promotes a cadet to senior cadet from the roster', (tester) async {
    final (c, repo) = await pumpLive(tester, ano, size: const Size(1280, 1000));
    c.read(routerProvider).go(Routes.cadets);
    await tester.pumpAndSettle();
    expect(find.text('Sample roster'), findsNothing);
    await tester.tap(find.text('Meera Nair'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JUO'));
    await tester.tap(find.text('Senior cadet'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(repo.memberUpdates.single, ('u1', AppRole.seniorCadet, 'JUO'));
    expect(find.text('JUO Meera Nair'), findsOneWidget);
  });

  testWidgets('cadet edits their own profile', (tester) async {
    final auth = LiveAuth(cadet);
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      initialUserProvider.overrideWithValue(cadet),
      unitRepositoryFactoryProvider.overrideWithValue((_) => FakeUnitRepo()),
      clockProvider.overrideWithValue(() => now),
      precisPackStoreProvider.overrideWithValue(MemoryPrecisPackStore()),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const PhoenixApp()));
    await tester.pumpAndSettle();
    c.read(routerProvider).push(Routes.editProfile);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Regimental number'), 'ka2024sda0001');
    await tester.tap(find.text('CPL'));
    await tester.tap(find.text('2nd year'));
    await tester.scrollUntilVisible(find.text('Save profile'), 200,
        scrollable: find.descendant(of: find.byType(EditProfileScreen), matching: find.byType(Scrollable)).first);
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    final saved = auth.profileSaves.single;
    expect(saved.regimentalNo, 'KA2024SDA0001');
    expect(saved.rank, 'CPL');
    expect(saved.trainingYear, 2);
    expect(saved.role, AppRole.cadet);
    expect(c.read(authControllerProvider)!.displayName, 'CPL Meera Nair');
  });

  testWidgets('a chapter code shared by two books shows only its own book and figures', (tester) async {
    final repo = _TwoBooksRepo();
    final (c, _) = await pumpLive(tester, cadet, repo: repo, size: const Size(420, 1600));
    await tester.tap(find.text('Ustaad'));
    await tester.pumpAndSettle(); // downloads the précis
    expect(c.read(precisProvider).books, containsAll(['Demo Army Book', 'Army SD/SW (Oct 2025)']));
    expect(c.read(precisProvider).figuresFor('AF I', book: 'Army SD/SW (Oct 2025)').single.id, 'f9');

    c.read(routerProvider).push(Routes.book('Army SD/SW (Oct 2025)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Armed Forces Revised'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Commands of the Army', findRichText: true), findsWidgets);
    expect(find.textContaining('responsibility for national defence', findRichText: true), findsNothing);
    expect(find.bySemanticsLabel('Figure from AF I, page 4'), findsOneWidget); // inline, in its section
    expect(find.text('IN 30 SECONDS'), findsOneWidget);
    expect(find.text('Mark as studied'), findsOneWidget);
  });

  testWidgets('quick facts answer what the précis gets wrong, with when they were checked', (tester) async {
    await pumpLive(tester, cadet, size: const Size(420, 1400));
    await tester.tap(find.text('Ustaad'));
    await tester.pumpAndSettle();
    await ask(tester, 'who is dg ncc');
    expect(find.text('QUICK FACT'), findsOneWidget);
    expect(find.textContaining('Lt Gen Virendra Vats', findRichText: true), findsOneWidget);
    expect(find.textContaining('checked Nov 2026'), findsOneWidget);
  });

  testWidgets('Explain simply sends the passages already shown, and renders bullets and bold', (tester) async {
    final repo = _ExplainRepo();
    await pumpLive(tester, cadet, repo: repo, size: const Size(420, 1600));
    await tester.tap(find.text('Ustaad'));
    await tester.pumpAndSettle();
    await ask(tester, 'what is magnetic north');
    await tester.tap(find.text('Explain simply'));
    await tester.pumpAndSettle();
    expect(repo.lastChunkIds, contains(2));
    expect(find.text('•'), findsWidgets);
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('Magnetic north', findRichText: true), findsWidgets);
  });

  group('row mapping', () {
    test('tests and attempts map from database rows', () {
      final t = testFromRow({
        'id': 't', 'title': 'Weekly', 'description': null, 'duration_minutes': 30, 'marks_correct': 2,
        'marks_wrong': 0.5, 'opens_at': '2026-11-26T03:30:00Z', 'closes_at': null,
        'test_questions': [{'question_id': 'q2', 'position': 1}, {'question_id': 'q1', 'position': 0}],
        'test_attempts': [{'count': 12}],
      }, myScore: 7);
      expect(t.questionIds, ['q1', 'q2']);
      expect(t.attemptCount, 12);
      expect(t.maxScore, 4);
      expect(t.marking.wrong, 0.5);
      expect(t.attempted, isTrue);
      final a = attemptFromRow({
        'cadet_id': 'u', 'score': 3.5, 'submitted_at': '2026-11-26T04:00:00Z', 'focus_lost_count': 2,
        'profiles': {'full_name': 'Meera Nair', 'rank': 'CDT'},
        'attempt_answers': [{'question_id': 'q1', 'chosen_index': 2}, {'question_id': 'q2', 'chosen_index': null}],
      });
      expect(a.cadetName, 'CDT Meera Nair');
      expect(a.answers, {'q1': 2, 'q2': null});
      expect(a.focusLost, 2);
    });

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

    test('Ustaad errors explain what to do', () {
      expect(ustaadErrorMessage(404, {'code': 'NOT_FOUND'}), contains('Ask your ANO to set it up'));
      expect(ustaadErrorMessage(429, {'error': 'Ustaad is busy right now.'}), 'Ustaad is busy right now.');
      expect(ustaadErrorMessage(401, null), contains('sign in again'));
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

class _TwoBooksRepo extends FakeUnitRepo {
  @override
  Future<List<PrecisPassage>> precisPassages() async => [
        ...FakeUnitRepo.demoPassages,
        const PrecisPassage(id: 9, title: 'Army SD/SW (Oct 2025)', heading: 'AF I · Armed Forces Revised', page: 4,
            content: 'Commands of the Army are headed by an Army Commander.'),
      ];

  @override
  Future<List<PrecisFigure>> figures() async => [
        ...FakeUnitRepo.demoFigures,
        const PrecisFigure(id: 'f9', title: 'Army SD/SW (Oct 2025)', chapterCode: 'AF I', page: 4, path: 'x/f9.webp'),
      ];
}

class _ExplainRepo extends FakeUnitRepo {
  List<int> lastChunkIds = const [];

  @override
  Future<UstaadReply> askUstaad(String question, {List<int> chunkIds = const [], List<String> facts = const []}) async {
    lastChunkIds = chunkIds;
    return const UstaadReply(
      answer: '**Magnetic north** is where a compass needle points [1].\n- It moves slowly over time\n  * nested point\nRemember: compass = magnetic.',
      covered: true,
      sources: [UstaadSource(n: 1, title: 'Demo Map Book', heading: 'MR III · Types of North', pages: '185')],
    );
  }
}
