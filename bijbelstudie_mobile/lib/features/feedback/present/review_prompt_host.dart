import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_review/in_app_review.dart';

import '../../../core/config/preview_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../onboarding/present/tour_controller.dart';
import '../data/review_prompt.dart';

/// Routes the prompt may appear over: the two calm "you have arrived" screens.
///
/// Anything else is either a flow the reader is in the middle of (the reader,
/// the note editor, checkout) or a screen that owns the whole window
/// (onboarding, the tour, login).
const Set<String> _safeRoutes = {'/dashboard', '/profile'};

/// Routes whose visit counts as real engagement once the reader has stayed
/// [ReviewPromptThresholds.engagementDwell] on one of them.
const Set<String> _engagementRoutes = {
  '/read',
  '/study',
  '/commentary',
  '/notes',
};

/// Hosts the App Store rating prompt above the router's Navigator.
///
/// Renders nothing at all until the gate in [ReviewPromptState.shouldAsk]
/// opens and the app is sitting still on a safe screen — mirroring how
/// `TourHost` paints its spotlight from the same position. It sits above the
/// Navigator, so it draws its own scrim and card instead of pushing a route:
/// there is no `Navigator` in scope this high in the tree.
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
  bool _visible = false;

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

    // Leaving a safe screen closes an open prompt rather than letting it hover
    // over whatever the reader navigated to.
    if (_visible && !_safeRoutes.contains(location)) {
      setState(() => _visible = false);
    }

    if (location != null && _engagementRoutes.contains(location)) {
      _dwellTimer = Timer(ReviewPromptThresholds.engagementDwell, () {
        if (!mounted || _currentLocation() != location) return;
        ref.read(reviewPromptProvider.notifier).recordEngagement();
      });
      return;
    }

    if (location != null && _safeRoutes.contains(location) && !_visible) {
      _settleTimer = Timer(ReviewPromptThresholds.settleDelay, _maybeShow);
    }
  }

  void _maybeShow() {
    if (!mounted || !_active || _visible) return;
    if (!_safeRoutes.contains(_currentLocation())) return;
    // Never over the guided tour: it owns the window and eats every gesture.
    if (ref.read(tourControllerProvider).active) return;
    if (!ref.read(reviewPromptProvider).shouldAsk(now: DateTime.now())) return;

    ref.read(reviewPromptProvider.notifier).markAsked();
    setState(() => _visible = true);
  }

  void _dismiss() {
    if (!mounted) return;
    setState(() => _visible = false);
  }

  Future<void> _rate() async {
    _dismiss();
    await ref.read(reviewPromptProvider.notifier).markRated();
    try {
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        // iOS decides whether the native sheet actually appears; it is capped
        // per device per year and silently does nothing when spent.
        await review.requestReview();
      } else if (kAppStoreId.isNotEmpty) {
        await review.openStoreListing(appStoreId: kAppStoreId);
      }
    } catch (_) {
      // A store that will not open is not worth an error message: the reader
      // asked to leave a rating, not to be told about a plugin.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (_visible)
          Positioned.fill(
            child: _ReviewPromptOverlay(onRate: _rate, onDismiss: _dismiss),
          ),
      ],
    );
  }
}

/// The card itself — a scrim, five taps, and a way out.
class _ReviewPromptOverlay extends StatelessWidget {
  const _ReviewPromptOverlay({required this.onRate, required this.onDismiss});

  final Future<void> Function() onRate;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _card(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: BoxDecoration(
        color: AppTheme.paperRaised,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.rule),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vind je BijbelStudie leuk?',
            style: AppTheme.displayTitle.copyWith(color: AppTheme.ink),
          ),
          const SizedBox(height: 6),
          Text(
            'Tik op een ster om de app te beoordelen in de App Store.',
            style: AppTheme.bodyMuted,
          ),
          const SizedBox(height: 16),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: onRate,
                    tooltip: '$i ${i == 1 ? 'ster' : 'sterren'}',
                    icon: Icon(
                      Icons.star_rounded,
                      size: 34,
                      color: AppTheme.flame,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(foregroundColor: AppTheme.inkMuted),
              child: const Text('Niet nu'),
            ),
          ),
        ],
      ),
    );
  }
}
