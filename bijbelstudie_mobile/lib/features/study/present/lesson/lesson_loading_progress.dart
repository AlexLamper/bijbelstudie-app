import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Captions shown while a lesson's quiz is being put together on the server.
const List<String> kQuizLoadingMessages = [
  'Je toetsvragen worden samengesteld...',
  'We lezen het hoofdstuk nog eens door...',
  'Vragen afstemmen op deze les...',
  'Antwoordopties worden gemaakt...',
  'De kern van de les op een rij...',
  'Elke vraag wordt zorgvuldig nagekeken...',
  'Nog even geduld...',
  'Bijna klaar...',
];

/// A calm stand-in for a spinner on loads of unknown length (AI generation).
///
/// The bar creeps forward quickly at first and then slows, approaching ~90%
/// without reaching it. Below it a muted caption cross-fades through
/// [messages] every [messageInterval]. Once [done] turns true the bar fills to
/// 100%, the whole thing fades out and [onFinished] fires, so the caller can
/// swap in the real content.
class LessonLoadingProgress extends StatefulWidget {
  const LessonLoadingProgress({
    super.key,
    this.messages = kQuizLoadingMessages,
    this.done = false,
    this.onFinished,
    this.messageInterval = const Duration(seconds: 2),
  });

  final List<String> messages;
  final bool done;
  final VoidCallback? onFinished;
  final Duration messageInterval;

  @override
  State<LessonLoadingProgress> createState() => _LessonLoadingProgressState();
}

class _LessonLoadingProgressState extends State<LessonLoadingProgress>
    with TickerProviderStateMixin {
  /// Seconds the creep is modelled over; the bar is ~90% by the end of it.
  static const _creepSeconds = 60;

  /// Time constant of the exponential ease: ~57% after 7s, ~86% after 22s.
  static const _tau = 7.0;
  static const _ceiling = 0.9;

  late final AnimationController _creep = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _creepSeconds),
  );
  late final AnimationController _finish = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  Timer? _ticker;
  int _message = 0;
  double _finishFrom = 0;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _creep.forward();
    _ticker = Timer.periodic(widget.messageInterval, (_) {
      if (!mounted || widget.messages.length < 2) return;
      setState(() {
        // Loop over everything but the opener once the list runs out.
        final next = _message + 1;
        _message = next < widget.messages.length ? next : 1;
      });
    });
    if (widget.done) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startFinish());
    }
  }

  @override
  void didUpdateWidget(LessonLoadingProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.done && !oldWidget.done) _startFinish();
  }

  double get _creepValue {
    final seconds = _creep.value * _creepSeconds;
    return _ceiling * (1 - math.exp(-seconds / _tau));
  }

  void _startFinish() {
    if (!mounted || _finishing) return;
    _finishing = true;
    _finishFrom = _creepValue;
    _creep.stop();
    _ticker?.cancel();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      widget.onFinished?.call();
      return;
    }
    _finish.forward().whenComplete(() {
      if (mounted) widget.onFinished?.call();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _creep.dispose();
    _finish.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final messages = widget.messages;
    final caption = messages.isEmpty
        ? ''
        : messages[_message.clamp(0, messages.length - 1)];

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: AnimatedBuilder(
            animation: Listenable.merge([_creep, _finish]),
            builder: (context, child) {
              // First half of the finish fills the bar, second half fades.
              final fill = Curves.easeOut.transform(
                (_finish.value / 0.5).clamp(0.0, 1.0),
              );
              final fade = ((_finish.value - 0.5) / 0.5).clamp(0.0, 1.0);
              final progress = _finishing
                  ? _finishFrom + (1 - _finishFrom) * fill
                  : _creepValue;
              return Opacity(
                opacity: 1 - fade,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Bar(progress: progress),
                    child!,
                  ],
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 450),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.center,
                    children: [...previous, if (current != null) current],
                  ),
                  child: Text(
                    caption,
                    key: ValueKey(_message),
                    textAlign: TextAlign.center,
                    style: AppTheme.caption,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);
    return Semantics(
      value: '${(progress * 100).round()}%',
      child: Container(
        height: 4,
        decoration: BoxDecoration(color: AppTheme.tealSoft, borderRadius: radius),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(color: AppTheme.teal, borderRadius: radius),
          ),
        ),
      ),
    );
  }
}
