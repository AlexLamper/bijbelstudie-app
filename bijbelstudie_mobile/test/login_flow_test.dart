import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:bijbelstudie_mobile/features/auth/data/auth_repository.dart';
import 'package:bijbelstudie_mobile/features/auth/domain/user.dart';
import 'package:bijbelstudie_mobile/features/auth/present/auth_controller.dart';
import 'package:bijbelstudie_mobile/features/auth/present/login_screen.dart';
import 'package:bijbelstudie_mobile/features/auth/present/register_screen.dart';
import 'package:bijbelstudie_mobile/features/notes/data/notes_repository.dart';
import 'package:bijbelstudie_mobile/features/onboarding/data/onboarding_storage.dart';
import 'package:bijbelstudie_mobile/features/onboarding/data/preferences_repository.dart';

/// Signing in must always end somewhere.
///
/// Every case here is a way the app previously stranded an authenticated user
/// on the login screen with no error and no navigation: a post-auth step that
/// never returned, a null user published as success, or a Keychain read that
/// threw into an uncaught `.then`. Registration hid all three because a new
/// account skips the work each one does.

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.user});

  /// null models a 200 whose body carried no `user` object.
  final User? user;

  @override
  Future<User?> login(String email, String password) async => user;

  @override
  Future<User?> register(String name, String email, String password) async => user;

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeNotesRepository implements NotesRepository {
  var flushed = false;

  @override
  Future<int> flushPendingChanges() async {
    flushed = true;
    return 0;
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeOnboardingStorage implements OnboardingStorage {
  _FakeOnboardingStorage({
    this.setupDone = true,
    this.tourDone = true,
    this.throws = false,
    this.doneAccounts,
  });

  final bool setupDone;
  final bool tourDone;

  /// When set, the flags are answered per account id rather than device-wide -
  /// which is what the storage actually does now.
  final Set<String>? doneAccounts;

  /// Models a device whose secure storage cannot be read.
  final bool throws;

  @override
  Future<bool> hasCompletedSetup([String? accountId]) async {
    if (throws) throw Exception('keystore unavailable');
    if (doneAccounts != null) return doneAccounts!.contains(accountId);
    return setupDone;
  }

  @override
  Future<bool> hasSeenTour([String? accountId]) async {
    if (throws) throw Exception('keystore unavailable');
    if (doneAccounts != null) return doneAccounts!.contains(accountId);
    return tourDone;
  }

  @override
  Future<bool> hasSeen() async => true;
  @override
  Future<void> markSeen() async {}
  @override
  Future<void> markSetupCompleted([String? accountId]) async {}
  @override
  Future<void> markTourSeen([String? accountId]) async {}
  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// The server's answer for an account the device has no local flags for.
class _FakePreferencesRepository implements PreferencesRepository {
  _FakePreferencesRepository({this.onboardingCompleted = false, this.tourCompleted = false});

  final bool onboardingCompleted;
  final bool tourCompleted;

  @override
  Future<UserPreferences> getPreferences() async => UserPreferences(
        onboardingCompleted: onboardingCompleted,
        tourCompleted: tourCompleted,
      );

  @override
  Future<void> syncPreferences(Map<String, dynamic> patch) async {}

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

GoRouter _router(String initial) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
        GoRoute(path: '/setup', builder: (_, __) => const Scaffold(body: Text('SETUP'))),
        GoRoute(path: '/tour', builder: (_, __) => const Scaffold(body: Text('TOUR'))),
        GoRoute(path: '/dashboard', builder: (_, __) => const Scaffold(body: Text('DASHBOARD'))),
      ],
    );

Future<_FakeNotesRepository> _pumpApp(
  WidgetTester tester,
  String initial, {
  User? user,
  OnboardingStorage? storage,
  PreferencesRepository? preferences,
}) async {
  final notes = _FakeNotesRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository(user: user)),
        onboardingStorageProvider.overrideWithValue(storage ?? _FakeOnboardingStorage()),
        notesRepositoryProvider.overrideWithValue(notes),
        preferencesRepositoryProvider
            .overrideWithValue(preferences ?? _FakePreferencesRepository()),
        googleSignInInitProvider.overrideWith((ref) async {}),
      ],
      child: MaterialApp.router(routerConfig: _router(initial)),
    ),
  );
  await tester.pumpAndSettle();
  return notes;
}

/// `pumpAndSettle` cannot be used once the button shows its spinner - a
/// `CircularProgressIndicator` never settles. Pumping past the RevenueCat
/// link timeout is also the point: it is what proves an unresponsive
/// post-auth call can no longer pin the screen.
Future<void> _pumpPastSignIn(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _submitLogin(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 't@e.com');
  await tester.enterText(fields.at(1), 'password123');
  await tester.pump();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Inloggen').first);
  await _pumpPastSignIn(tester);
}

void main() {
  final user = User(id: 'u1', name: 'Test', email: 't@e.com');

  testWidgets('login reaches the dashboard when setup and tour are done', (tester) async {
    await _pumpApp(tester, '/login', user: user);
    await _submitLogin(tester);
    expect(find.text('DASHBOARD'), findsOneWidget);
  });

  testWidgets('login reaches the wizard when setup is outstanding', (tester) async {
    await _pumpApp(
      tester,
      '/login',
      user: user,
      storage: _FakeOnboardingStorage(setupDone: false, tourDone: false),
    );
    await _submitLogin(tester);
    expect(find.text('SETUP'), findsOneWidget);
  });

  testWidgets('login still navigates when secure storage cannot be read', (tester) async {
    await _pumpApp(
      tester,
      '/login',
      user: user,
      storage: _FakeOnboardingStorage(throws: true),
    );
    await _submitLogin(tester);
    // Unreadable flags mean "not done", so the wizard - never the login screen.
    expect(find.text('Welkom terug'), findsNothing);
    expect(find.text('SETUP'), findsOneWidget);
  });

  testWidgets('a response with no user surfaces an error instead of nothing', (tester) async {
    await _pumpApp(tester, '/login', user: null);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 't@e.com');
    await tester.enterText(fields.at(1), 'password123');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Inloggen').first);
    // Short pumps: the SnackBar dismisses itself after four seconds.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('geen accountgegevens'), findsOneWidget);
    // And the button is usable again rather than stuck spinning.
    expect(find.widgetWithText(ElevatedButton, 'Inloggen'), findsOneWidget);
  });

  testWidgets('the offline queue is flushed without blocking sign-in', (tester) async {
    final notes = await _pumpApp(tester, '/login', user: user);
    await _submitLogin(tester);
    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(notes.flushed, isTrue);
  });

  testWidgets('a second account on this device is still shown the wizard', (tester) async {
    // The flags belong to `u1`, who set this phone up. `u2` is a different
    // account and has answered nothing, so it gets the wizard - the whole
    // point of keying these per account. Device-wide flags sent it to the
    // dashboard having asked it nothing.
    await _pumpApp(
      tester,
      '/login',
      user: User(id: 'u2', name: 'Tweede', email: 'two@e.com'),
      storage: _FakeOnboardingStorage(doneAccounts: const {'u1'}),
    );
    await _submitLogin(tester);
    expect(find.text('SETUP'), findsOneWidget);
  });

  testWidgets('the account that did finish setup is not asked again', (tester) async {
    await _pumpApp(
      tester,
      '/login',
      user: user,
      storage: _FakeOnboardingStorage(doneAccounts: const {'u1'}),
    );
    await _submitLogin(tester);
    expect(find.text('DASHBOARD'), findsOneWidget);
  });

  testWidgets('the server can vouch for an account this device has no flags for',
      (tester) async {
    // Set up on the website or another phone: no local flags, but the server
    // knows. Being asked the same questions twice is what this avoids.
    await _pumpApp(
      tester,
      '/login',
      user: user,
      storage: _FakeOnboardingStorage(setupDone: false, tourDone: false),
      preferences: _FakePreferencesRepository(
        onboardingCompleted: true,
        tourCompleted: true,
      ),
    );
    await _submitLogin(tester);
    expect(find.text('DASHBOARD'), findsOneWidget);
  });

  testWidgets('registering from the login screen reaches the wizard, not the dashboard',
      (tester) async {
    // `/register` is pushed on top of `/login`, so the login screen stays
    // mounted and its own listener sees the same successful registration.
    // Resolving with `isNewAccount: false` against a device whose flags are
    // already "done", it used to answer `/dashboard` and race the register
    // screen's `/setup` - which is how a brand-new account skipped onboarding
    // on a phone that had had the app before.
    await _pumpApp(tester, '/login', user: user);

    final registerLink = find
        .ancestor(
          of: find.textContaining('Registreren'),
          matching: find.byType(TextButton),
        )
        .first;
    // It sits at the bottom of a ListView, below the fold on a test viewport.
    await tester.ensureVisible(registerLink);
    await tester.pumpAndSettle();
    await tester.tap(registerLink);
    await tester.pumpAndSettle();

    // Scoped to the pushed screen: the login screen is still mounted
    // underneath, and its fields are in the tree too - which is the very
    // condition this test exists to cover.
    final fields = find.descendant(
      of: find.byType(RegisterScreen),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(0), 'Test');
    await tester.enterText(fields.at(1), 't@e.com');
    await tester.enterText(fields.at(2), 'password123');
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(RegisterScreen),
        matching: find.widgetWithText(ElevatedButton, 'Registreren'),
      ),
    );
    await _pumpPastSignIn(tester);

    expect(find.text('SETUP'), findsOneWidget);
    expect(find.text('DASHBOARD'), findsNothing);
  });

  testWidgets('register goes straight to the wizard', (tester) async {
    await _pumpApp(tester, '/register', user: user);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Test');
    await tester.enterText(fields.at(1), 't@e.com');
    await tester.enterText(fields.at(2), 'password123');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Registreren').first);
    await _pumpPastSignIn(tester);
    expect(find.text('SETUP'), findsOneWidget);
  });
}
