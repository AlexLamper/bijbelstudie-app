import 'dart:async';

import 'package:flutter/widgets.dart';

/// Tells when a chapter (or an uitleg) has been read to its end: the moment
/// the bottom of its text is on screen.
///
/// The rule, the same in the normal reader and the plan reader:
/// - a text taller than the screen counts once it is scrolled to within
///   [endSlack] of its bottom - the last verse is then on screen, only the
///   attribution under it may not be;
/// - a text that fits without scrolling counts after [dwell] on screen, so
///   paging past a short psalm does not tick it.
///
/// Listens to the scroll notifications of the one vertical scroll view under
/// it (including the [ScrollMetricsNotification] of its first layout), so it
/// needs no controller. Fires [onEnd] at most once; give it a new key per
/// chapter so the next chapter starts over.
class ChapterEndDetector extends StatefulWidget {
  const ChapterEndDetector({
    super.key,
    required this.onEnd,
    this.onProgress,
    this.dwell = const Duration(seconds: 3),
    this.enabled = true,
    required this.child,
  });

  /// False while the text under it is still a loading skeleton, which must
  /// never count as read.
  final bool enabled;

  final VoidCallback onEnd;

  /// 0..1: how far the text has been scrolled towards its end. 1 once [onEnd]
  /// fired.
  final ValueChanged<double>? onProgress;
  final Duration dwell;
  final Widget child;

  /// Distance from the bottom of the scroll view that still counts as the end:
  /// more than the attribution and padding under the last verse.
  static const double endSlack = 96;

  @override
  State<ChapterEndDetector> createState() => _ChapterEndDetectorState();
}

class _ChapterEndDetectorState extends State<ChapterEndDetector> {
  bool _fired = false;
  Timer? _dwell;
  double _progress = -1;

  @override
  void didUpdateWidget(ChapterEndDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _dwell?.cancel();
      _dwell = null;
    }
  }

  @override
  void dispose() {
    _dwell?.cancel();
    super.dispose();
  }

  bool _onNotification(Notification notification) {
    if (!widget.enabled) return false;
    final ScrollMetrics metrics;
    if (notification is ScrollMetricsNotification) {
      if (notification.depth != 0) return false;
      metrics = notification.metrics;
    } else if (notification is ScrollUpdateNotification || notification is ScrollEndNotification) {
      final scroll = notification as ScrollNotification;
      if (scroll.depth != 0) return false;
      metrics = scroll.metrics;
    } else {
      return false;
    }
    if (metrics.axis != Axis.vertical || !metrics.hasContentDimensions) return false;
    _evaluate(metrics);
    return false;
  }

  void _evaluate(ScrollMetrics metrics) {
    if (_fired) return;
    final fits = metrics.maxScrollExtent - metrics.minScrollExtent <= ChapterEndDetector.endSlack;
    if (fits) {
      _dwell ??= Timer(widget.dwell, _onDwell);
      return;
    }
    // Grown past the screen (a larger font): the dwell no longer applies.
    _dwell?.cancel();
    _dwell = null;

    final span = metrics.maxScrollExtent - metrics.minScrollExtent - ChapterEndDetector.endSlack;
    _report(((metrics.pixels - metrics.minScrollExtent) / span).clamp(0.0, 1.0));
    if (metrics.extentAfter <= ChapterEndDetector.endSlack) _fire();
  }

  void _onDwell() {
    if (!mounted || _fired) return;
    // A pane that is not on screen (the other half of `/studie`) has its
    // tickers muted; nobody is reading it.
    if (!TickerMode.of(context)) {
      _dwell = null;
      return;
    }
    _fire();
  }

  void _fire() {
    _fired = true;
    _dwell?.cancel();
    _report(1);
    widget.onEnd();
  }

  void _report(double progress) {
    if ((progress - _progress).abs() < 0.01 && progress != 1) return;
    _progress = progress;
    widget.onProgress?.call(progress);
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<Notification>(onNotification: _onNotification, child: widget.child);
}
