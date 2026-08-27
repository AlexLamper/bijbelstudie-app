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
class OnboardingStorage {
  OnboardingStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _seenKey = 'onboarding_seen_v1';
  static const _setupKey = 'onboarding_setup_completed_v1';
  static const _tourKey = 'onboarding_tour_seen_v1';

  Future<bool> hasSeen() async {
    final value = await _storage.read(key: _seenKey);
    return value == 'true';
  }

  Future<void> markSeen() async {
    await _storage.write(key: _seenKey, value: 'true');
  }

  Future<bool> hasCompletedSetup() async {
    final value = await _storage.read(key: _setupKey);
    return value == 'true';
  }

  /// Only ever called from the setup wizard's own finish/skip action, never
  /// from a login or splash check - so an app kill mid-wizard leaves this
  /// false and the wizard reappears next launch instead of being silently
  /// skipped.
  Future<void> markSetupCompleted() async {
    await _storage.write(key: _setupKey, value: 'true');
  }

  Future<bool> hasSeenTour() async {
    final value = await _storage.read(key: _tourKey);
    return value == 'true';
  }

  Future<void> markTourSeen() async {
    await _storage.write(key: _tourKey, value: 'true');
  }
}

final onboardingStorageProvider = Provider<OnboardingStorage>(
  (ref) => OnboardingStorage(),
);
