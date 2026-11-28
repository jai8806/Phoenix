// Screenshots of the OMR screens: PREVIEW=1 flutter test test/omr/omr_preview_test.dart --update-goldens
import 'dart:math' as math;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoenix/app.dart';
import 'package:phoenix/core/router/app_router.dart';
import 'package:phoenix/data/models/test.dart';
import 'package:phoenix/data/precis_pack.dart';
import 'package:phoenix/data/providers.dart';
import 'package:phoenix/domain/omr/exam_pattern.dart';
import 'package:phoenix/domain/omr/exam_session.dart';
import 'package:phoenix/domain/omr/omr_layout.dart';
import 'package:phoenix/features/omr/exam_screen.dart';

import '../live_mode_test.dart' show FakeUnitRepo, LiveAuth, cadet, now;
import 'synthetic_sheet.dart';

Future<void> _font(String family, String path) async {
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  await loader.load();
}

Future<void> shot(WidgetTester tester, String name) =>
    expectLater(find.byType(PhoenixApp), matchesGoldenFile('../preview/omr_$name.png'));

List<Question> examBank() => [
      for (final p in bCertPattern.papers)
        for (final s in p.sections)
          for (var i = 0; i < s.count + 2; i++)
            Question(id: '${s.subject}-$i', subject: s.subject, prompt: '${s.subject} question $i?',
                options: const ['w', 'x', 'y', 'z'], correctIndex: i % 4),
    ];

void main() {
  testWidgets('OMR screens preview', (tester) async {
    await tester.runAsync(() async {
      await _font('Inter', 'assets/fonts/Inter.ttf');
      await _font('BarlowCondensed', 'assets/fonts/BarlowCondensed-Bold.ttf');
      await _font('MaterialIcons', '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    });
    final repo = FakeUnitRepo()..bank.addAll(examBank());
    final pick = pickForPattern(bCertPattern, repo.bank, rng: math.Random(3));
    final entries = pick.byNumber.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    await repo.createTest(NewTest(
      title: 'B Cert mock 1', durationMinutes: 180, marking: bCertPattern.marking,
      questionIds: [for (final e in entries) e.value], numbers: [for (final e in entries) e.key],
      mode: TestMode.omr, pattern: 'bcert', sheetCode: 4242, setSeed: 99, uploadMinutes: 20,
    ));
    // testsList stores TestDefinition without numbers/mode: rebuild it as the database would return it.
    final created = repo.testsList.single;
    repo.testsList[0] = TestDefinition(
      id: created.id, title: created.title, durationMinutes: 180, marking: bCertPattern.marking,
      questionIds: [for (final e in entries) e.value], numbers: [for (final e in entries) e.key],
      mode: TestMode.omr, pattern: 'bcert', sheetCode: 4242, setSeed: 99, uploadMinutes: 20,
    );

    // The photo the cadet takes: every question answered correctly for their set, but Q2 smudged.
    final set = setFor(cadet.id, created.id);
    final byId = {for (final q in repo.bank) q.id: q};
    final paper = paperFor(repo.testsList.single, byId, set);
    final marks = {for (final item in paper) item.number: [item.question.correctIndex]};
    final firstNumber = paper.first.number;
    marks[firstNumber] = [paper.first.question.correctIndex, (paper.first.question.correctIndex + 1) % 4]; // double mark
    late Uint8List photo;
    await tester.runAsync(() async {
      final layout = OmrLayout.forPattern(bCertPattern);
      photo = photograph(drawSheet(layout, marks, code: 4242, set: set, rng: math.Random(5)), rng: math.Random(6));
    });

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(LiveAuth(cadet)),
      initialUserProvider.overrideWithValue(cadet),
      unitRepositoryFactoryProvider.overrideWithValue((_) => repo),
      clockProvider.overrideWithValue(() => now),
      precisPackStoreProvider.overrideWithValue(MemoryPrecisPackStore()),
      sheetPhotoSourceProvider.overrideWithValue((_) async => photo),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const PhoenixApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();
    expect(c.read(testsProvider).single.isOmr, isTrue);

    c.read(routerProvider).push(Routes.exam(created.id));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(set), findsOneWidget); // the lobby shows the cadet's set
    await shot(tester, '1_lobby');
    expect(find.textContaining('Waiting for your ANO'), findsOneWidget);

    // The ANO starts it; the cadet's phone picks it up.
    await repo.startTest(repo.testsList.single.copyWith(startedAt: DateTime.now()));
    repo.testsList[0] = repo.testsList.single.copyWith(startedAt: DateTime.now(), closesAt: DateTime.now().add(const Duration(minutes: 200)));
    await c.read(testsProvider.notifier).reload();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('$firstNumber. ${paper.first.question.prompt}'), findsOneWidget);
    expect(find.textContaining('Set $set'), findsWidgets);
    await shot(tester, '2_paper');

    await tester.tap(find.text('Finished · scan my sheet'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Scan my sheet'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Take photo of my sheet'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 6)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Check what was read'), findsOneWidget);
    await shot(tester, '3_review');
    expect(find.textContaining('1 to check'), findsOneWidget);
    // Submit is blocked until the double mark is confirmed.
    await tester.tap(find.text('2×'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Two marked'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Submit answers'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 300));

    final (testId, answers) = repo.submissions.single;
    expect(testId, created.id);
    expect(answers[paper.first.question.id], -1); // double mark counts wrong
    for (final item in paper.skip(1)) {
      expect(answers[item.question.id], item.question.correctIndex, reason: 'question ${item.number}');
    }
    expect(repo.lastSetLabel, set);
    expect(repo.uploads[created.id], greaterThan(10000));
    expect(find.textContaining('Each paper'.toUpperCase()), findsOneWidget);
    expect(find.text('You would pass every paper.'), findsOneWidget);
    await shot(tester, '4_result');
  }, timeout: const Timeout(Duration(minutes: 3)), skip: Platform.environment['PREVIEW'] != '1');
}
