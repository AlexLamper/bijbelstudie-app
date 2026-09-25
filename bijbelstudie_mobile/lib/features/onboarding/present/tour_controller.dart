import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/present/auth_controller.dart';
import '../data/onboarding_storage.dart';
import '../data/preferences_repository.dart';

/// The guided walkthrough, as `guided-tour.tsx` does it on the website: a
/// spotlight cut out of a dimmed screen, anchored to the real widget being
/// talked about, with the app itself navigating underneath from step to step.
///
/// The previous version was six full-screen explainer pages with an icon on
/// each. It described the app rather than showing it, so nothing the reader
/// was told was ever attached to the thing it was about. Everything here
/// exists to put the tooltip next to the live widget instead.

/// Where a step lives and what it points at.
class TourStep {
  const TourStep({
    required this.anchorId,
    required this.route,
    required this.title,
    required this.description,
    this.showMaterials,
    this.materialsTab,
    this.hideForPro = false,
  });

  /// Matches the id passed to the [TourAnchor] wrapping the target widget.
  final String anchorId;

  /// The route this step's anchor lives on. The overlay navigates there before
  /// it starts looking for the anchor.
  final String route;

  final String title;
  final String description;

  /// For `/study` only: which of the two panes has to be showing. Null leaves
  /// whatever the reader had open.
  final bool? showMaterials;

  /// For `/study`'s materials pane: which tab to open on.
  final int? materialsTab;

  /// Dropped for a subscriber, matching the website filtering `pro-cta` out of
  /// `GuidedTourLauncher`.
  final bool hideForPro;
}

/// Anchor ids. Constants rather than bare strings so a renamed anchor breaks
/// at compile time instead of silently never being found.
class TourAnchorIds {
  const TourAnchorIds._();

  static const dashboardHero = 'dashboard-hero';
  static const navStudy = 'nav-study';
  static const navStudies = 'nav-studies';
  static const navNotes = 'nav-notes';
  static const navProfile = 'nav-profile';
  static const readerBar = 'reader-bar';
  static const readerText = 'reader-text';
  static const studyPaneSwitcher = 'study-pane-switcher';
  static const studyMaterialsTabs = 'study-materials-tabs';
  static const notesTabs = 'notes-tabs';
  static const profilePro = 'profile-pro';
}

/// The walkthrough, kept deliberately short.
///
/// It used to be ten steps that marched the reader through every pane of the
/// study screen, each with a paragraph of copy. People did not finish it. It
/// then went to one step per tab, which was too thin: the reader got a single
/// step pointing at its own tab icon, and the verse long-press - where most of
/// the app's tools live - was one clause in a paragraph. The list below gives
/// the reader three steps, each on the control it describes, and keeps one
/// step for every other place worth knowing about: seven taps for a free
/// reader, six for a subscriber.
///
/// Every anchor is present the moment its route lands - the reader's text
/// anchor wraps its loading skeleton too - so no step can stall hunting for a
/// widget deep inside a screen that is still loading.
const List<TourStep> _allSteps = [
  TourStep(
    anchorId: TourAnchorIds.dashboardHero,
    route: '/dashboard',
    title: 'Je startpunt',
    description:
        'Op Start zie je meteen waar je gebleven was. Tik op de kaart om '
        'verder te lezen.',
  ),
  TourStep(
    anchorId: TourAnchorIds.readerText,
    route: '/study',
    showMaterials: false,
    title: 'Houd een vers ingedrukt',
    description:
        'Dan kun je het markeren, er een notitie of bladwijzer bij zetten, '
        'kruisverwijzingen zien of het commentaar en de grondtekst bij dat '
        'vers openen. Delen en kopiëren kan ook.',
  ),
  TourStep(
    anchorId: TourAnchorIds.readerBar,
    route: '/study',
    showMaterials: false,
    title: 'Vertaling en weergave',
    description:
        'Tik op de vertaling om te wisselen. Met het vergrootglas zoek je in '
        'de hele Bijbel, en onder Aa stel je lettergrootte en weergave in.',
  ),
  TourStep(
    anchorId: TourAnchorIds.studyPaneSwitcher,
    route: '/study',
    showMaterials: true,
    materialsTab: 0,
    title: 'Bijbel en Studie',
    description:
        'Tik op de titel om een ander boek of hoofdstuk te kiezen. Onder '
        'Studie vind je commentaar, grondtekst, achtergrond en de assistent '
        'bij het hoofdstuk dat je leest.',
  ),
  TourStep(
    anchorId: TourAnchorIds.navStudies,
    route: '/studies',
    title: 'Begeleide studies',
    description:
        'Uitgewerkte studies nemen je stap voor stap mee door een thema of '
        'bijbelgedeelte. Je voortgang wordt onthouden.',
  ),
  TourStep(
    anchorId: TourAnchorIds.navNotes,
    route: '/notes',
    title: 'Notities en profiel',
    description:
        'Je notities, markeringen en bladwijzers komen hier samen. Onder '
        'Profiel staan je voortgang, instellingen en hulp.',
  ),
  TourStep(
    anchorId: TourAnchorIds.profilePro,
    route: '/profile',
    title: 'Upgrade naar Pro',
    description:
        'Met Pro lees je alle commentaren en de grondtekst bij elk '
        'hoofdstuk. Het gratis plan blijft gewoon beschikbaar.',
    hideForPro: true,
  ),
];

class TourState {
  const TourState({this.active = false, this.index = 0});

  final bool active;
  final int index;

  TourState copyWith({bool? active, int? index}) =>
      TourState(active: active ?? this.active, index: index ?? this.index);
}

final tourControllerProvider = NotifierProvider<TourController, TourState>(
  TourController.new,
);

class TourController extends Notifier<TourState> {
  @override
  TourState build() => const TourState();

  /// The steps a given reader sees. A subscriber is not pitched Pro.
  static List<TourStep> stepsFor({required bool isPro}) {
    if (!isPro) return _allSteps;
    return _allSteps.where((step) => !step.hideForPro).toList();
  }

  void start() => state = const TourState(active: true, index: 0);

  void goTo(int index, int total) {
    if (index < 0 || index >= total) return;
    state = state.copyWith(index: index);
  }

  void next(int total) {
    if (state.index + 1 >= total) {
      finish();
      return;
    }
    state = state.copyWith(index: state.index + 1);
  }

  void back() {
    if (state.index == 0) return;
    state = state.copyWith(index: state.index - 1);
  }

  /// Ends the tour and records that it has been seen.
  ///
  /// The local flag is what stops it reappearing on the next launch; the sync
  /// is best-effort so the website and a second device agree, exactly as the
  /// setup wizard does it. Neither is allowed to keep the overlay on screen,
  /// so the state is cleared first.
  void finish() {
    if (!state.active) return;
    state = const TourState();

    unawaited(() async {
      final accountId = ref.read(authControllerProvider).value?.id;
      await ref.read(onboardingStorageProvider).markTourSeen(accountId);
      try {
        await ref
            .read(preferencesRepositoryProvider)
            .syncPreferences({'tourCompleted': true});
      } catch (_) {
        // Offline. The local flag already did the job that matters.
      }
    }());
  }
}

/// Where the live widgets register themselves so the overlay can find them.
///
/// A plain process-wide registry rather than a provider or a map of
/// [GlobalKey]s. GlobalKeys were the obvious choice and the wrong one: during a
/// route transition go_router has the outgoing and incoming pages in the tree
/// at once, and two mounted widgets sharing one GlobalKey is a crash, not a
/// warning. Registering a [BuildContext] under a plain string cannot crash -
/// the second registration simply wins, which is also the one the reader is
/// looking at.
class TourAnchors {
  TourAnchors._();

  static final TourAnchors instance = TourAnchors._();

  final Map<String, BuildContext> _byId = {};

  void register(String id, BuildContext context) => _byId[id] = context;

  /// Removes [context] only if it is still the registered one, so a widget
  /// disposing *after* its replacement registered cannot unregister the
  /// replacement.
  void unregister(String id, BuildContext context) {
    if (identical(_byId[id], context)) _byId.remove(id);
  }

  BuildContext? contextFor(String id) {
    final context = _byId[id];
    if (context == null || !context.mounted) return null;
    return context;
  }

  /// The anchor's rectangle in global coordinates, or null while it is not
  /// mounted, not laid out, or off-screen.
  Rect? rectFor(String id) {
    final context = contextFor(id);
    if (context == null) return null;
    final object = context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) return null;
    if (object.size.isEmpty) return null;
    return object.localToGlobal(Offset.zero) & object.size;
  }
}

/// Marks a widget as something the guided tour can point at.
///
/// Wrapping is deliberately invisible: it adds no layout, no painting and no
/// hit-test behaviour, so an anchor can be dropped around any widget without
/// changing how the screen looks or behaves when the tour is not running.
class TourAnchor extends StatefulWidget {
  const TourAnchor({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  State<TourAnchor> createState() => _TourAnchorState();
}

class _TourAnchorState extends State<TourAnchor> {
  @override
  void initState() {
    super.initState();
    TourAnchors.instance.register(widget.id, context);
  }

  @override
  void didUpdateWidget(TourAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      TourAnchors.instance.unregister(oldWidget.id, context);
      TourAnchors.instance.register(widget.id, context);
    }
  }

  @override
  void dispose() {
    TourAnchors.instance.unregister(widget.id, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
