import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// The one place that decides *which* road to the paywall a reader takes.
///
/// There are two, and the difference is whether the reader has already said
/// what they want:
///
///  * **Discovery** - the 24h promo on Start, or "Bekijk Pro" on Profiel. They
///    asked for nothing in particular, so the pitch (`/pro-intro`, three
///    screens: goal, demo, benefits) is doing real work. Pass no [PaywallGate].
///  * **A stated want** - they tried to open a commentary, ran out of AI
///    questions, hit the note limit. They said it by being blocked. Asking
///    "Wat wil je uit bijbelstudie halen?" asks a question they just answered,
///    and every screen between wanting to pay and being able to is somewhere
///    to lose them. Pass the [PaywallGate] and they land on the price.
///
/// Every surface goes through [openPaywall] rather than writing a path, so the
/// two roads cannot drift apart again - the last time each caller spelled out
/// its own `/pro-intro?source=...`, one of them had been reporting the wrong
/// source for every gated surface it served.
enum PaywallGate {
  aiLimit(
    id: 'ai',
    source: 'app_ai',
    reason: 'Je gratis AI-vragen voor vandaag zijn op.',
    benefit: 'Meer AI-vragen',
  ),
  commentary(
    id: 'commentary',
    source: 'app_study',
    reason: 'Dit commentaar hoort bij Pro.',
    benefit: 'Alle commentaren',
  ),
  originalText(
    id: 'grondtekst',
    source: 'app_study',
    reason: 'De grondtekst hoort bij Pro.',
    benefit: 'Grondtekst',
  ),
  offline(
    id: 'offline',
    source: 'app_study',
    reason: 'Offline lezen hoort bij Pro.',
    benefit: 'Offline lezen',
  ),
  crossrefs(
    id: 'crossrefs',
    source: 'app_crossrefs',
    reason: 'Alle verwante bijbelteksten horen bij Pro.',
  ),
  resources(
    id: 'bronnen',
    source: 'app_resources',
    reason: 'Deze bronnen horen bij Pro.',
  ),
  groups(
    id: 'groepen',
    source: 'app_groups',
    reason: 'Je kunt één groep gratis leiden.',
  ),
  // No [benefit]: "Onbeperkt notities" is deliberately not in `kProBenefits`
  // (see the comment there), so there is nothing in the list to lift. The
  // reason line below says no more than the server's own
  // `NOTE_LIMIT_REACHED` message the reader has just been shown.
  notes(
    id: 'notities',
    source: 'app_notes',
    reason: 'Je hebt je gratis notities gebruikt.',
  );

  const PaywallGate({
    required this.id,
    required this.source,
    required this.reason,
    this.benefit,
  });

  /// Carried in `?gate=` and read back by `PremiumScreen`. Kept separate from
  /// [source] on purpose: [source] is an analytics value checked against the
  /// server's allowlist, this is only ever used to pick copy on screen, so a
  /// new gate here can never cause a dropped event.
  final String id;

  /// `?source=` for the paywall's own `pricing_viewed`. These strings are on
  /// the server allowlist (`lib/analyticsSchema.ts`, website repo) - reuse one,
  /// never invent one, or the event is dropped silently.
  final String source;

  /// One line, shown above the price, naming what the reader was just trying
  /// to do. This is the whole job the three pitch screens were doing for a
  /// reader who already knew what they wanted.
  final String reason;

  /// The `kProBenefits` title to lift to the top of the paywall's list, when
  /// this gate matches one. A reader who came for commentaries should not find
  /// "Alle commentaren" third in a generic list.
  final String? benefit;

  static PaywallGate? fromId(String? id) {
    if (id == null) return null;
    for (final gate in PaywallGate.values) {
      if (gate.id == id) return gate;
    }
    return null;
  }
}

/// Opens the paywall by the right road. See [PaywallGate].
///
/// [gate] null means discovery: the three-screen pitch first. A [gate] means
/// the reader is blocked on something specific and goes straight to the price
/// with that reason named above it.
///
/// Deliberately does not report anything. The gated surfaces already track
/// their own `paywall_cta_clicked` with their own surface - this would either
/// double-count them or quietly replace surfaces that are on the server
/// allowlist with ones that are not.
void openPaywall(BuildContext context, {PaywallGate? gate, String? source}) {
  final router = GoRouter.of(context);
  if (gate == null) {
    router.push('/pro-intro?source=${source ?? 'app_funnel'}');
    return;
  }
  router.push('/premium?source=${source ?? gate.source}&gate=${gate.id}');
}

/// [openPaywall] for a caller that is about to lose its own `BuildContext` -
/// a sheet it pops first, a snackbar action whose host is already gone. The
/// router outlives both; capture it before the pop and hand it over.
void openPaywallWith(GoRouter? router, {PaywallGate? gate, String? source}) {
  if (router == null) return;
  if (gate == null) {
    router.push('/pro-intro?source=${source ?? 'app_funnel'}');
    return;
  }
  router.push('/premium?source=${source ?? gate.source}&gate=${gate.id}');
}
