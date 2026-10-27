import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../notes/present/notes_providers.dart';
import 'pro_access_provider.dart';

/// Why the Pro offer is allowed on screen right now, beyond the 24h promo.
///
/// The old promo only ran from the second app session, once a day. That left
/// the first session - when roughly half of all subscription conversions
/// happen - without any offer at all, and it never reacted to the moments a
/// reader is most likely to want more (a streak, a full notes quota, their last
/// free AI question). Each value here is one such moment; [ProPromoTrigger]
/// opens the pitch for it the next time Start is on screen.
///
/// The ids are the server allowlist's `promo_shown.trigger` values
/// (`lib/analyticsSchema.ts`, website repo) - reuse, never invent.
enum PromoMoment {
  /// End of onboarding: setup and the tour are done. Once per account.
  onboarding('onboarding', source: 'app_onboarding'),

  /// A streak milestone (3, 7, 30 days).
  streak('streak', source: 'app_streak'),

  /// The progress tree grew a level.
  treeLevel('tree_level', source: 'app_promo'),

  /// Two notes left before the free limit.
  noteLimitNear('note_limit_near', source: 'app_promo'),

  /// The last free AI question of the day was just used.
  aiLastQuestion('ai_last_question', source: 'app_ai'),

  /// A gifted Pro week (referral) or month (admin) ends within a day.
  referralEnd('referral_end', source: 'app_referral_end');

  const PromoMoment(this.trigger, {required this.source});

  /// `promo_shown.trigger`.
  final String trigger;

  /// `?source=` for the pitch and the paywall behind it.
  final String source;

  /// The onboarding offer ignores the 24h window and the session count - it is
  /// the one moment the old schedule skipped on purpose and should not have.
  /// Every other moment still respects the window, so a busy reader is never
  /// shown two offers in a day.
  bool get bypassesWindow => this == PromoMoment.onboarding || this == PromoMoment.referralEnd;
}

final promoMomentProvider = NotifierProvider<PromoMomentController, PromoMoment?>(
  PromoMomentController.new,
);

/// Holds at most one pending moment. A higher-priority moment replaces a
/// lower one; the trigger consumes it when it opens the offer.
class PromoMomentController extends Notifier<PromoMoment?> {
  @override
  PromoMoment? build() => null;

  /// Asks for the offer at [moment]. Onboarding and an ending gift outrank
  /// the rest; between the others the first one wins.
  void request(PromoMoment moment) {
    final current = state;
    if (current == null || (!current.bypassesWindow && moment.bypassesWindow)) {
      state = moment;
    }
  }

  PromoMoment? consume() {
    final moment = state;
    state = null;
    return moment;
  }
}

/// The end-of-onboarding offer, armed by the setup wizard. Separate from
/// [promoMomentProvider] only so the wizard does not need to know about the
/// other moments.
final onboardingPaywallProvider = NotifierProvider<OnboardingPaywallController, bool>(
  OnboardingPaywallController.new,
);

class OnboardingPaywallController extends Notifier<bool> {
  @override
  bool build() => false;

  void arm() {
    state = true;
    ref.read(promoMomentProvider.notifier).request(PromoMoment.onboarding);
  }
}

/// Streak lengths that earn an offer. Celebrating the day matters more than
/// the pitch, so only a few, and the 24h window still applies.
const kPromoStreakMilestones = {3, 7, 30};

/// Notes written before the free limit at which the offer appears ("nog 2").
const kPromoNotesLeft = 2;

/// The free note limit, mirrored from the website's `FREE_NOTE_LIMIT`.
const kFreeNoteLimit = 10;

/// After a note is saved: asks for the offer when exactly [kPromoNotesLeft]
/// free notes remain. Best-effort - an unreadable list just means no offer.
Future<void> requestNoteMomentIfNear(ProviderContainer container) async {
  try {
    if (container.read(hasProProvider)) return;
    final notes = await container.read(notesListProvider.future);
    if (notes.length == kFreeNoteLimit - kPromoNotesLeft) {
      container.read(promoMomentProvider.notifier).request(PromoMoment.noteLimitNear);
    }
  } catch (_) {}
}

/// From the notification scheduler's milestone bookkeeping: `streak-7` etc.
/// Takes the two things it needs rather than a ref, so both a `Ref` and a
/// `WidgetRef` caller can use it.
void requestStreakMomentFor(
  String milestoneId, {
  required bool isPro,
  required PromoMomentController moments,
}) {
  final days = int.tryParse(milestoneId.replaceFirst('streak-', ''));
  if (days == null || !kPromoStreakMilestones.contains(days)) return;
  if (isPro) return;
  moments.request(PromoMoment.streak);
}

const _kGiftUntil = 'proPromo.giftUntil';
const _kGiftOffered = 'proPromo.giftOfferedFor';

/// Watches for the end of a gifted Pro period (a referral week, an admin
/// month) and asks for the "je Pro-week is voorbij" offer once, on the first
/// open after it lapsed.
///
/// While the gift runs the reader *has* Pro, so the paywall would rightly show
/// them their status instead of prices; the offer has to wait for the lapse.
/// The server reports the gift's end as `proExpiresAt` for a non-store Pro;
/// a store subscription's own period end is ignored here (it renews).
///
/// [isPro], [proSource], [proExpiresAt] are the profile's fields.
Future<void> trackGiftEnd(
  PromoMomentController moments, {
  required bool isPro,
  required String? proSource,
  required DateTime? proExpiresAt,
  DateTime? now,
  SharedPreferences? prefs,
}) async {
  try {
    final store = prefs ?? await SharedPreferences.getInstance();
    final at = now ?? DateTime.now();
    final gifted = isPro && proSource != 'apple' && proSource != 'google' && proExpiresAt != null;
    if (gifted) {
      await store.setInt(_kGiftUntil, proExpiresAt.millisecondsSinceEpoch);
      return;
    }
    if (isPro) return;
    final until = store.getInt(_kGiftUntil);
    if (until == null) return;
    final ended = DateTime.fromMillisecondsSinceEpoch(until);
    // Only a recent lapse: a month later the moment has passed.
    if (ended.isAfter(at) || at.difference(ended) > const Duration(days: 7)) return;
    if (store.getInt(_kGiftOffered) == until) return;
    await store.setInt(_kGiftOffered, until);
    moments.request(PromoMoment.referralEnd);
  } catch (_) {}
}
