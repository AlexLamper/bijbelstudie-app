import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../study/present/study_pane_controller.dart';
import 'guide_cues.dart';
import 'guide_hand.dart';
import 'guide_reward_card.dart';
import 'tour_controller.dart';

/// Wraps the whole app so the guide can paint over every route, the bottom
/// nav and the open sheets included. Installed once, from
/// `MaterialApp.router`'s `builder`.
///
/// Unlike the spotlight tour it replaced, nothing here blocks the app: the
/// reader has to long-press, swipe and tap the real screens, so only the
/// guide's own card takes touches. The hand is painted, never hit-tested.
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
        if (active)
          const Positioned.fill(child: _GuideOverlay())
        else
          const Positioned.fill(child: _GuideTipLayer()),
      ],
    );
  }
}

const double _screenMargin = 12;

/// The tab bar's own height from `MainScaffold`; the card stays clear of it so
/// the tabs remain usable while the guide runs.
const double _navBarReserve = 60;

/// How often the overlay re-measures what it points at. Sheets slide in,
/// chapters load and lists scroll under the guide; a quick poll follows all
/// of it without wiring a listener into every one of those widgets.
const Duration _followEvery = Duration(milliseconds: 120);

/// Follows the route and, while there is something to point at, the anchors
/// on screen, for one of the two layers below.
///
/// The route comes from the router's own notifications. The anchors are
/// polled: sheets slide in, chapters load and lists scroll under the guide,
/// and a quick poll follows all of that without wiring a listener into every
/// one of those widgets. It only runs while a hand is wanted.
mixin _Following<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Timer? _poll;
  GoRouter? _router;
  String _path = '';
  final Map<String, Rect?> _rects = {};

  /// The anchors whose rectangles the layer needs right now.
  List<String> get followedAnchors;

  void listenToRoute() {
    try {
      _router = ref.read(routerProvider);
      _router!.routerDelegate.addListener(_onRoute);
      _path = _router!.state.uri.path;
    } catch (_) {
      // No router above this harness: every screen reads as "elsewhere".
    }
  }

  void _onRoute() {
    if (!mounted) return;
    String path;
    try {
      path = _router!.state.uri.path;
    } catch (_) {
      return;
    }
    if (path == _path) return;
    setState(() => _path = path);
  }

  void startPolling() {
    if (_poll != null) return;
    _poll = Timer.periodic(_followEvery, (_) => _measure());
    measureSoon();
  }

  void stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  void _measure() {
    if (!mounted) return;
    var changed = false;
    for (final id in followedAnchors) {
      final rect = TourAnchors.instance.rectFor(id);
      if (_rects[id] != rect) {
        _rects[id] = rect;
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  /// The first of [anchors] that is on screen, with the part of it that is.
  ///
  /// Read from the last measure only. Measuring here, in build, would walk a
  /// tree that is still being rebuilt.
  (String, Rect)? firstOnScreen(List<String> anchors, Size screen) {
    for (final id in anchors) {
      final rect = _rects[id];
      if (rect == null || !rect.isFinite) continue;
      final visible = rect.intersect(Offset.zero & screen);
      if (visible.width < 8 || visible.height < 8) continue;
      return (id, visible);
    }
    return null;
  }

  /// Measures again right after this frame, for anchors that just became
  /// wanted, rather than on the next tick.
  void measureSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  GuideView viewOf(StudyPaneState pane) => GuideView(
    onStudy: _path == '/study',
    showMaterials: pane.showMaterials,
    materialsTab: pane.materialsTab,
  );

  @override
  void dispose() {
    _poll?.cancel();
    _router?.routerDelegate.removeListener(_onRoute);
    super.dispose();
  }
}

/// Where on an anchor the finger goes. Rows and the reader are aimed a little
/// left of centre, onto the words rather than the empty right margin.
Offset _aimFor(String id, Rect rect, GuideGesture gesture) {
  switch (id) {
    case TourAnchorIds.firstVerse:
      return Offset(rect.left + rect.width * 0.38, rect.top + math.min(rect.height / 2, 28));
    case TourAnchorIds.readerText:
      return gesture == GuideGesture.swipeLeft
          ? Offset(rect.center.dx, rect.top + math.min(rect.height * 0.35, 220))
          : Offset(rect.left + rect.width * 0.38, rect.top + 40);
    case TourAnchorIds.sheetColours:
      // The first colour: "kies een kleur" reads better with one to pick.
      return Offset(rect.left + math.min(rect.width * 0.08, 40), rect.center.dy);
    case TourAnchorIds.sheetNote:
    case TourAnchorIds.sheetCommentary:
    case TourAnchorIds.aiSuggestion:
      return Offset(rect.left + math.min(rect.width * 0.3, 120), rect.center.dy);
    case TourAnchorIds.aiComposer:
      return Offset(rect.left + rect.width * 0.4, rect.center.dy);
    case TourAnchorIds.studyMaterialsTabs:
      // The whole tab row: Assistent is its last label.
      return Offset(rect.right - 44, rect.center.dy);
    default:
      return rect.center;
  }
}

class _GuideOverlay extends ConsumerStatefulWidget {
  const _GuideOverlay();

  @override
  ConsumerState<_GuideOverlay> createState() => _GuideOverlayState();
}

class _GuideOverlayState extends ConsumerState<_GuideOverlay> with _Following {
  int? _syncedIndex;
  List<String> _cueAnchors = const [];
  String? _scrolledTo;

  /// Right after the guide moves the app to a step's screen, the router and
  /// the pager are still on their way there. "Ga terug" is held back until
  /// they have had the time to arrive, or it flashes on every step.
  bool _settling = false;
  Timer? _settle;

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  @override
  List<String> get followedAnchors => _cueAnchors;

  @override
  void initState() {
    super.initState();
    listenToRoute();
    startPolling();
  }

  /// Puts the app where the step starts: on the Bijbel tab, on the side of
  /// `/study` the step is about. Called from a post-frame callback - it
  /// navigates and writes to providers, neither of which may happen in build.
  void _syncToStep(GuideStep step) {
    final router = ref.read(routerProvider);
    if (router.state.uri.path != '/study') router.go('/study');
    final pane = ref.read(studyPaneProvider);
    if (pane.showMaterials != step.onStudyPane) {
      ref.read(studyPaneProvider.notifier).apply(showMaterials: step.onStudyPane);
    }
    _scrolledTo = null;
    _settle?.cancel();
    setState(() => _settling = true);
    _settle = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _settling = false);
    });
  }

  /// Brings the verse the hand points at on screen, once per cue and only if
  /// it is off screen: doing it on every measure would fight the reader's own
  /// scrolling.
  void _ensureVisible(String id) {
    if (_scrolledTo == id) return;
    final context = TourAnchors.instance.contextFor(id);
    if (context == null) return;
    _scrolledTo = id;
    unawaited(() async {
      try {
        await Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {
        // Not inside a scrollable, or gone mid-scroll: measured where it is.
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final guide = ref.watch(tourControllerProvider);
    final controller = ref.read(tourControllerProvider.notifier);
    final media = MediaQuery.of(context);
    final reduced = media.disableAnimations;

    if (guide.finishing) {
      return _RewardLayer(
        guide: guide,
        reducedMotion: reduced,
        onDone: controller.close,
      );
    }

    final step = guide.step;
    if (step == null) return const SizedBox.shrink();

    if (_syncedIndex != guide.index) {
      _syncedIndex = guide.index;
      _settling = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncToStep(step);
      });
    }

    final pane = ref.watch(studyPaneProvider);
    var cue = cueFor(guide, viewOf(pane));
    if (cue.needsReturn && _settling) {
      // Say what the step will ask once the screen is there.
      cue = cueFor(
        guide,
        GuideView(onStudy: true, showMaterials: step.onStudyPane, materialsTab: pane.materialsTab),
      );
    }
    if (!_sameAnchors(cue.anchors, _cueAnchors)) {
      _cueAnchors = cue.anchors;
      _scrolledTo = null;
      measureSoon();
    }
    if (cue.anchors.contains(TourAnchorIds.firstVerse) && _scrolledTo == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureVisible(TourAnchorIds.firstVerse);
      });
    }
    final target = cue.gesture == GuideGesture.none ? null : firstOnScreen(cue.anchors, media.size);
    final aimed = target == null ? null : _aimFor(target.$1, target.$2, cue.gesture);
    final point = aimed != null && aimed.isFinite ? aimed : null;

    // The card sits at the bottom, above the tab bar, unless something has
    // taken the bottom of the screen: a sheet, the keyboard, or the very
    // spot the hand is pointing at.
    final keyboard = media.viewInsets.bottom > 0;
    final atTop = keyboard ||
        guide.surface != GuideSurface.none ||
        (point != null && point.dy > media.size.height * 0.58);

    final card = _GuideCard(
      guide: guide,
      step: step,
      cue: cue,
      compact: atTop,
      onSkip: controller.skip,
      onClose: controller.close,
      onNext: controller.next,
      onReturn: () => _syncToStep(step),
    );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          if (point != null)
            Positioned.fill(
              child: GuideHand(gesture: cue.gesture, point: point, reducedMotion: reduced),
            ),
          Positioned(
            left: _screenMargin,
            right: _screenMargin,
            top: atTop ? media.padding.top + 8 : null,
            bottom: atTop ? null : media.padding.bottom + _navBarReserve + 10,
            child: card,
          ),
        ],
      ),
    );
  }

  static bool _sameAnchors(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _RewardLayer extends StatelessWidget {
  const _RewardLayer({required this.guide, required this.reducedMotion, required this.onDone});

  final GuideState guide;
  final bool reducedMotion;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // The one moment the guide holds the screen: it is the end, and the
          // only thing left to do is the button on the card.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: const ColoredBox(color: Color(0xA80F172A)),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 420, maxHeight: media.size.height),
                    child: GuideRewardCard(
                      guide: guide,
                      onDone: onDone,
                      reducedMotion: reducedMotion,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.guide,
    required this.step,
    required this.cue,
    required this.compact,
    required this.onSkip,
    required this.onClose,
    required this.onNext,
    required this.onReturn,
  });

  final GuideState guide;
  final GuideStep step;
  final GuideCue cue;

  /// At the top of the screen, over a sheet or the keyboard: the title and the
  /// checklist go, the instruction stays.
  final bool compact;
  final VoidCallback onSkip;
  final VoidCallback onClose;
  final VoidCallback onNext;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final total = kGuideSteps.length;
    final isLast = guide.index == total - 1;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.touch_app_outlined, size: 15, color: AppTheme.teal),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${GuideCopy.overline} · ${guide.index + 1}/$total',
                  style: AppTheme.overline,
                ),
              ),
              Semantics(
                button: true,
                label: GuideCopy.closeLabel,
                excludeSemantics: true,
                child: InkWell(
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.close, size: 16, color: AppTheme.inkMuted),
                  ),
                ),
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(GuideCopy.title(step.id), style: AppTheme.displaySmall),
            ),
            // Once the step is done the "gelukt" line says it all, and the
            // card gives back the room - the assistant's answer is under it.
            if (step.tasks.length > 1 && !guide.stepDone) ...[
              const SizedBox(height: 8),
              for (final task in step.tasks)
                _TaskLine(label: GuideCopy.task(task), done: guide.done.contains(task)),
            ],
          ],
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Row(
                key: ValueKey(cue.text),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (guide.stepDone) ...[
                    Icon(Icons.check_circle, size: 18, color: AppTheme.teal),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      cue.text,
                      style: (guide.stepDone ? AppTheme.bodyStrong : AppTheme.bodyMuted)
                          .copyWith(height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (!guide.stepDone)
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    GuideCopy.skipLabel,
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.inkMuted,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              const Spacer(),
              if (guide.stepDone)
                SiteButton(
                  label: isLast ? GuideCopy.lastLabel : GuideCopy.nextLabel,
                  expand: false,
                  height: 40,
                  trailingIcon: isLast ? Icons.check : Icons.arrow_forward,
                  onPressed: onNext,
                )
              else if (cue.needsReturn)
                SiteOutlineButton(
                  label: GuideCopy.returnLabel,
                  expand: false,
                  height: 40,
                  onPressed: onReturn,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskLine extends StatelessWidget {
  const _TaskLine({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3, right: 6),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              key: ValueKey(done),
              size: 16,
              color: done ? AppTheme.teal : AppTheme.inkFaint,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppTheme.caption.copyWith(
                color: done ? AppTheme.inkMuted : AppTheme.ink,
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A skipped step coming back once, as a tip, the next time the reader is on
/// its screen - see [GuideTips] for when that is allowed to happen.
class _GuideTipLayer extends ConsumerStatefulWidget {
  const _GuideTipLayer();

  @override
  ConsumerState<_GuideTipLayer> createState() => _GuideTipLayerState();
}

class _GuideTipLayerState extends ConsumerState<_GuideTipLayer> with _Following {
  /// Whether the last measure found the reader on a screen some pending tip
  /// belongs to. A tip is offered on arriving there, not while staying.
  final Map<GuideStepId, bool> _wasOn = {};

  @override
  List<String> get followedAnchors {
    final showing = ref.read(guideTipsProvider).showing;
    return showing == null ? const [] : tipFor(showing).anchors;
  }

  @override
  void initState() {
    super.initState();
    listenToRoute();
    _maybePoll();
  }

  /// Only measures anchors while a tip with a hand is on screen.
  void _maybePoll() {
    if (ref.read(guideTipsProvider).showing != null) {
      startPolling();
      measureSoon();
    } else {
      stopPolling();
    }
  }

  void _offerTip(GuideView view) {
    final tips = ref.read(guideTipsProvider);
    final notifier = ref.read(guideTipsProvider.notifier);
    if (tips.showing != null) {
      // Gone from its screen: a tip is not followed around the app.
      if (!tipFits(tips.showing!, view)) notifier.dismiss();
      return;
    }
    if (!notifier.eligibleAt(DateTime.now())) {
      for (final step in tips.pending) {
        _wasOn[step] = tipFits(step, view);
      }
      return;
    }
    for (final step in tips.pending) {
      final fits = tipFits(step, view);
      final arrived = fits && _wasOn[step] != true;
      _wasOn[step] = fits;
      if (arrived) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(guideTipsProvider.notifier).show(step);
        });
        // One tip per visit.
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tips = ref.watch(guideTipsProvider);
    ref.listen(guideTipsProvider, (previous, next) => _maybePoll());
    final pane = ref.watch(studyPaneProvider);
    final view = viewOf(pane);
    if (tips.pending.isNotEmpty || tips.showing != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _offerTip(view);
      });
    }

    // A tip goes the moment the reader does what it suggests.
    ref.listen(tourControllerProvider.select((g) => g.sheetOpen), (_, open) {
      final showing = ref.read(guideTipsProvider).showing;
      if (open && (showing == GuideStepId.mark || showing == GuideStepId.study)) {
        ref.read(guideTipsProvider.notifier).dismiss();
      }
    });
    if (tips.showing == GuideStepId.swipe && pane.showMaterials ||
        tips.showing == GuideStepId.ask && pane.materialsTab == StudyPaneTabs.assistant) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(guideTipsProvider.notifier).dismiss();
      });
    }

    final showing = tips.showing;
    if (showing == null) return const SizedBox.shrink();

    final media = MediaQuery.of(context);
    final cue = tipFor(showing);
    final target = firstOnScreen(cue.anchors, media.size);
    final aimed = target == null ? null : _aimFor(target.$1, target.$2, cue.gesture);
    final point = aimed != null && aimed.isFinite ? aimed : null;
    final atTop = point != null && point.dy > media.size.height * 0.58;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          if (point != null)
            Positioned.fill(
              child: GuideHand(
                gesture: cue.gesture,
                point: point,
                reducedMotion: media.disableAnimations,
              ),
            ),
          Positioned(
            left: _screenMargin,
            right: _screenMargin,
            top: atTop ? media.padding.top + 8 : null,
            bottom: atTop ? null : media.padding.bottom + _navBarReserve + 10,
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(Icons.lightbulb_outline, size: 18, color: AppTheme.teal),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          cue.text,
                          style: AppTheme.bodyMuted.copyWith(height: 1.45),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => ref.read(guideTipsProvider.notifier).dismiss(),
                      child: const Text('Begrepen'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
