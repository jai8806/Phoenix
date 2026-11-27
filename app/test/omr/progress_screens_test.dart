import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phoenix/app.dart';
import 'package:phoenix/core/router/app_router.dart';
import 'package:phoenix/data/models/test.dart';
import 'package:phoenix/data/precis_pack.dart';
import 'package:phoenix/data/providers.dart';
import 'package:phoenix/domain/omr/progress.dart';

import '../live_mode_test.dart' show FakeUnitRepo, LiveAuth, ano, cadet, now;

AttemptHistory mock(String id, String name, DateTime at, {required int wt, required int mr, double score = 0}) => AttemptHistory(
      testId: 'm${at.day}',
      testTitle: 'Mock ${at.day}',
      cadetId: id,
      cadetName: name,
      score: score,
      submittedAt: at,
      pattern: 'bcert',
      marking: const MarkingScheme(correct: 2, wrong: 0.5),
      answers: [
        for (var i = 0; i < 10; i++)
          AnsweredQuestion(Question(id: 'wt$i', subject: 'Weapon Training', prompt: '?', options: const ['a', 'b', 'c', 'd'], correctIndex: 0), i < wt ? 0 : 1),
        for (var i = 0; i < 10; i++)
          AnsweredQuestion(Question(id: 'mr$i', subject: 'MR III', prompt: '?', options: const ['a', 'b', 'c', 'd'], correctIndex: 0), i < mr ? 0 : 1),
      ],
    );

Future<ProviderContainer> pump(WidgetTester tester, user, FakeUnitRepo repo) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(LiveAuth(user)),
    initialUserProvider.overrideWithValue(user),
    unitRepositoryFactoryProvider.overrideWithValue((_) => repo),
    clockProvider.overrideWithValue(() => now),
    precisPackStoreProvider.overrideWithValue(MemoryPrecisPackStore()),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const PhoenixApp()));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  final repo = FakeUnitRepo()
    ..history.addAll([
      mock('u1', 'Meera Nair', DateTime(2026, 11, 1), wt: 5, mr: 2, score: 8),
      mock('u1', 'Meera Nair', DateTime(2026, 11, 20), wt: 9, mr: 6, score: 26),
      mock('u9', 'Arjun Rao', DateTime(2026, 11, 20), wt: 8, mr: 1, score: 10),
    ]);

  testWidgets('a cadet sees scores over time, weak subjects and whether they would pass', (tester) async {
    final c = await pump(tester, cadet, repo);
    c.read(routerProvider).push(Routes.progress);
    await tester.pumpAndSettle();
    expect(find.textContaining('2 tests'), findsOneWidget);
    expect(find.text('WOULD YOU PASS TODAY?'), findsOneWidget);
    expect(find.text('Map Reading'), findsOneWidget); // précis "MR III" questions count as Map Reading
    expect(find.text('40%'), findsOneWidget); // Map Reading: 8 of 20
    expect(find.textContaining('24 marks in the paper'), findsOneWidget);
  });

  testWidgets('the ANO sees who is at risk and the cadet-by-subject heatmap', (tester) async {
    final c = await pump(tester, ano, repo);
    c.read(routerProvider).push(Routes.unitPerformance);
    await tester.pumpAndSettle();
    expect(find.textContaining('3 attempts by 2 cadets'), findsOneWidget);
    expect(find.text('Arjun Rao'), findsWidgets); // failing Paper IV in the latest mock
    expect(find.textContaining('SPECIALISED SUBJECTS'), findsOneWidget);
    expect(find.text('CADET BY SUBJECT'), findsOneWidget);
  });
}
