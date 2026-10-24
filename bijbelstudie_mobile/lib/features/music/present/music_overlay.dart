import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/lucide_icon.dart';
import '../../bible/present/reader_chrome.dart';
import '../../onboarding/present/tour_controller.dart';
import '../data/music_tracks.dart';
import '../domain/music_models.dart';
import 'music_menu_sheet.dart';
import 'music_player_controller.dart';
import 'music_stopped_toast.dart';
import 'music_widgets.dart';

/// The playing pill, the bubble it shrinks into, the first-time swipe hint and
/// "Muziek gestopt", floating over every tab.
///
/// Mounted once, by `MainScaffold`, around the shell's body. Pages outside the
/// shell (paywall, onboarding) do not show it; the music plays on regardless.
class MusicOverlay extends ConsumerStatefulWidget {
  const MusicOverlay({
    super.key,
    required this.child,
    required this.inReader,
    required this.readerChromeVisible,
  });

  final Widget child;

  /// The reader is showing. The pill then floats above its chapter pager
  /// (Vorige / Volgende) rather than above the tab bar.
  final bool inReader;

  /// While the reader has hidden its chrome to read, a pill opened from the
  /// bubble goes back to being one after [autoShrinkDelay].
  final bool readerChromeVisible;

  static const autoShrinkDelay = Duration(milliseconds: 3500);

  /// A scroll this long shrinks the pill...
  static const scrollShrinkDistance = 60.0;

  /// ...but not this soon after it was expanded, or the scroll that is still
  /// settling would undo the tap.
  static const scrollShrinkGrace = Duration(milliseconds: 600);

  /// A downward swipe past this shrinks the pill; less springs back.
  static const swipeShrinkDistance = 24.0;

  @override
  ConsumerState<MusicOverlay> createState() => _MusicOverlayState();
}

class _MusicOverlayState extends ConsumerState<MusicOverlay>
    with SingleTickerProviderStateMixin {
  static const _morph = Cubic(0.2, 0.8, 0.2, 1);
  static const _pillWidth = 236.0;
  static const _pillHeight = 46.0;
  static const _bubbleSize = 44.0;

  late final AnimationController _springBack;

  double _drag = 0;
  double _springFrom = 0;
  DateTime _expandedAt = DateTime.now();
  double _scrolled = 0;
  Timer? _autoShrink;

  @override
  void initState() {
    super.initState();
    _springBack = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(_onSpringBack);
  }

  @override
  void dispose() {
    _autoShrink?.cancel();
    _springBack.dispose();
    super.dispose();
  }

  MusicPlayerController get _controller => ref.read(musicPlayerProvider.notifier);

  void _onSpringBack() {
    final t = Curves.easeOutCubic.transform(_springBack.value);
    setState(() => _drag = _springFrom * (1 - t));
  }

  void _releaseDrag(bool reduceMotion) {
    if (_drag > MusicOverlay.swipeShrinkDistance) _controller.shrink();
    if (reduceMotion || _drag == 0) {
      setState(() => _drag = 0);
      return;
    }
    _springFrom = _drag;
    _springBack.forward(from: 0);
  }

  void _onPlayerChanged(MusicState? previous, MusicState next) {
    final becameExpanded =
        next.isPlaying && !next.mini && (previous == null || !previous.isPlaying || previous.mini);
    if (!becameExpanded) return;
    _expandedAt = DateTime.now();
    _scrolled = 0;
    _autoShrink?.cancel();
    if (next.expandedFromBubble) {
      _autoShrink = Timer(MusicOverlay.autoShrinkDelay, () {
        if (!mounted) return;
        final state = ref.read(musicPlayerProvider);
        final stillReading = widget.inReader && !widget.readerChromeVisible;
        if (state.isPlaying && !state.mini && state.expandedFromBubble && stillReading) {
          _controller.shrink();
        }
      });
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification || notification.dragDetails == null) {
      return false;
    }
    if (notification.metrics.axis != Axis.vertical) return false;
    final state = ref.read(musicPlayerProvider);
    if (!state.isPlaying || state.mini) return false;
    if (DateTime.now().difference(_expandedAt) < MusicOverlay.scrollShrinkGrace) return false;
    _scrolled += (notification.scrollDelta ?? 0).abs();
    if (_scrolled >= MusicOverlay.scrollShrinkDistance) {
      _scrolled = 0;
      _controller.shrink();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(musicPlayerProvider, _onPlayerChanged);
    final state = ref.watch(musicPlayerProvider);
    final touring = ref.watch(tourControllerProvider.select((t) => t.active));
    final pagerHeight = widget.inReader ? ref.watch(readerPagerHeightProvider) : 0.0;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // Typing (a note, a search) pushes the shell's body up above the keyboard;
    // a pill riding along would cover the very field being typed in.
    // Read from the view: the shell Scaffold strips the inset from its body's
    // MediaQuery when it resizes for the keyboard.
    final keyboardOpen = MediaQueryData.fromView(View.of(context)).viewInsets.bottom > 0;
    final shown = !touring && !keyboardOpen;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (shown)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (state.isPlaying)
                      ..._pill(state, constraints.maxWidth, pagerHeight, reduceMotion),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: pagerHeight + 14,
                      child: MusicStoppedToast(
                        visible: state.showStoppedMessage,
                        reduceMotion: reduceMotion,
                        onUndo: () {
                          AppHaptics.light();
                          _controller.undoStop();
                        },
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

  List<Widget> _pill(MusicState state, double width, double base, bool reduceMotion) {
    AppTheme.dependOn(context);
    final mini = state.mini;
    final track = kMusicTracks[state.trackIndex];
    final morph = reduceMotion ? Duration.zero : const Duration(milliseconds: 350);
    final surface = reduceMotion ? Duration.zero : const Duration(milliseconds: 250);
    final fade = reduceMotion ? Duration.zero : const Duration(milliseconds: 200);
    final pillBottom = base + 14;
    final showHint = !mini && !state.hintSeen && _drag == 0;

    return [
      Positioned(
        left: 0,
        right: 0,
        bottom: pillBottom + _pillHeight + 10,
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: showHint ? 1 : 0,
            duration: fade,
            child: Center(
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.tealStrong,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
                child: const Text(
                  'Veeg omlaag om te verkleinen',
                  style: TextStyle(
                    fontFamily: AppTheme.sansFontName,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      AnimatedPositioned(
        duration: morph,
        curve: _morph,
        left: mini ? width - 16 - _bubbleSize : (width - _pillWidth) / 2,
        bottom: mini ? base + 16 : pillBottom,
        width: mini ? _bubbleSize : _pillWidth,
        height: mini ? _bubbleSize : _pillHeight,
        child: Transform.translate(
          offset: Offset(0, _drag),
          child: Semantics(
            button: true,
            label: mini
                ? 'Achtergrondmuziek: ${track.name}. Vergroten'
                : 'Achtergrondmuziek: ${track.name}. Muziekmenu openen',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                AppHaptics.light();
                if (mini) {
                  _controller.expand();
                } else {
                  showMusicMenuSheet(context);
                }
              },
              onVerticalDragStart: mini ? null : (_) => _springBack.stop(),
              onVerticalDragUpdate: mini
                  ? null
                  : (details) => setState(() => _drag = math.max(0, _drag + details.delta.dy)),
              onVerticalDragEnd: mini ? null : (_) => _releaseDrag(reduceMotion),
              onVerticalDragCancel: mini ? null : () => _releaseDrag(reduceMotion),
              child: AnimatedContainer(
                duration: surface,
                curve: _morph,
                // The 1px ring is a border here, so the padding is 1 short of
                // the design's 16 / 13.5 to land the note in the same place.
                padding: EdgeInsets.only(left: mini ? 12.5 : 15, right: mini ? 0 : 3),
                decoration: BoxDecoration(
                  color: AppTheme.paperRaised,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  border: Border.all(color: AppTheme.rule),
                  boxShadow: mini
                      ? musicFloatShadow(blur: 14, y: 4, alpha: 0.12)
                      : musicFloatShadow(),
                ),
                // The row is always laid out at the pill's full width and
                // clipped, so the morph never squeezes it into an overflow.
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: _pillWidth - 20,
                    child: SizedBox(
                      width: _pillWidth - 20,
                      child: Row(
                        children: [
                          LucideIcon(MusicIcons.note, size: 17, color: AppTheme.teal),
                          const SizedBox(width: 8),
                          Expanded(
                            child: IgnorePointer(
                              ignoring: mini,
                              child: AnimatedOpacity(
                                opacity: mini ? 0 : 1,
                                duration: fade,
                                child: _PillControls(
                                  track: track,
                                  paused: state.paused,
                                  onTogglePause: () {
                                    AppHaptics.light();
                                    _controller.togglePause();
                                  },
                                  onStop: () {
                                    AppHaptics.light();
                                    _controller.stop();
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

class _PillControls extends StatelessWidget {
  const _PillControls({
    required this.track,
    required this.paused,
    required this.onTogglePause,
    required this.onStop,
  });

  final MusicTrack track;
  final bool paused;
  final VoidCallback onTogglePause;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            track.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.sansFontName,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.ink,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(width: 1, height: 20, color: AppTheme.rule),
        const SizedBox(width: 6),
        _PillButton(
          semantics: paused ? 'Afspelen' : 'Pauzeren',
          onTap: onTogglePause,
          child: LucideIcon(
            paused ? MusicIcons.play : MusicIcons.pause,
            size: 15,
            color: AppTheme.ink,
          ),
        ),
        _PillButton(
          semantics: 'Muziek stoppen',
          onTap: onStop,
          child: LucideIcon(MusicIcons.close, size: 15, color: AppTheme.inkMuted, strokeWidth: 2.2),
        ),
      ],
    );
  }
}

/// A 34x34 target inside the pill. Its own tap wins the gesture arena over the
/// pill's, so pausing never also opens the menu.
class _PillButton extends StatelessWidget {
  const _PillButton({required this.semantics, required this.onTap, required this.child});

  final String semantics;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(width: 34, height: 34, child: Center(child: child)),
      ),
    );
  }
}
