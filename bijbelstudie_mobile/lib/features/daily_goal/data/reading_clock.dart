import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../present/daily_goal_providers.dart';

/// Counts reading time for the daily goal.
///
/// A second counts when all three hold:
///
/// - the app is in the foreground;
/// - a reading screen is on top: the reader (`/read`), the split reader
///   (`/study`) or a lesson (`/studie/...`);
/// - the reader touched the screen in the last [idle] - a scroll, a tap, a
///   page turn. A phone left on a chapter on the nightstand adds nothing.
///
/// Ticks every [tick] while the first two hold and stops its timer otherwise,
/// so it costs nothing on every other screen. The minutes go to
/// [DailyGoalController.addSeconds], which reports them to the server; the
/// website's twin is `components/dailyGoal/ReadingClock.tsx`, with the same
/// two-minute rule.
class ReadingClock with WidgetsBindingObserver {
  ReadingClock(this._ref);

  final Ref _ref;

  static const tick = Duration(seconds: 5);
  static const idle = Duration(minutes: 2);

  Timer? _timer;
  GoRouter? _router;
  DateTime _lastTouch = DateTime.now();
  bool _foreground = true;
  bool _onReadingRoute = false;
  bool _attached = false;

  /// Whether [path] is a screen where reading happens.
  static bool isReadingPath(String path) =>
      path == '/read' ||
      path == '/study' ||
      path.startsWith('/studie/');

  void attach() {
    if (_attached) return;
    _attached = true;
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    _foreground = binding.lifecycleState == null ||
        binding.lifecycleState == AppLifecycleState.resumed;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    try {
      _router = _ref.read(routerProvider);
      _router!.routerDelegate.addListener(_onRoute);
      _onRoute();
    } catch (_) {
      // No router (a test container): the clock simply never runs.
    }
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _router?.routerDelegate.removeListener(_onRoute);
    _stop();
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent || event is PointerMoveEvent || event is PointerScrollEvent) {
      _lastTouch = DateTime.now();
    }
  }

  void _onRoute() {
    final router = _router;
    if (router == null) return;
    String path;
    try {
      path = router.routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      return;
    }
    final reading = isReadingPath(path);
    if (reading && !_onReadingRoute) _lastTouch = DateTime.now();
    if (!reading && _onReadingRoute) _flush();
    _onReadingRoute = reading;
    _update();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg && !_foreground) _lastTouch = DateTime.now();
    if (!fg && _foreground) _flush();
    _foreground = fg;
    _update();
  }

  void _update() {
    if (_foreground && _onReadingRoute) {
      _timer ??= Timer.periodic(tick, (_) => _onTick());
    } else {
      _stop();
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _onTick() {
    if (DateTime.now().difference(_lastTouch) > idle) return;
    try {
      _ref.read(dailyGoalProvider.notifier).addSeconds(tick.inSeconds);
    } catch (_) {}
  }

  void _flush() {
    try {
      unawaited(_ref.read(dailyGoalProvider.notifier).flush());
    } catch (_) {}
  }
}

/// The app's one reading clock. Read once from the lifecycle wiring
/// (`app_lifecycle.dart`), which is what attaches it.
final readingClockProvider = Provider<ReadingClock>((ref) {
  final clock = ReadingClock(ref);
  ref.onDispose(clock.detach);
  return clock;
});
