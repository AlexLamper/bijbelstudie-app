import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists three independent flags, each shown at most once:
///
/// - [hasSeen]/[markSeen] - the pre-login marketing intro (3 static pages).
///   Only relevant to a signed-out first run.
/// - [hasCompletedSetup]/[markSetupCompleted] - the post-registration setup
///   wizard that actually configures translation, reading preferences and the
///   daily reminder.
/// - [hasSeenTour]/[markTourSeen] - the guided walkthrough of the app itself.
///
/// Keeping these separate (rather than one "onboarding done" bit) is what
/// lets a signed-in user who has never set up their account still get the
/// setup wizard and the tour even though the marketing intro is irrelevant to
/// them - and what stops a value being marked done before the flow it
/// belongs to has actually been completed.
///
/// ## Why setup and tour are keyed by account
///
/// The marketing intro is a property of the *device*: it pitches the product
/// to whoever is holding the phone, and showing it twice on one phone is
/// pointless. Setup and the tour are properties of an *account* - they ask
/// which translation you read and show you around your own data.
///
/// Storing all three device-wide meant registering a second account on a phone
/// that had already been set up skipped the wizard and the tour outright. The
/// new account landed on an empty dashboard having never been asked a single
/// question, and because [resolvePostAuthRoute] short-circuits on a local
/// `true`, the server - which correctly reported `onboardingCompleted: false`
/// for that brand-new account - was never even consulted.
///
/// A null [accountId] keeps the old device-wide key. Nothing signed in should
/// pass null; it exists so a caller without a user id degrades to the previous
/// behaviour rather than throwing.
class OnboardingStorage {
  OnboardingStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _seenKey = 'onboarding_seen_v1';
  static const _setupKey = 'onboarding_setup_completed_v1';
  static const _tourKey = 'onboarding_tour_seen_v1';

  /// Per-account keys deliberately carry a new version suffix. Reusing the v1
  /// key with an id appended would be indistinguishable from the device-wide
  /// value for an account whose id happened to be empty.
  static String _scoped(String base, String? accountId) {
    if (accountId == null || accountId.isEmpty) return base;
    return '${base}_acct_$accountId';
  }

  Future<bool> hasSeen() async {
    final value = await _storage.read(key: _seenKey);
    return value == 'true';
  }

  Future<void> markSeen() async {
    await _storage.write(key: _seenKey, value: 'true');
  }

  Future<bool> hasCompletedSetup([String? accountId]) async {
    final value = await _storage.read(key: _scoped(_setupKey, accountId));
    return value == 'true';
  }

  /// Only ever called from the setup wizard's own finish/skip action, never
  /// from a login or splash check - so an app kill mid-wizard leaves this
  /// false and the wizard reappears next launch instead of being silently
  /// skipped.
  Future<void> markSetupCompleted([String? accountId]) async {
    await _storage.write(key: _scoped(_setupKey, accountId), value: 'true');
  }

  Future<bool> hasSeenTour([String? accountId]) async {
    final value = await _storage.read(key: _scoped(_tourKey, accountId));
    return value == 'true';
  }

  Future<void> markTourSeen([String? accountId]) async {
    await _storage.write(key: _scoped(_tourKey, accountId), value: 'true');
  }
}

final onboardingStorageProvider = Provider<OnboardingStorage>(
  (ref) => OnboardingStorage(),
);
