import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phoenix/app.dart';
import 'package:phoenix/core/router/app_router.dart';
import 'package:phoenix/features/cadet/diary_entry_screen.dart';
import 'package:phoenix/data/models/user.dart';
import 'package:phoenix/data/providers.dart';

final _now = DateTime(2026, 11, 26, 9);

/// Pumps the app in demo mode with a frozen clock. Returns the container so
/// tests can inspect state.
Future<ProviderContainer> pumpApp(WidgetTester tester, {Size size = const Size(420, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [clockProvider.overrideWithValue(() => _now)]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const PhoenixApp()));
  await tester.pumpAndSettle();
  return container;
}

Future<void> signInAs(WidgetTester tester, AppRole role) async {
  await tester.tap(find.text('Continue as ${role.label}'));
  await tester.pumpAndSettle();
}

Finder inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

String location(ProviderContainer c) => c.read(routerProvider).state.matchedLocation;

void main() {
  testWidgets('demo sign-in offers all three roles', (tester) async {
    await pumpApp(tester);
    expect(find.text('Demo mode'), findsOneWidget);
    for (final role in AppRole.values) {
      expect(find.text('Continue as ${role.label}'), findsOneWidget);
    }
  });

  testWidgets('cadet lands on Today with countdown and eligibility', (tester) async {
    final c = await pumpApp(tester);
    await signInAs(tester, AppRole.cadet);

    expect(location(c), Routes.today);
    expect(find.text('Good morning, Aarav'), findsOneWidget);
    expect(find.text('81'), findsOneWidget); // days to the B Certificate exam
    expect(find.text('B Certificate eligibility'), findsOneWidget);
    // 61/90 periods: needs 26 more to reach 75% ((61 + 26) / 116 = 0.75).
    expect(find.text('Attend 26 more training periods'), findsOneWidget);
  });

  testWidgets('cadet cannot open the Command Center', (tester) async {
    final c = await pumpApp(tester);
    await signInAs(tester, AppRole.cadet);
    c.read(routerProvider).go(Routes.overview);
    await tester.pumpAndSettle();
    expect(location(c), Routes.today);
  });

  testWidgets('ANO lands on the Command Center overview', (tester) async {
    final c = await pumpApp(tester, size: const Size(1280, 900));
    await signInAs(tester, AppRole.ano);
    expect(location(c), Routes.overview);
    expect(find.text('Exam eligible'), findsOneWidget);
    expect(find.text('Needs attention'.toUpperCase()), findsOneWidget);
  });

  testWidgets('an announcement posted by the ANO reaches cadets', (tester) async {
    final c = await pumpApp(tester, size: const Size(1280, 900));
    await signInAs(tester, AppRole.ano);
    c.read(routerProvider).go(Routes.commandAnnouncements);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Post announcement'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Parade cancelled');
    await tester.enterText(find.widgetWithText(TextField, 'Message'), 'Rain. See you next week.');
    await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Post announcement')));
    await tester.pumpAndSettle();

    expect(c.read(announcementsProvider).first.title, 'Parade cancelled');
    expect(find.text('Parade cancelled'), findsOneWidget);
  });

  testWidgets('posting without a message shows an error and keeps the dialog', (tester) async {
    final c = await pumpApp(tester, size: const Size(1280, 900));
    await signInAs(tester, AppRole.ano);
    c.read(routerProvider).go(Routes.commandAnnouncements);
    await tester.pumpAndSettle();
    final before = c.read(announcementsProvider).length;

    await tester.tap(find.text('Post announcement'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Post announcement')));
    await tester.pumpAndSettle();

    expect(find.text('Add both a title and a message'), findsOneWidget);
    expect(c.read(announcementsProvider).length, before);
  });

  testWidgets('cadet logs a shooting session in the diary', (tester) async {
    final c = await pumpApp(tester);
    await signInAs(tester, AppRole.cadet);
    final before = c.read(diaryProvider).length;

    c.read(routerProvider).push(Routes.newDiaryEntry);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Score'), '46');
    await tester.enterText(find.widgetWithText(TextField, 'Group size'), '9');
    await tester.scrollUntilVisible(
      find.text('Save session'),
      300,
      scrollable: find.descendant(of: find.byType(DiaryEntryScreen), matching: find.byType(Scrollable)).first,
    );
    await tester.tap(find.text('Save session'));
    await tester.pumpAndSettle();

    final entries = c.read(diaryProvider);
    expect(entries.length, before + 1);
    expect(entries.first.shooting?.score, 46);
    expect(entries.first.sharedWithUnit, isFalse); // private by default
    expect(c.read(diaryStatsProvider).bestScore, 46);
  });

  testWidgets('cadet completes a unit test and sees the result', (tester) async {
    final c = await pumpApp(tester);
    await signInAs(tester, AppRole.cadet);
    c.read(routerProvider).push(Routes.quiz('t1')); // 4 questions, +2 / −0.5
    await tester.pumpAndSettle();

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byType(RadioListTile<int>).first);
      await tester.pump();
      final next = find.text('Next question');
      if (next.evaluate().isNotEmpty) {
        await tester.tap(next);
        await tester.pump();
      }
    }
    await tester.tap(find.text('Submit test'));
    await tester.pump();

    expect(find.textContaining('/ 8'), findsOneWidget);
    expect(find.text('REVIEW ANSWERS'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('theme can be switched to dark from the profile', (tester) async {
    final c = await pumpApp(tester);
    await signInAs(tester, AppRole.cadet);
    await tester.tap(find.text('Me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(c.read(themeModeProvider), ThemeMode.dark);
  });

  testWidgets('senior cadet can switch between Command Center and cadet view', (tester) async {
    final c = await pumpApp(tester);
    await signInAs(tester, AppRole.seniorCadet);
    expect(location(c), Routes.overview);
    await tester.tap(find.byTooltip('Switch to cadet view'));
    await tester.pumpAndSettle();
    expect(location(c), Routes.today);
  });

  testWidgets('signing out returns to sign-in', (tester) async {
    final c = await pumpApp(tester, size: const Size(1280, 900));
    await signInAs(tester, AppRole.ano);
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(location(c), Routes.signIn);
    expect(c.read(authControllerProvider), isNull);
    expect(GoRouter.of(tester.element(find.text('Demo mode'))), isNotNull);
  });
}
