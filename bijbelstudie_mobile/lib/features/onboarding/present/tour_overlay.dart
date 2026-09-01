import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../profile/present/profile_provider.dart';
import '../../study/present/study_pane_controller.dart';
import 'tour_controller.dart';

/// Wraps the whole app so the tour can paint over every route, the bottom nav
/// included. Installed once, from `MaterialApp.router`'s `builder`.
///
/// Nothing is built while the tour is off - this costs one provider read per
/// rebuild of the app root and nothing else.
class TourHost extends ConsumerWidget {
  const TourHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(tourControllerProvider.select((s) => s.active));
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        child,
        if (active) const Positioned.fill(child: _TourOverlay()),
      ],
    );
  }
}

/// Padding around the spotlight hole, matching `guided-tour.tsx`'s PADDING.
const double _spotlightPadding = 8;
const double _tooltipGap = 14;
const double _screenMargin = 16;

/// How long to keep looking for a step's anchor before giving up on placing
/// the card next to it. The route change, the screen's own data fetch and the
/// first layout all have to land first, and on a cold tab that is not
/// instant. Matches the website's 5s polling window.
const Duration _anchorTimeout = Duration(seconds: 5);

/// Once found, the anchor is re-measured for a short while in case the screen
/// is still settling - a late image, a list that finishes laying out, data that
/// lands after the first frame. It is not watched forever: the scrim eats every
/// gesture, so nothing the reader does can move the target, and a timer that
/// never stops is a frame of work every quarter second for the whole tour.
const int _stableTicksBeforeRest = 8;

class _TourOverlay extends ConsumerStatefulWidget {
  const _TourOverlay();

  @override
  ConsumerState<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends ConsumerState<_TourOverlay> {
  Rect? _rect;

  /// True once the anchor search for the current step has run out of time.
  /// The step still shows - it just floats, centred, instead of pointing at
  /// something. A tour that stalls on a missing widget would be worse than one
  /// that occasionally explains without pointing.
  bool _gaveUp = false;

  Timer? _poll;
  Stopwatch? _searching;
  int _stableTicks = 0;
  int _syncedStep = -1;
  String? _syncedAnchor;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }


  /// Puts the app on the step's route and pane, then starts hunting for its
  /// anchor. Called from a post-frame callback: it navigates and writes to
  /// providers, neither of which may happen during a build.
  void _syncToStep(TourStep step) {
    final router = ref.read(routerProvider);
    if (router.state.uri.path != step.route) {
      router.go(step.route);
    }
    if (step.showMaterials != null || step.materialsTab != null) {
      ref.read(studyPaneProvider.notifier).apply(
        showMaterials: step.showMaterials,
        materialsTab: step.materialsTab,
      );
    }

    _poll?.cancel();
    _searching = Stopwatch()..start();
    _stableTicks = 0;
    if (_rect != null || _gaveUp) {
      setState(() {
        _rect = null;
        _gaveUp = false;
      });
    }
    // Only start the search when the anchor is not already on screen. A
    // successful `_locate` installs the follow timer as `_poll`, so assigning
    // a search timer over the top of it unconditionally - which is what this
    // used to do - orphaned a periodic timer per step, ticking for the rest of
    // the app's life with nothing left holding a reference to cancel it.
    if (_locate(step)) return;
    // The route may still be animating and the target screen may still be
    // fetching, so keep looking rather than deciding on the first frame.
    _poll = Timer.periodic(const Duration(milliseconds: 100), (_) => _locate(step));
  }

  /// Returns true once the anchor has been found and the follow timer taken
  /// over, so the caller knows not to keep searching.
  bool _locate(TourStep step) {
    if (!mounted) return false;

    final anchorContext = TourAnchors.instance.contextFor(step.anchorId);
    if (anchorContext != null) {
      // Bring the anchor on screen before measuring it, or the spotlight lands
      // on wherever the widget happens to be parked below the fold.
      unawaited(_ensureVisible(anchorContext));
    }

    final rect = TourAnchors.instance.rectFor(step.anchorId);
    if (rect != null) {
      _poll?.cancel();
      _searching?.stop();
      if (_rect != rect || _gaveUp) {
        setState(() {
          _rect = rect;
          _gaveUp = false;
        });
      }
      _stableTicks = 0;
      _poll = Timer.periodic(const Duration(milliseconds: 250), (_) => _follow(step));
      return true;
    }

    if ((_searching?.elapsed ?? Duration.zero) > _anchorTimeout) {
      _poll?.cancel();
      if (!_gaveUp) setState(() => _gaveUp = true);
    }
    return false;
  }

  void _follow(TourStep step) {
    if (!mounted) return;
    final rect = TourAnchors.instance.rectFor(step.anchorId);
    if (rect == null || rect == _rect) {
      if (++_stableTicks >= _stableTicksBeforeRest) _poll?.cancel();
      return;
    }
    _stableTicks = 0;
    setState(() => _rect = rect);
  }

  Future<void> _ensureVisible(BuildContext anchorContext) async {
    try {
      await Scrollable.ensureVisible(
        anchorContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {
      // Not inside a scrollable, or the element went away mid-scroll. The
      // anchor is simply measured where it is.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read once: the profile fetch is usually still in flight
    // when the tour opens, so reading it once would settle on "not Pro" and
    // pitch the paywall step to a subscriber for the whole tour.
    final isPro = ref.watch(profileProvider).value?.isPro ?? false;
    final steps = TourController.stepsFor(isPro: isPro);
    if (steps.isEmpty) return const SizedBox.shrink();

    final tour = ref.watch(tourControllerProvider);
    final index = tour.index.clamp(0, steps.length - 1);
    final step = steps[index];
    final controller = ref.read(tourControllerProvider.notifier);

    // Re-sync when the step changes, or when the same index now points at a
    // different step because the Pro card was filtered out mid-tour.
    if (_syncedStep != index || _syncedAnchor != step.anchorId) {
      _syncedStep = index;
      _syncedAnchor = step.anchorId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncToStep(step);
      });
    }

    final media = MediaQuery.of(context);
    final spotlight = _rect == null
        ? null
        : Rect.fromLTRB(
            (_rect!.left - _spotlightPadding).clamp(0.0, media.size.width),
            (_rect!.top - _spotlightPadding).clamp(0.0, media.size.height),
            (_rect!.right + _spotlightPadding).clamp(0.0, media.size.width),
            (_rect!.bottom + _spotlightPadding).clamp(0.0, media.size.height),
          );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // The scrim swallows every tap, so the app underneath cannot be
          // driven out from under the tour. Tapping it does nothing: closing
          // by accident is a worse outcome than having to reach for Overslaan.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: CustomPaint(painter: TourScrimPainter(spotlight)),
            ),
          ),
          if (spotlight != null)
            Positioned(
              left: spotlight.left,
              top: spotlight.top,
              width: spotlight.width,
              height: spotlight.height,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.teal, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.teal.withValues(alpha: 0.25),
                        blurRadius: 0,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          _positionCard(
            media: media,
            spotlight: spotlight,
            card: _TourCard(
              step: step,
              index: index,
              total: steps.length,
              onSkip: controller.finish,
              onBack: index == 0 ? null : controller.back,
              onNext: () => controller.next(steps.length),
              onJump: (i) => controller.goTo(i, steps.length),
            ),
          ),
        ],
      ),
    );
  }

  /// Places the card in whichever gap around the spotlight is larger, capped
  /// to that gap so a tall card scrolls inside itself rather than running off
  /// the screen. With no spotlight it simply centres.
  Widget _positionCard({
    required MediaQueryData media,
    required Rect? spotlight,
    required Widget card,
  }) {
    final topInset = media.padding.top + _screenMargin;
    final bottomInset = media.padding.bottom + _screenMargin;

    if (spotlight == null) {
      return Positioned(
        left: _screenMargin,
        right: _screenMargin,
        top: topInset,
        bottom: bottomInset,
        child: Center(child: SingleChildScrollView(child: card)),
      );
    }

    final spaceAbove = spotlight.top - topInset - _tooltipGap;
    final spaceBelow = media.size.height - spotlight.bottom - bottomInset - _tooltipGap;
    final below = spaceBelow >= spaceAbove;
    final available = (below ? spaceBelow : spaceAbove).clamp(0.0, media.size.height);

    return Positioned(
      left: _screenMargin,
      right: _screenMargin,
      top: below ? spotlight.bottom + _tooltipGap : null,
      bottom: below ? null : media.size.height - spotlight.top + _tooltipGap,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: available),
        child: SingleChildScrollView(child: card),
      ),
    );
  }
}

/// The dimmed screen with a rounded hole punched in it.
///
/// `saveLayer` + `BlendMode.clear` rather than a Path difference: the hole
/// stays crisp at any radius and the whole thing is one composited layer.
///
/// Public so a widget test can read [hole] back and tell "the overlay found
/// its anchor and cut a spotlight" apart from "it gave up and centred the
/// card" - two states that otherwise look identical to a finder.
class TourScrimPainter extends CustomPainter {
  const TourScrimPainter(this.hole);

  /// The spotlight, in global coordinates. Null when no anchor was found.
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = const Color(0xA80F172A));
    if (hole != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole!, const Radius.circular(AppTheme.radiusMd)),
        Paint()..blendMode = BlendMode.clear,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(TourScrimPainter oldDelegate) => oldDelegate.hole != hole;
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.step,
    required this.index,
    required this.total,
    required this.onSkip,
    required this.onBack,
    required this.onNext,
    required this.onJump,
  });

  final TourStep step;
  final int index;
  final int total;
  final VoidCallback onSkip;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final isLast = index == total - 1;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.explore_outlined, size: 15, color: AppTheme.teal),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Rondleiding · ${index + 1}/$total', style: AppTheme.overline),
              ),
              InkWell(
                onTap: onSkip,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: AppTheme.inkMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(step.title, style: AppTheme.displaySmall),
          const SizedBox(height: 8),
          Text(step.description, style: AppTheme.bodyMuted.copyWith(height: 1.5)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < total; i++)
                Semantics(
                  button: true,
                  label: 'Ga naar stap ${i + 1}',
                  child: InkWell(
                    onTap: () => onJump(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 4,
                        width: i == index ? 16 : 4,
                        decoration: BoxDecoration(
                          color: i <= index
                              ? AppTheme.teal
                              : AppTheme.teal.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: onSkip,
                child: Text(
                  'Overslaan',
                  style: AppTheme.bodyStrong.copyWith(color: AppTheme.inkMuted),
                ),
              ),
              const Spacer(),
              if (onBack != null) ...[
                SiteOutlineButton(label: 'Vorige', expand: false, onPressed: onBack),
                const SizedBox(width: 8),
              ],
              SiteButton(
                label: isLast ? 'Klaar' : 'Volgende',
                expand: false,
                trailingIcon: isLast ? Icons.check : Icons.arrow_forward,
                onPressed: onNext,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
