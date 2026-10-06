import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../progress_tree/domain/verse_scene.dart';
import '../../data/daily_verse_background_store.dart';
import 'daily_verse_photo.dart';
import 'daily_verse_tree_backdrop.dart';

/// One of the card's backgrounds, full bleed.
///
/// [DailyVerseBackground.tree] is the reader's progress tree (itself falling back
/// to the day's photo while there is no tree to show);
/// [DailyVerseBackground.photo] is the day's nature photo.
class DailyVerseBackgroundView extends StatelessWidget {
  const DailyVerseBackgroundView({
    super.key,
    required this.kind,
    required this.scene,
    this.still = false,
  });

  final DailyVerseBackground kind;
  final VerseScene scene;

  /// One static frame, no ticker: the off-screen share image.
  final bool still;

  @override
  Widget build(BuildContext context) {
    return switch (kind) {
      DailyVerseBackground.tree => DailyVerseBackdrop(scene: scene, still: still),
      DailyVerseBackground.photo => DailyVersePhoto(dayKey: scene.key),
    };
  }
}

/// The reader's chosen background, without paging - the expanded card.
class DailyVerseSelectedBackground extends ConsumerWidget {
  const DailyVerseSelectedBackground({super.key, required this.scene});

  final VerseScene scene;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DailyVerseBackgroundView(
      kind: ref.watch(dailyVerseBackgroundProvider),
      scene: scene,
    );
  }
}

/// Both backgrounds side by side, slid by [page] (0 = first, 1 = second).
///
/// A page that is entirely off the card is kept alive (no rebuild, no flash
/// when it slides back in) but neither painted nor ticking.
class DailyVerseBackgroundPager extends StatelessWidget {
  const DailyVerseBackgroundPager({
    super.key,
    required this.scene,
    required this.page,
  });

  final VerseScene scene;
  final Animation<double> page;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: page,
      builder: (context, _) {
        final at = page.value;
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final kind in DailyVerseBackground.values)
                _page(kind, kind.index - at),
            ],
          ),
        );
      },
    );
  }

  Widget _page(DailyVerseBackground kind, double offset) {
    final visible = offset.abs() < 0.999;
    return Visibility(
      key: ValueKey(kind),
      visible: visible,
      maintainState: true,
      child: TickerMode(
        enabled: visible,
        child: FractionalTranslation(
          translation: Offset(offset, 0),
          child: DailyVerseBackgroundView(kind: kind, scene: scene),
        ),
      ),
    );
  }
}

/// The page indicator in the card's top-right corner: the current page's dot
/// white, the other a thin white.
class DailyVersePageDots extends StatelessWidget {
  const DailyVersePageDots({super.key, required this.page});

  final Animation<double> page;

  static const double _dot = 6;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: page,
      builder: (context, _) {
        final at = page.value.clamp(0.0, 1.0);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final kind in DailyVerseBackground.values) ...[
              if (kind.index > 0) const SizedBox(width: 5),
              Container(
                width: _dot,
                height: _dot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(
                    alpha: 1 - 0.6 * (kind.index - at).abs().clamp(0.0, 1.0),
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x40000000), blurRadius: 3),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Drives [DailyVerseBackgroundPager] from a horizontal drag on the card.
///
/// Owned by the card's state; [page] runs 0..1 with a little give past
/// either end, and settles on a whole page when the drag ends.
class DailyVersePaging {
  DailyVersePaging(TickerProvider vsync, {required int initial})
    : _controller = AnimationController.unbounded(
        vsync: vsync,
        value: initial.toDouble(),
      );

  final AnimationController _controller;
  bool _dragging = false;

  Animation<double> get page => _controller;

  static final int _last = DailyVerseBackground.values.length - 1;

  void dragStart() {
    _dragging = true;
    _controller.stop();
  }

  void dragUpdate(DragUpdateDetails details, double width) {
    if (width <= 0) return;
    var delta = -(details.primaryDelta ?? details.delta.dx) / width;
    final value = _controller.value;
    // Resistance past the first and last page, like a scroll's overscroll.
    if ((value <= 0 && delta < 0) || (value >= _last && delta > 0)) {
      delta *= 0.3;
    }
    _controller.value = (value + delta).clamp(-0.12, _last + 0.12);
  }

  /// Settles on the nearest page, or the next one in the fling's direction,
  /// and returns it.
  int dragEnd(DragEndDetails details) {
    _dragging = false;
    final velocity = details.primaryVelocity ?? 0;
    final value = _controller.value;
    final int target;
    if (velocity < -300) {
      target = value.ceil().clamp(0, _last);
    } else if (velocity > 300) {
      target = value.floor().clamp(0, _last);
    } else {
      target = value.round().clamp(0, _last);
    }
    _controller.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    return target;
  }

  void dragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _controller.animateTo(
      _controller.value.round().clamp(0, _last).toDouble(),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// Follows a choice that came from elsewhere (restored from disk, another
  /// account) - unless the reader is mid-swipe.
  void sync(int page) {
    if (_dragging || _controller.isAnimating) return;
    _controller.value = page.toDouble();
  }

  void dispose() => _controller.dispose();
}
