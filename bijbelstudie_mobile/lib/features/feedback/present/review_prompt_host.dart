import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_review/in_app_review.dart';

import '../../../core/config/preview_config.dart';
import '../../../core/router/app_router.dart';
import '../../onboarding/present/tour_controller.dart';
import '../data/review_prompt.dart';

/// Routes the review sheet may be requested over: the two calm "you have
/// arrived" screens.
///
/// Anything else is either a flow the reader is in the middle of (the reader,
/// the note editor, checkout) or a screen that owns the whole window
/// (onboarding, the tour, login).
const Set<String> _safeRoutes = {'/dashboard', '/profile'};

/// Routes whose visit counts as real engagement once the reader has stayed
/// [ReviewPromptThresholds.engagementDwell] on one of them.
///
/// Dwell is only one of the signals; the stronger ones — a finished lesson, a
/// passed quiz, a streak milestone — are recorded where they happen and land
/// in the same counter. See [ReviewSignal].
const Set<String> _engagementRoutes = {
  '/read',
  '/study',
  '/commentary',
  '/notes',
};

/// Picks the moment to ask the OS for a rating prompt.
///
/// It paints nothing. There is no card, no scrim, no stars, no "do you like
/// the app?" — that shape of pre-prompt is banned outright: App Store Review
/// Guideline 5.6.1 requires the provided API and disallows custom review
/// prompts, and Play's in-app review guidelines forbid both the "do you like
/// the app" question and any overlay around the review card. Stars we drew
/// ourselves were dishonest on top of that, since one star and five did the
/// same thing and neither was recorded anywhere.
///
/// What is allowed — and encouraged by both stores — is choosing *when* to
/// call the API. That is all this widget does: it counts launches and
/// engagement, waits until the app is sitting still on a safe screen, and then
/// calls [InAppReview.requestReview] once. The OS decides the rest: the sheet
/// is rate-limited by the system, the reader can switch it off in Settings,
/// and a call that returns normally is no evidence anything appeared. Nothing
/// downstream may read "asked" as "rated".
///
/// There is deliberately no automatic fall-back to the store listing when
/// `requestReview` is unavailable: throwing the reader out of the app and into
/// the store, unasked, is worse than staying quiet. The store listing is
/// reachable only from the explicit "Beoordeel de app" row in the profile
/// menu (`rate_app.dart`).
class ReviewPromptHost extends ConsumerStatefulWidget {
  const ReviewPromptHost({super.key, required this.child, this.enabled = true});

  final Widget child;

  /// The off switch. `main.dart` passes `false` in preview mode, and tests that
  /// mount the whole app can pass `false` so no timer or plugin call is ever
  /// started from a widget test.
  final bool enabled;

  @override
  ConsumerState<ReviewPromptHost> createState() => _ReviewPromptHostState();
}

class _ReviewPromptHostState extends ConsumerState<ReviewPromptHost> {
  GoRouter? _router;
  Listenable? _routerListenable;
  Timer? _dwellTimer;
  Timer? _settleTimer;
  String? _location;

  /// One attempt per process, so a reader who walks in and out of /dashboard
  /// does not get the API called at them on every return.
  bool _askedThisSession = false;

  bool get _active => widget.enabled && !PreviewConfig.enabled;

  @override
  void initState() {
    super.initState();
    if (!_active) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(reviewPromptProvider.notifier).recordLaunch();
      _attachRouter();
    });
  }

  void _attachRouter() {
    final router = ref.read(routerProvider);
    _router = router;
    _routerListenable = router.routerDelegate..addListener(_onRouteChanged);
    _onRouteChanged();
  }

  @override
  void dispose() {
    _routerListenable?.removeListener(_onRouteChanged);
    _dwellTimer?.cancel();
    _settleTimer?.cancel();
    super.dispose();
  }

  String? _currentLocation() {
    try {
      return _router?.state.uri.path;
    } catch (_) {
      // The delegate can fire before the first route is resolved.
      return null;
    }
  }

  void _onRouteChanged() {
    if (!mounted || !_active) return;
    final location = _currentLocation();
    if (location == _location) return;
    _location = location;

    _dwellTimer?.cancel();
    _settleTimer?.cancel();

    if (location != null && _engagementRoutes.contains(location)) {
      _dwellTimer = Timer(ReviewPromptThresholds.engagementDwell, () {
        if (!mounted || _currentLocation() != location) return;
        ref
            .read(reviewPromptProvider.notifier)
            .recordSuccess(ReviewSignal.dwell);
      });
      return;
    }

    if (location != null &&
        _safeRoutes.contains(location) &&
        !_askedThisSession) {
      _settleTimer = Timer(ReviewPromptThresholds.settleDelay, _maybeAsk);
    }
  }

  Future<void> _maybeAsk() async {
    if (!mounted || !_active || _askedThisSession) return;
    if (!_safeRoutes.contains(_currentLocation())) return;
    // Never during the guided tour: it owns the window and eats every gesture.
    if (ref.read(tourControllerProvider).active) return;
    if (!ref.read(reviewPromptProvider).shouldAsk(now: DateTime.now())) return;

    // Claimed before the await, so a second settle timer cannot slip past the
    // gate while this one is waiting on the plugin.
    _askedThisSession = true;

    try {
      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;
      if (!mounted) return;
      // The reader may have walked off the safe screen while the plugin was
      // answering; the sheet belongs over the calm screen or nowhere.
      if (!_safeRoutes.contains(_currentLocation())) return;

      await ref.read(reviewPromptProvider.notifier).markAsked();
      await review.requestReview();
    } catch (_) {
      // A prompt that will not open is not worth an error message: the reader
      // did not ask for anything and has nothing to act on.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
