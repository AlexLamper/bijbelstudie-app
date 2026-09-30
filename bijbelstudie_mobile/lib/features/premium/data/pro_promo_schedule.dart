import 'package:shared_preferences/shared_preferences.dart';

/// Tunables for the full-screen Pro promo (`ProPromoScreen`), in one place.
class ProPromoRules {
  const ProPromoRules._();

  /// Master switch.
  static const bool enabled = true;

  /// At most one promo per this window, persisted across launches.
  static const Duration minInterval = Duration(hours: 24);

  /// How long the Start tab has to be on screen before the promo slides in.
  static const Duration showDelay = Duration(milliseconds: 1500);

  /// App opens (processes that reached the main shell) needed before the
  /// first promo. 2 = never in the very first session, which is the one right
  /// after registration and onboarding.
  static const int minSessions = 2;

  /// The only route the promo may open over.
  static const String triggerRoute = '/dashboard';

  /// Only show when the store answered with real prices: a promo whose CTA
  /// leads to a paywall that cannot sell is worse than no promo.
  static const bool requireStorePrices = true;

  /// `?source=` passed to the paywall, so conversions from here are countable.
  static const String paywallSource = 'app_promo';
}

const _kLastShownAt = 'proPromo.lastShownAt';
const _kSessions = 'proPromo.sessions';

/// The persisted half of the show logic: session count and last-shown time.
class ProPromoSchedule {
  const ProPromoSchedule._();

  /// Counts one app open. Call once per process.
  static Future<void> recordSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kSessions, (prefs.getInt(_kSessions) ?? 0) + 1);
    } catch (_) {
      // Unreadable storage only means the promo waits a session longer.
    }
  }

  /// Whether the persisted gates (session count, 24h window) allow a promo now.
  static Future<bool> isDue({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessions = prefs.getInt(_kSessions) ?? 0;
      if (sessions < ProPromoRules.minSessions) return false;
      final last = prefs.getInt(_kLastShownAt);
      if (last == null) return true;
      final at = now ?? DateTime.now();
      final elapsed = at.difference(DateTime.fromMillisecondsSinceEpoch(last));
      // A clock set backwards reads as negative; treat it as "just shown".
      return elapsed >= ProPromoRules.minInterval;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markShown({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastShownAt, (now ?? DateTime.now()).millisecondsSinceEpoch);
    } catch (_) {}
  }
}
