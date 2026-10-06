import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../domain/palette.dart';
import '../domain/verse_scene.dart';
import 'verse_scene_painter.dart';

/// The daily verse's landscape, alive.
///
/// Replaces the photograph the dagtekst card used to carry. Motion is
/// deliberately almost nothing (`AVATAR_NOTIFICATIONS_PLAN.md` §6.2): the sky
/// warms and dims on a ninety-second breath and two or three clouds cross in
/// minutes, at five frames a second. It stops entirely when the reader asked
/// for less motion, and Flutter's own [TickerMode] stops it whenever the card
/// is not on the visible route.
class VerseSceneBackdrop extends StatefulWidget {
  const VerseSceneBackdrop({
    super.key,
    required this.verse,
    this.animate = true,
  });

  final VerseScene verse;

  /// False pins the scene to a single still frame - used where the card is a
  /// thumbnail, and forced on when the platform asks for reduced motion.
  final bool animate;

  @override
  State<VerseSceneBackdrop> createState() => _VerseSceneBackdropState();
}

class _VerseSceneBackdropState extends State<VerseSceneBackdrop>
    with SingleTickerProviderStateMixin {
  static const _frame = Duration(milliseconds: 200);

  Ticker? _ticker;
  final ValueNotifier<double> _timeMs = ValueNotifier(0);
  late VerseSceneArt _art = VerseSceneArt(widget.verse);
  late TreePalette _palette = verseScenePalette(widget.verse);
  int _paletteHour = DateTime.now().hour;
  Duration _lastFrame = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(VerseSceneBackdrop old) {
    super.didUpdateWidget(old);
    if (old.verse.key != widget.verse.key) {
      _art = VerseSceneArt(widget.verse);
      _palette = verseScenePalette(widget.verse);
      _paletteHour = DateTime.now().hour;
    }
    _syncTicker();
  }

  void _syncTicker() {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final wanted = widget.animate && !reduced;
    if (wanted && _ticker == null) {
      _ticker = createTicker(_onTick)..start();
    } else if (!wanted && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
      _timeMs.value = 0;
    }
  }

  void _onTick(Duration elapsed) {
    // Five frames a second is plenty for weather that takes minutes to cross,
    // and it keeps a full-bleed CustomPaint off the hot path.
    if (elapsed - _lastFrame < _frame) return;
    _lastFrame = elapsed;
    final hour = DateTime.now().hour;
    if (hour != _paletteHour) {
      _paletteHour = hour;
      _palette = verseScenePalette(widget.verse);
    }
    _timeMs.value = elapsed.inMilliseconds.toDouble();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _timeMs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: _timeMs,
        builder: (context, timeMs, _) => CustomPaint(
          painter: VerseScenePainter(art: _art, palette: _palette, timeMs: timeMs),
          size: Size.infinite,
          isComplex: true,
          willChange: _ticker != null,
        ),
      ),
    );
  }
}
