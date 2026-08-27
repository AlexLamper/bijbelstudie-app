import 'package:flutter_riverpod/flutter_riverpod.dart';

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
Future<String> resolvePostAuthRoute(WidgetRef ref, {bool isNewAccount = false}) async {
  if (isNewAccount) return '/setup';

  final storage = ref.read(onboardingStorageProvider);
  var setupDone = await storage.hasCompletedSetup();
  var tourDone = await storage.hasSeenTour();

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
        await storage.markSetupCompleted();
        setupDone = true;
      }
      if (prefs.tourCompleted && !tourDone) {
        await storage.markTourSeen();
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
