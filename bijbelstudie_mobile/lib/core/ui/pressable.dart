import 'dart:async';

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tap acknowledgement shared by every custom button, card and tab: a light
/// haptic tick plus a small press-down scale, so a tap reads as "received"
/// before the next screen or sheet arrives.
abstract final class AppHaptics {
  /// For choosing between options: tabs, segments, filter pills.
  static void selection() => unawaited(HapticFeedback.selectionClick());

  /// For committing an action: buttons and tappable cards.
  static void light() => unawaited(HapticFeedback.lightImpact());

  /// [onTap] with a [light] tick in front of it; `null` stays `null` so a
  /// disabled control keeps rendering as disabled.
  static VoidCallback? tap(VoidCallback? onTap) {
    if (onTap == null) return null;
    return () {
      light();
      onTap();
    };
  }

  /// As [tap], with a [selection] tick.
  static VoidCallback? select(VoidCallback? onTap) {
    if (onTap == null) return null;
    return () {
      selection();
      onTap();
    };
  }
}

/// Scales [child] down a touch while a finger is on it and springs it back on
/// release. It only listens to raw pointers, so it never competes with the
/// child's own InkWell / button in the gesture arena, and a drag that turns
/// into a scroll lets go of the press as soon as it passes the touch slop.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 0.96,
  });

  final Widget child;

  /// Off for a disabled control, which should not look pressable.
  final bool enabled;

  /// Scale while pressed. Buttons use ~0.96; large cards want less travel.
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  Offset? _origin;

  void _set(bool down) {
    if (_down == down) return;
    setState(() => _down = down);
  }

  @override
  void didUpdateWidget(Pressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _down = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: (e) {
        _origin = e.position;
        _set(true);
      },
      onPointerMove: (e) {
        final origin = _origin;
        if (origin != null && (e.position - origin).distance > kTouchSlop) {
          _origin = null;
          _set(false);
        }
      },
      onPointerUp: (_) {
        _origin = null;
        _set(false);
      },
      onPointerCancel: (_) {
        _origin = null;
        _set(false);
      },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        // Quick in, a slightly longer spring out - the release is what reads.
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
