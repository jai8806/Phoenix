import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phoenix/app.dart';
import 'package:phoenix/core/router/app_router.dart';
import 'package:phoenix/data/auth_repository.dart';
import 'package:phoenix/data/models/user.dart';
import 'package:phoenix/data/providers.dart';

/// Stands in for Supabase: accounts start without a unit, "UNIT1234" is the only valid code.
class FakeBackend implements AuthRepository {
  FakeBackend({this.confirmEmail = false});

  final bool confirmEmail;
  AppUser? _user;

  @override
  bool get isDemo => false;

  @override
  Future<AppUser?> restoreSession() async => null;

  @override
  Future<AppUser> signInAs(AppRole role) => throw UnsupportedError('demo only');

  @override
  Future<AppUser> signInWithPassword({required String email, required String password}) async {
    if (_user == null) throw const AuthFailure('No account');
    return _user!;
  }

  @override
  Future<AppUser?> signUp({required String email, required String password, required String fullName}) async {
    _user = AppUser(id: 'u1', fullName: fullName, role: AppRole.cadet);
    return confirmEmail ? null : _user;
  }

  @override
  Future<AppUser> joinUnit(String code) async {
    if (code != 'UNIT1234') throw const AuthFailure("That code doesn't match a unit.");
    return _user = AppUser(id: 'u1', fullName: _user!.fullName, role: AppRole.cadet, unitName: 'Test Unit');
  }

  @override
  Future<void> signOut() async => _user = null;
}

Future<ProviderContainer> pump(WidgetTester tester, AuthRepository repo) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(repo),
    clockProvider.overrideWithValue(() => DateTime(2026, 11, 26, 9)),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const PhoenixApp()));
  await tester.pumpAndSettle();
  return c;
}

Future<void> createAccount(WidgetTester tester) async {
  await tester.tap(find.text('New here? Create an account'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Full name'), 'Meera Nair');
  await tester.enterText(find.widgetWithText(TextField, 'Email'), 'meera@example.com');
  await tester.enterText(find.widgetWithText(TextField, 'Password'), 'longpassword1');
  await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
  await tester.pumpAndSettle();
}

String loc(ProviderContainer c) => c.read(routerProvider).state.matchedLocation;

void main() {
  testWidgets('new account must join a unit before reaching the app', (tester) async {
    final c = await pump(tester, FakeBackend());
    expect(find.text('Demo mode'), findsNothing);
    await createAccount(tester);
    expect(loc(c), Routes.joinUnit);
    expect(find.text('Join your unit'), findsOneWidget);

    // Can't wander off before joining.
    c.read(routerProvider).go(Routes.today);
    await tester.pumpAndSettle();
    expect(loc(c), Routes.joinUnit);

    await tester.enterText(find.widgetWithText(TextField, 'Unit code'), 'WRONG123');
    await tester.tap(find.widgetWithText(FilledButton, 'Join unit'));
    await tester.pumpAndSettle();
    expect(find.text("That code doesn't match a unit."), findsOneWidget);
    expect(loc(c), Routes.joinUnit);

    await tester.enterText(find.widgetWithText(TextField, 'Unit code'), 'UNIT1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Join unit'));
    await tester.pumpAndSettle();
    expect(loc(c), Routes.today);
    expect(find.text('Good morning, Meera'), findsOneWidget);
  });

  testWidgets('sign-up that needs email confirmation explains the next step', (tester) async {
    final c = await pump(tester, FakeBackend(confirmEmail: true));
    await createAccount(tester);
    expect(loc(c), Routes.signIn);
    expect(find.textContaining('Open the confirmation link we emailed to meera@example.com'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('sign-up without a name asks for it', (tester) async {
    final c = await pump(tester, FakeBackend());
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your full name as it appears on your NCC records.'), findsOneWidget);
    expect(c.read(authControllerProvider), isNull);
  });
}
