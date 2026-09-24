import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../domain/catalog.dart';
import '../../domain/growth.dart';
import '../../domain/growth_copy.dart';
import '../../domain/scenes.dart';
import '../../domain/species.dart';
import '../../domain/stages.dart';
import '../../domain/tree_state.dart';
import '../tree_view.dart';

/// The playback runs to here (ten jaarringen), or to the reader's own step
/// when that is further.
const int kWholeGrowthLastStep = 30;

/// One step per this long while playing.
const Duration kWholeGrowthStep = Duration(milliseconds: 700);

/// The growth between two steps; the tree rests for what is left of
/// [kWholeGrowthStep].
const int kWholeGrowthTweenMs = 600;

/// What a [TreeView] draws a step from: its `level`, `frac` and `floor` - the
/// same three a tween's start ([TreeFrom]) is made of.
typedef WholeGrowthInputs = ({int level, double frac, GrowthFloor? floor});

/// The inputs that draw this account's tree on step [n]. The website's
/// `inputsForStep` in `WholeGrowthDialog.tsx`.
///
/// Not `at`, as the Groei ladder draws: a tween can only start from a level, a
/// frac and a floor, and `at` hangs fruit by a different rule than a floored
/// tree does - a tween from one to the other would drop and regrow fruit on
/// every step. Every step is drawn the way a tween's start is, so the start of
/// each tween is exactly the picture that was on screen before it.
///
/// - The reader's own step ([step]): their own [level], [frac] and floor, the
///   stage's picture exactly.
/// - Any other step the account stands on at some level: the level it first
///   stands on it ([levelForStep]), at the start of that level. Its fruit and
///   traits are the ones the account had, or will have, there.
/// - The steps a head start skipped (a floor lifts level 1 past them): level
///   1, lifted to step [n] by a floor of its own. Level 1 carries no traits or
///   fruit, so nothing but the wood differs between them.
WholeGrowthInputs wholeGrowthInputs(
  int n,
  GrowthFloor? floor, {
  required int step,
  required int level,
  required double frac,
}) {
  if (n == step) return (level: level, frac: frac, floor: floor);
  if (n >= structuralStep(1, floor)) return (level: levelForStep(n, floor), frac: 0, floor: floor);
  return (level: 1, frac: 0, floor: n > 1 ? GrowthFloor(from: 1, to: n.toDouble()) : null);
}

/// Opens "Bekijk de hele groei" on [tree], drawn as the studio stage draws it
/// ([species], [scene]). Only ever from its button, never on its own.
///
/// A full-screen route: while it is up the studio underneath is offstage and
/// its tickers are muted, so the one animated tree is the one in the player.
Future<void> showWholeGrowth(
  BuildContext context, {
  required TreeState tree,
  required TreeSpecies species,
  required TreeSceneId scene,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => WholeGrowthPlayer(
        seed: tree.seed,
        species: species,
        scene: scene,
        level: tree.level,
        frac: tree.progress,
        step: tree.step,
        floor: tree.floor,
        reducedMotion: tree.reducedMotion,
      ),
    ),
  );
}

/// "Zo groeit je eik": the reader's own tree - their seed, the species on the
/// stage, their scene and floor - from step 1 to step 30. The mirror of the
/// website's `WholeGrowthDialog.tsx`.
///
/// Playing, it moves one step every 700 ms with the growth tween from the step
/// before. The slider, "Naar nu" and "Opnieuw" jump straight to a step's end
/// state. Under reduced motion (the account's "minder beweging" or the system
/// setting) nothing plays by itself: it opens on the reader's own step, and
/// "Afspelen" steps through end states only.
///
/// Light on a low-end Android: the screen rebuilds once per step, never per
/// frame - the tween and the sway run inside [TreeView]'s own painter - and
/// every step's scene comes from the scene cache, so each is generated once
/// and the start of a tween is the scene already on screen. Full health: this
/// shows how the tree grows, not how it looks after a week away.
class WholeGrowthPlayer extends StatefulWidget {
  const WholeGrowthPlayer({
    super.key,
    required this.seed,
    required this.species,
    required this.scene,
    required this.level,
    required this.frac,
    required this.step,
    required this.floor,
    this.reducedMotion = false,
  });

  final String seed;
  final TreeSpecies species;
  final TreeSceneId scene;

  /// The account's level and its progress through it: the "Nu" step is drawn
  /// from these.
  final int level;
  final double frac;

  /// `levensboom.growth.step`.
  final int step;

  /// `levensboom.growth.floor`.
  final GrowthFloor? floor;

  /// The account's stored preference; the system setting is read here too.
  final bool reducedMotion;

  @override
  State<WholeGrowthPlayer> createState() => _WholeGrowthPlayerState();
}

class _WholeGrowthPlayerState extends State<WholeGrowthPlayer> {
  bool _started = false;

  /// Read once, before the first frame, so a reduced-motion reader never sees
  /// the autoplay start.
  bool _reduced = false;

  late int _shown;

  /// The step the running tween grows from; null shows [_shown] as it stands.
  int? _tweenFrom;

  Timer? _timer;

  bool get _playing => _timer != null;

  int get _last => math.max(kWholeGrowthLastStep, widget.step);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduced = widget.reducedMotion || MediaQuery.maybeDisableAnimationsOf(context) == true;
    _shown = _reduced ? widget.step.clamp(1, _last) : 1;
    if (!_reduced) _play();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _play() {
    _timer?.cancel();
    _timer = Timer.periodic(kWholeGrowthStep, (_) => _advance());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _advance() {
    if (!mounted) return;
    setState(() {
      if (_shown >= _last) {
        _stop();
        return;
      }
      _tweenFrom = _shown;
      _shown += 1;
      // Looping off: the last step grows in and the playback stops there.
      if (_shown >= _last) _stop();
    });
  }

  void _jump(int n) {
    setState(() {
      _stop();
      _tweenFrom = null;
      _shown = n.clamp(1, _last);
    });
  }

  void _togglePlay() {
    setState(() {
      if (_playing) {
        _stop();
        return;
      }
      if (_shown >= _last) {
        _tweenFrom = null;
        _shown = 1;
      }
      _play();
    });
  }

  void _restart() {
    setState(() {
      _tweenFrom = null;
      _shown = 1;
      _play();
    });
  }

  WholeGrowthInputs _inputs(int n) => wholeGrowthInputs(
    n,
    widget.floor,
    step: widget.step,
    level: widget.level,
    frac: widget.frac,
  );

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final target = _inputs(_shown);
    final tweenFrom = _tweenFrom;
    final from = tweenFrom != null && !_reduced ? _inputs(tweenFrom) : null;
    final name = catalogItem(ItemKind.species, kSpeciesIds[widget.species]!)?.name ?? 'boom';
    final pill = growthPill(phaseForStep(_shown).name, _shown);
    final isNow = _shown == widget.step;

    final stage = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg + 3),
        border: Border.all(color: AppTheme.rule),
      ),
      // Inset by the border and clipped to the inner radius, so the scene
      // never paints over its own outline.
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg + 2),
          child: Semantics(
            image: true,
            label: 'Je boom: $pill',
            child: TreeView(
              seed: widget.seed,
              level: target.level,
              frac: target.frac,
              floor: target.floor,
              from: from == null
                  ? null
                  : TreeFrom.withFloor(level: from.level, frac: from.frac, floor: from.floor),
              tweenMs: kWholeGrowthTweenMs,
              species: widget.species,
              scene: widget.scene,
              reducedMotion: _reduced,
            ),
          ),
        ),
      ),
    );

    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        // Read out when the reader moves the tree themselves; while it plays,
        // a step every 700 ms would drown everything else.
        Semantics(
          liveRegion: !_playing,
          container: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.tealTint,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
                child: Text(
                  pill,
                  style: AppTheme.caption.copyWith(color: AppTheme.teal, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                wholeGrowthLine(_shown, widget.step, widget.floor),
                style: isNow
                    ? AppTheme.bodyStrong.copyWith(color: AppTheme.teal)
                    : AppTheme.bodyMuted,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _StepSlider(
          value: _shown,
          last: _last,
          now: widget.step.clamp(1, _last),
          label: pill,
          onChanged: _jump,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SiteButton(
              label: _playing ? wholeGrowth.pause : wholeGrowth.play,
              icon: _playing ? Icons.pause : Icons.play_arrow,
              height: 44,
              expand: false,
              onPressed: _togglePlay,
            ),
            SiteOutlineButton(
              label: wholeGrowth.restart,
              icon: Icons.replay,
              height: 44,
              expand: false,
              onPressed: _restart,
            ),
            SiteOutlineButton(
              label: wholeGrowth.toNow,
              height: 44,
              expand: false,
              onPressed: () => _jump(widget.step),
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: wholeGrowth.close,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(wholeGrowthTitle(name), maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: scheme.surface,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: ConstrainedBox(
              // The tree takes what the controls leave, never less than this;
              // below that (a small phone at large text) the page scrolls.
              constraints: BoxConstraints(minHeight: math.max(0.0, box.maxHeight - 32)),
              child: IntrinsicHeight(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // No taller than a little over square: in a tall frame
                    // the camera gives the tree the same share of a much
                    // bigger sky, and it reads as small.
                    Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: 220,
                          maxHeight: math.max(220.0, (box.maxWidth - 40) * 1.15),
                        ),
                        child: stage,
                      ),
                    ),
                    details,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Steps 1 to [last], with a "Nu" marker under the reader's own step.
class _StepSlider extends StatelessWidget {
  const _StepSlider({
    required this.value,
    required this.last,
    required this.now,
    required this.label,
    required this.onChanged,
  });

  final int value;
  final int last;
  final int now;

  /// The pill for [value], read out as the slider's value.
  final String label;
  final ValueChanged<int> onChanged;

  /// The slider's side padding. With an explicit padding its track runs the
  /// full width between, so the marker can sit exactly under a step.
  static const double _inset = 14;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final marker = _NowMarker(
      t: last > 1 ? (now - 1) / (last - 1) : 0.0,
      inset: _inset,
      text: wholeGrowth.now.toUpperCase(),
      style: AppTheme.caption.copyWith(
        color: AppTheme.teal,
        fontWeight: FontWeight.w700,
        fontSize: 10.5,
        letterSpacing: 0.6,
        height: 1.2,
      ),
      textScaler: MediaQuery.textScalerOf(context),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: Slider(
            value: value.toDouble(),
            min: 1,
            max: last.toDouble(),
            divisions: last - 1,
            padding: const EdgeInsets.symmetric(horizontal: _inset),
            activeColor: AppTheme.teal,
            inactiveColor: AppTheme.ruleStrong,
            label: ladderStep(value),
            semanticFormatterCallback: (_) => label,
            onChanged: (v) {
              final step = v.round();
              if (step != value) onChanged(step);
            },
          ),
        ),
        // Drawn, not laid out: the marker needs the row's width, and the page
        // measures this column's intrinsic height (no LayoutBuilder allowed).
        ExcludeSemantics(
          child: SizedBox(
            height: marker.height,
            width: double.infinity,
            child: CustomPaint(painter: marker),
          ),
        ),
      ],
    );
  }
}

/// A tick under the slider at [t] (0..1 along the track) and "NU" under it,
/// kept inside the row at both ends.
class _NowMarker extends CustomPainter {
  _NowMarker({
    required this.t,
    required this.inset,
    required this.text,
    required this.style,
    required this.textScaler,
  });

  final double t;
  final double inset;
  final String text;
  final TextStyle style;
  final TextScaler textScaler;

  static const double _tick = 6;
  static const double _gap = 2;

  TextPainter _layoutLabel() => TextPainter(
    text: TextSpan(text: text, style: style),
    textScaler: textScaler,
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();

  /// The height the marker needs at this text size.
  double get height {
    final label = _layoutLabel();
    final h = label.height.ceilToDouble();
    label.dispose();
    return _tick + _gap + h;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final x = inset + (size.width - 2 * inset) * t;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x - 1, 0, 2, _tick), const Radius.circular(1)),
      Paint()..color = style.color ?? const Color(0xFF0D9488),
    );
    final label = _layoutLabel();
    final left = (x - label.width / 2).clamp(0.0, math.max(0.0, size.width - label.width)).toDouble();
    label.paint(canvas, Offset(left, _tick + _gap));
    label.dispose();
  }

  @override
  bool shouldRepaint(_NowMarker old) =>
      old.t != t || old.inset != inset || old.text != text || old.style != style || old.textScaler != textScaler;
}
