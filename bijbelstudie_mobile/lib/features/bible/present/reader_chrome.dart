import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the app chrome around the reader - its own top bar and the shell's
/// bottom tab bar - is currently shown.
///
/// The reader owns the *decision* (it is the only screen that watches the
/// scroll direction) but the tab bar is built by `MainScaffold`, which sits
/// above every tab. A provider is the only place both can meet.
///
/// Contract: default `true`; the reader flips it while the chapter is scrolled
/// and restores it when it is left. `MainScaffold` additionally ignores this
/// value outside `/read`, so no other screen can ever be stranded without a
/// tab bar even if a reset were missed.
class ReaderChromeVisibility extends Notifier<bool> {
  @override
  bool build() => true;

  void setVisible(bool visible) {
    if (state != visible) state = visible;
  }

  void show() => setVisible(true);

  void hide() => setVisible(false);
}

final readerChromeVisibleProvider = NotifierProvider<ReaderChromeVisibility, bool>(
  ReaderChromeVisibility.new,
);

/// Slides a bar out along its own axis and collapses the space it held, in one
/// motion, so the content next to it moves in step instead of jumping.
///
/// [axisAlignment] is -1 for a bar pinned to the top (it slides up out of view)
/// and 1 for a bar pinned to the bottom.
///
/// Falls back to an instant toggle when the platform asks for reduced motion.
class ReaderChromeReveal extends StatefulWidget {
  const ReaderChromeReveal({
    super.key,
    required this.visible,
    required this.axisAlignment,
    required this.child,
  });

  final bool visible;
  final double axisAlignment;
  final Widget child;

  static const Duration duration = Duration(milliseconds: 220);

  @override
  State<ReaderChromeReveal> createState() => _ReaderChromeRevealState();
}

class _ReaderChromeRevealState extends State<ReaderChromeReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ReaderChromeReveal.duration,
    value: widget.visible ? 1 : 0,
  );

  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  bool get _reducedMotion => MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void didUpdateWidget(covariant ReaderChromeReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible == widget.visible) return;

    if (_reducedMotion) {
      _controller.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Position and opacity move together, on the same curve, so the bar
    // reads as floating away rather than shrinking or snapping: it slides
    // off along its own axis while it fades, and the space it held
    // collapses in the same motion so the content next to it glides into
    // place instead of jumping once the bar is gone.
    final offset = widget.axisAlignment < 0
        ? Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        : Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero);
    return ClipRect(
      child: SizeTransition(
        sizeFactor: _curve,
        axisAlignment: widget.axisAlignment,
        child: SlideTransition(
          position: offset.animate(_curve),
          child: FadeTransition(opacity: _curve, child: widget.child),
        ),
      ),
    );
  }
}
