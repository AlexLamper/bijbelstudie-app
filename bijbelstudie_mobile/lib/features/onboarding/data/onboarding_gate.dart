import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/present/auth_controller.dart';
import 'onboarding_storage.dart';
import 'preferences_repository.dart';

/// Where a signed-in user should land right after authenticating.
///
/// Splash (a returning session), login and register all funnel through this
/// so the same rule decides whether the setup wizard or the tour still owes
/// the user something, instead of three call sites each having their own
/// opinion — which is how the app ended up shipping a splash screen that
/// unconditionally marked onboarding "seen" and a register screen that always
/// went straight to `/dashboard`.
///
/// [isNewAccount] skips the network round trip for a registration that just
/// succeeded: there is no preferences record to disagree with yet, so the
/// answer is always the setup wizard.
///
/// The flags are read per account ([OnboardingStorage]). A second account
/// registered on a phone that had already been set up used to inherit the
/// first account's "done" flags and skip straight to the dashboard, never
/// having been asked anything — and never asking the server, which knew
/// perfectly well that the new account had `onboardingCompleted: false`.
Future<String> resolvePostAuthRoute(WidgetRef ref, {bool isNewAccount = false}) async {
  if (isNewAccount) return '/setup';

  final storage = ref.read(onboardingStorageProvider);
  final accountId = ref.read(authControllerProvider).value?.id;

  // Deliberately not left to throw. These are Keychain/KeyStore reads, and a
  // device that fails one (a restored backup, a rotated key, a locked
  // keystore) would take the whole future down with it — and because the
  // callers only chain `.then`, an authenticated user would sit on the login
  // screen with no error and no navigation. Signing in has already succeeded
  // by this point; the worst an unreadable flag can cost is being shown the
  // wizard again.
  var setupDone = await _readFlag(() => storage.hasCompletedSetup(accountId));
  var tourDone = await _readFlag(() => storage.hasSeenTour(accountId));

  if (!setupDone || !tourDone) {
    // The user may have finished setup on the website or on another device;
    // asking the server means they are not asked the same questions twice.
    // Best-effort and short-lived: offline or a slow server must not delay
    // reaching the dashboard, so the local flags stand if this fails.
    try {
      final prefs = await ref
          .read(preferencesRepositoryProvider)
          .getPreferences()
          .timeout(const Duration(seconds: 3));
      if (prefs.onboardingCompleted && !setupDone) {
        await storage.markSetupCompleted(accountId);
        setupDone = true;
      }
      if (prefs.tourCompleted && !tourDone) {
        await storage.markTourSeen(accountId);
        tourDone = true;
      }
    } catch (_) {
      // Offline or the endpoint failed — fall back to what is known locally.
    }
  }

  if (!setupDone) return '/setup';
  if (!tourDone) return '/tour';
  return '/dashboard';
}

Future<bool> _readFlag(Future<bool> Function() read) async {
  try {
    return await read();
  } catch (_) {
    return false;
  }
}
