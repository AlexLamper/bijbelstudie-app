import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/camera.dart';
import '../domain/catalog.dart';
import '../domain/palette.dart';
import '../domain/rng.dart';
import '../domain/scenes.dart';
import '../domain/species.dart';
import '../domain/tree_generator.dart';

export '../domain/camera.dart' show TreeFraming;

/// The scene a tree stands in, painted without the tree.
///
/// Everything here used to live in [TreePainter]. It is split out so a second
/// painter can draw the same world - sky, backdrop, earth, animals - with no
/// branches on top: `verse_scene.dart` uses it for the daily-verse art, and
/// `notification_canvas.dart` for the picture a notification carries
/// (`AVATAR_NOTIFICATIONS_PLAN.md` §2.1). Pure extraction: no routine below
/// changed when it moved, and the generator was not touched, so the website
/// parity fixtures are unaffected.

/// The two framings ([TreeFraming], scene and portrait) live with the camera
/// in `domain/camera.dart` and are re-exported from here.

/// The `seasons` trait (docs/levensboom-spec.md §6) arrives here.

/// Motes, stars, drifters and the backdrop's own details, drawn from their own
/// streams so adding one can never shift the tree's own random draws.
class TreeDecor {
  TreeDecor(String seed) {
    final rand = seededRng('$seed:decor');
    motes = [
      for (var i = 0; i < 18; i++)
        (
          x: rand() * 100,
          y: rand() * 100,
          r: 0.25 + rand() * 0.45,
          speed: 0.6 + rand() * 1.2,
          phase: rand(),
        ),
    ];
    stars = [
      for (var i = 0; i < 60; i++)
        (x: rand() * 100, y: rand() * 62, r: 0.15 + rand() * 0.3, phase: rand()),
    ];
    // Autumn's falling leaves and the level-25 blossom storm are the same
    // handful of drifters wearing different colours.
    drifters = [
      for (var i = 0; i < 14; i++)
        (
          x: rand() * 100,
          y: rand() * 100,
          size: 0.7 + rand() * 0.9,
          speed: 0.5 + rand() * 1.1,
          drift: 0.6 + rand() * 1.6,
          phase: rand(),
        ),
    ];
    fireflies = [
      for (var i = 0; i < 12; i++) (x: rand(), y: rand(), phase: rand()),
    ];
    butterflies = [
      for (var i = 0; i < 3; i++)
        (
          rx: 0.55 + rand() * 0.35,
          ry: 0.35 + rand() * 0.3,
          speed: 0.7 + rand() * 0.6,
          phase: rand(),
          hue: i,
        ),
    ];
    // Appended after everything that existed before, so no older decor moved.
    // Same order as the website's `buildDecor`.
    bees = [
      for (var i = 0; i < 7; i++)
        (
          rx: 0.35 + rand() * 0.55,
          ry: 0.3 + rand() * 0.5,
          speed: 0.6 + rand() * 0.8,
          phase: rand(),
        ),
    ];
    eaglePhase = rand();

    final scene = seededRng('$seed:scene');
    dots = [
      for (var i = 0; i < 120; i++)
        (x: scene(), y: scene(), r: scene(), k: scene()),
    ];
    sheep = (-(13 + scene() * 8), 11 + scene() * 7);
    deer = 15 + scene() * 6;
    // Same rule: later animals draw after the earlier ones.
    fox = -(12 + scene() * 6);
    donkey = 14 + scene() * 6;
    stork = 12 + scene() * 5;
    lion = 15 + scene() * 5;
  }

  late final List<({double x, double y, double r, double speed, double phase})> motes;
  late final List<({double x, double y, double r, double phase})> stars;
  late final List<
    ({double x, double y, double size, double speed, double drift, double phase})
  >
  drifters;
  late final List<({double x, double y, double phase})> fireflies;
  late final List<({double rx, double ry, double speed, double phase, int hue})>
  butterflies;
  late final List<({double rx, double ry, double speed, double phase})> bees;

  /// Where on its circle the eagle starts. 0..1.
  late final double eaglePhase;

  /// Backdrop details: stone/flower/olive positions, extra stars. 0..1.
  late final List<({double x, double y, double r, double k})> dots;

  /// Where the ground animals stand, in tree units left/right of the trunk.
  late final (double, double) sheep;
  late final double deer;
  late final double fox;
  late final double donkey;
  late final double stork;
  late final double lion;
}

const int kSeasonsTraitLevel = 25;

/// The frame a scene is drawn in: where tree space lands in pixels.
class TreeFrame {
  const TreeFrame({
    required this.width,
    required this.height,
    required this.scale,
    required this.originX,
    required this.originY,
    required this.pivotX,
    required this.pivotY,
    required this.groundTop,
    this.guarded = false,
  });

  final double width, height, scale, originX, originY, pivotX, pivotY;

  /// Top edge of the earth band (scene) or of the shadow (portrait).
  final double groundTop;

  /// True when a ground animal forced the camera out past the designed fill.
  final bool guarded;
}

const double kDeg = math.pi / 180;

/// The canvas `ellipse(cx, cy, rx, ry, rotation)` the website draws with:
/// radii, not a bounding box, and an optional rotation about the centre.
void fillEllipse(
  Canvas canvas,
  Offset centre,
  double rx,
  double ry,
  Paint paint, {
  double rotation = 0,
}) {
  if (rotation == 0) {
    canvas.drawOval(Rect.fromCenter(center: centre, width: rx * 2, height: ry * 2), paint);
    return;
  }
  canvas.save();
  canvas.translate(centre.dx, centre.dy);
  canvas.rotate(rotation);
  canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), paint);
  canvas.restore();
}

/// Ground animals stand beside the trunk; the frame has to hold them too.
({double minX, double maxX}) extentWithAnimals(
  TreeScene scene,
  TreeAnimal animal,
  TreeDecor decor,
) {
  var minX = scene.bounds.minX;
  var maxX = scene.bounds.maxX;
  if (animal == TreeAnimal.schaap) {
    minX = math.min(minX, kTrunkX + decor.sheep.$1 - 5);
    maxX = math.max(maxX, kTrunkX + decor.sheep.$2 + 5);
  }
  if (animal == TreeAnimal.hert) maxX = math.max(maxX, kTrunkX + decor.deer + 6);
  if (animal == TreeAnimal.vos) minX = math.min(minX, kTrunkX + decor.fox - 5);
  if (animal == TreeAnimal.ezel) maxX = math.max(maxX, kTrunkX + decor.donkey + 7);
  if (animal == TreeAnimal.ooievaar) maxX = math.max(maxX, kTrunkX + decor.stork + 4);
  if (animal == TreeAnimal.leeuw) maxX = math.max(maxX, kTrunkX + decor.lion + 8);
  return (minX: minX, maxX: maxX);
}

/// What a ground animal needs in frame, in tree units beside the trunk and
/// above the ground, for the camera's guard (`camera.dart` [FrameExtents]).
/// Widths are the old frame margins; heights are each animal's drawn height at
/// world size. The website's `animalExtents` in `TreeCanvas.tsx`, minus its
/// last case (a perching bird waiting on the ground while the crown has no
/// perch), which needs the ground-bird spot the app's [TreeDecor] does not
/// draw yet.
FrameExtents? animalExtents(TreeAnimal animal, TreeDecor decor) {
  switch (animal) {
    case TreeAnimal.schaap:
      return FrameExtents(left: -decor.sheep.$1 + 5, right: decor.sheep.$2 + 5, top: 4);
    case TreeAnimal.hert:
      return FrameExtents(right: decor.deer + 6, top: 10);
    case TreeAnimal.vos:
      return FrameExtents(left: -decor.fox + 5, top: 6);
    case TreeAnimal.ezel:
      return FrameExtents(right: decor.donkey + 7, top: 8);
    case TreeAnimal.ooievaar:
      return FrameExtents(right: decor.stork + 4, top: 8);
    case TreeAnimal.leeuw:
      return FrameExtents(right: decor.lion + 8, top: 5);
    default:
      return null;
  }
}

/// The growth v2 camera (`domain/camera.dart`, the website's `measureFrame`):
/// the landscape stays put and the tree takes a designed share of it, centred
/// on the trunk base. Ground animals only guard the scene framing.
TreeFrame measureTreeFrame(
  Size size,
  TreeScene scene,
  TreeFraming framing,
  TreeAnimal animal,
  TreeDecor decor,
) {
  final extents = framing == TreeFraming.scene ? animalExtents(animal, decor) : null;
  final frame = measureFrame(size.width, size.height, scene, framing, extents);
  return TreeFrame(
    width: size.width,
    height: size.height,
    scale: frame.scale,
    originX: frame.originX,
    originY: frame.originY,
    pivotX: frame.pivotX,
    pivotY: frame.pivotY,
    groundTop: frame.groundTop,
    guarded: frame.guarded,
  );
}

/// The scene layers, on any painter that can say what it is painting.
///
/// A [TreePainter] mixes this in and draws its branches between
/// [paintGround] and [paintForeground]; a scene-only painter simply never
/// calls the tree layers.
mixin SceneLayers {
  TreeScene get scene;
  TreePalette get palette;
  TreeDecor get decor;
  TreeFraming get framing;
  TreeAnimal get animal;
  double get timeMs;
  bool get still;
  bool get celebration;
  int get level;

  SpeciesParams get sp => speciesParams(scene.species);

  /// Slow weather, for the daily-verse art only
  /// (`AVATAR_NOTIFICATIONS_PLAN.md` §6.2).
  ///
  /// [TreePainter] never calls this: the tree's sky is the one the website
  /// mirrors and it stays exactly as it was. Three blurred blobs crossing on
  /// their own periods, wrapped so there is no seam. A night sky already has
  /// stars and gets no clouds.
  void paintClouds(
    Canvas canvas,
    TreeFrame frame, {
    required double seed,
    required double drift,
  }) {
    if (palette.night) return;
    final w = frame.width;
    final band = frame.groundTop;
    if (w <= 0 || band <= 0) return;

    final rand = seededRng('verse-clouds:${(seed * 100000).round()}');
    final paint = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(4.0, w * 0.02));

    for (var i = 0; i < 3; i++) {
      final y = band * (0.12 + rand() * 0.34);
      final rx = w * (0.13 + rand() * 0.12);
      final ry = rx * (0.28 + rand() * 0.12);
      // px per millisecond: a cloud crosses the sky in six to fourteen minutes.
      final speed = (w / (360000 + rand() * 480000)) * (rand() < 0.5 ? 1 : -1);
      final span = w + rx * 4;
      final start = ((drift + i / 3) % 1) * span;
      final x = ((start + timeMs * speed) % span + span) % span - rx * 2;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2),
        paint..color = palette.light.withValues(alpha: 0.13 + rand() * 0.09),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x + rx * 0.5, y + ry * 0.35),
          width: rx * 1.3,
          height: ry * 1.5,
        ),
        paint..color = palette.light.withValues(alpha: 0.09),
      );
    }
  }

  // ---------------------------------------------------------------- sky

  void paintSky(Canvas canvas, TreeFrame frame) {
    final rect = Offset.zero & Size(frame.width, frame.height);
    if (framing == TreeFraming.portrait) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(frame.width / 2, frame.height * 0.38),
            math.max(frame.width, frame.height) * 0.75,
            [palette.skyBottom, palette.skyTop],
          ),
      );
      return;
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, frame.groundTop),
          [palette.skyTop, palette.skyBottom],
        ),
    );

    if (palette.night) {
      final star = Paint();
      for (final s in decor.stars) {
        final twinkle =
            0.45 + 0.55 * math.sin(timeMs * 0.0008 + s.phase * 6.283).abs();
        // Sky decoration is placed in viewport fractions, not tree space: the
        // tree is framed to its own bounds, so following it would bunch the
        // stars around the canopy instead of filling the sky.
        canvas.drawCircle(
          Offset(s.x / 100 * frame.width, s.y / 100 * frame.groundTop),
          math.max(0.5, s.r * frame.scale),
          star..color = palette.light.withValues(alpha: twinkle * 0.8),
        );
      }
    }
  }

  // ------------------------------------------------------------- ground

  void paintGround(Canvas canvas, TreeFrame frame) {
    final scale = frame.scale;
    final pivot = Offset(frame.pivotX, frame.pivotY);

    if (framing == TreeFraming.portrait) {
      // A soft shadow and a thin arc of ground: enough to stand on, not a
      // landscape.
      final extent = extentWithAnimals(scene, animal, decor);
      final rx = math.max(6.0, ((extent.maxX - extent.minX) / 2) * scale * 0.55);
      canvas.drawOval(
        Rect.fromCenter(center: pivot, width: rx * 2, height: math.max(3.0, 3.2 * scale)),
        Paint()..color = palette.ground.withValues(alpha: 0.9),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: pivot.translate(0, 0.4 * scale),
          width: rx * 1.4,
          height: math.max(2.0, 2.2 * scale),
        ),
        Paint()..color = palette.bark.withValues(alpha: 0.25),
      );
      return;
    }

    // The glow, centred on the canopy wherever it happens to be for this level.
    final glowCentre = Offset(
      frame.pivotX,
      frame.originY + (scene.bounds.minY + kGroundY) / 2 * scale,
    );
    final glowRadius = math.max(30.0, (kGroundY - scene.bounds.minY) * 0.7) * scale;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, frame.width, frame.groundTop),
      Paint()
        ..shader = ui.Gradient.radial(glowCentre, glowRadius, [
          palette.glow.withValues(alpha: 0.4),
          palette.glow.withValues(alpha: 0),
        ]),
    );

    paintFarBackdrop(canvas, frame);

    // The earth band, with a low mound where the trunk goes in.
    final top = frame.groundTop;
    canvas.drawRect(
      Rect.fromLTRB(0, top, frame.width, frame.height),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, top), Offset(0, frame.height), [
          palette.ground,
          palette.groundDeep,
        ]),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(frame.pivotX, top + 0.2 * scale),
        width: math.max(16.0, 28 * scale),
        height: math.max(4.0, 4.4 * scale),
      ),
      Paint()..color = palette.ground,
    );

    paintNearBackdrop(canvas, frame);

    canvas.drawOval(
      Rect.fromCenter(
        center: pivot.translate(0, 0.6 * scale),
        width: math.max(12.0, 22 * scale),
        height: math.max(2.4, 3.2 * scale),
      ),
      Paint()
        ..color = Color.lerp(palette.groundDeep, palette.bark, 0.5)!.withValues(alpha: 0.28),
    );
  }

  Path _hillPath(double width, double baseY, double amp, double freq, double phase, double lift) {
    final path = Path()..moveTo(0, baseY + amp * 2);
    const steps = 24;
    for (var i = 0; i <= steps; i++) {
      final x = i / steps * width;
      final y = baseY - lift - amp * (0.5 + 0.5 * math.sin(i / steps * freq * math.pi * 2 + phase));
      path.lineTo(x, y);
    }
    path
      ..lineTo(width, baseY + amp * 2)
      ..close();
    return path;
  }

  /// A wavy line across the frame: sea swell, the shore's foam.
  Path _wavePath(double width, double y, double amp, int count, double shift) {
    final step = width / count;
    final path = Path()..moveTo(-step + shift, y);
    for (var i = -1; i <= count; i++) {
      final x = i * step + shift;
      path.quadraticBezierTo(x + step * 0.5, y - amp, x + step, y);
    }
    return path;
  }

  void paintFarBackdrop(Canvas canvas, TreeFrame frame) {
    final w = frame.width;
    final h = frame.height;
    final groundTop = frame.groundTop;
    final spec = sceneSpec(palette.scene);
    final paint = Paint();

    switch (spec.backdrop) {
      case Backdrop.hills:
        canvas.drawPath(_hillPath(w, groundTop, h * 0.09, 1.3, 0.8, h * 0.05), paint..color = palette.farAlt);
        canvas.drawPath(_hillPath(w, groundTop, h * 0.06, 2.1, 2.6, 0), paint..color = palette.far);
        // Olive groves: dark specks along the near hill.
        paint.color = spec.accent.withValues(alpha: 0.7);
        for (var i = 0; i < 9; i++) {
          final d = decor.dots[i];
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(d.x * w, groundTop - h * 0.02 - d.y * h * 0.05),
              width: math.max(2.4, w * 0.024),
              height: math.max(2.0, w * 0.016),
            ),
            paint,
          );
        }
      case Backdrop.lake:
        final horizon = groundTop - h * 0.14;
        canvas.drawPath(_hillPath(w, horizon, h * 0.045, 1.6, 1.2, 0), paint..color = palette.far);
        canvas.drawRect(
          Rect.fromLTRB(0, horizon, w, groundTop),
          paint..color = palette.water ?? palette.far,
        );
        final streak = Paint()
          ..color = spec.accent.withValues(alpha: 0.5)
          ..strokeWidth = math.max(1.0, h * 0.004)
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 5; i++) {
          final d = decor.dots[i + 10];
          final y = horizon + (0.2 + d.y * 0.7) * (groundTop - horizon);
          final x = d.x * w;
          final half = w * 0.05 * (0.5 + d.r);
          canvas.drawLine(Offset(x - half, y), Offset(x + half, y), streak);
        }
        // The boat.
        final bx = w * 0.74;
        final by = horizon + (groundTop - horizon) * 0.3;
        final bw = math.max(8.0, w * 0.06);
        canvas.drawPath(
          Path()
            ..moveTo(bx - bw / 2, by)
            ..lineTo(bx + bw / 2, by)
            ..lineTo(bx + bw * 0.35, by + bw * 0.22)
            ..lineTo(bx - bw * 0.35, by + bw * 0.22)
            ..close(),
          paint..color = palette.bark,
        );
        canvas.drawLine(
          Offset(bx, by),
          Offset(bx, by - bw * 0.7),
          Paint()
            ..color = palette.bark
            ..strokeWidth = math.max(1.0, bw * 0.05),
        );
        canvas.drawPath(
          Path()
            ..moveTo(bx + bw * 0.03, by - bw * 0.68)
            ..lineTo(bx + bw * 0.42, by - bw * 0.08)
            ..lineTo(bx + bw * 0.03, by - bw * 0.08)
            ..close(),
          paint..color = spec.accent,
        );
      case Backdrop.dunes:
        canvas.drawPath(_hillPath(w, groundTop, h * 0.1, 0.9, 2.2, h * 0.03), paint..color = palette.farAlt);
        canvas.drawPath(_hillPath(w, groundTop, h * 0.07, 1.4, 4.4, 0), paint..color = palette.far);
      case Backdrop.mountain:
        const peaks = [
          (-0.05, 0.12),
          (0.08, 0.3),
          (0.24, 0.42),
          (0.4, 0.26),
          (0.58, 0.48),
          (0.74, 0.3),
          (0.9, 0.38),
          (1.05, 0.14),
        ];
        final range = Path()..moveTo(-w * 0.1, groundTop);
        for (final (px, py) in peaks) {
          range.lineTo(px * w, groundTop - py * h);
        }
        range
          ..lineTo(w * 1.1, groundTop)
          ..close();
        canvas.drawPath(range, paint..color = palette.far);
        // Snow on the two tallest peaks.
        paint.color = spec.accent;
        for (final (px, py) in [peaks[2], peaks[4]]) {
          final top = groundTop - py * h;
          final cap = h * 0.06;
          canvas.drawPath(
            Path()
              ..moveTo(px * w, top)
              ..lineTo(px * w + cap * 0.9, top + cap)
              ..lineTo(px * w + cap * 0.3, top + cap * 0.8)
              ..lineTo(px * w - cap * 0.2, top + cap * 1.05)
              ..lineTo(px * w - cap * 0.9, top + cap)
              ..close(),
            paint,
          );
        }
        canvas.drawPath(_hillPath(w, groundTop, h * 0.07, 1.1, 3.4, 0), paint..color = palette.farAlt);
      case Backdrop.wall:
        final wallTop = groundTop - h * 0.17;
        paint.color = palette.far;
        canvas.drawRect(Rect.fromLTRB(0, wallTop, w, groundTop), paint);
        final step = w * 0.07;
        final mw = step * 0.5;
        final mh = h * 0.035;
        for (var x = step * 0.25; x < w; x += step) {
          canvas.drawRect(Rect.fromLTWH(x, wallTop - mh, mw, mh + 1), paint);
        }
        final tx = w * 0.78;
        final tw = w * 0.12;
        final towerTop = groundTop - h * 0.3;
        canvas.drawRect(Rect.fromLTRB(tx, towerTop, tx + tw, groundTop), paint);
        for (var x = tx; x < tx + tw; x += tw / 4) {
          canvas.drawRect(Rect.fromLTWH(x, towerTop - mh, tw / 8, mh + 1), paint);
        }
        final course = Paint()
          ..color = palette.farAlt.withValues(alpha: 0.55)
          ..strokeWidth = 1;
        for (var i = 1; i < 4; i++) {
          final y = wallTop + (groundTop - wallTop) * i / 4;
          canvas.drawLine(Offset(0, y), Offset(w, y), course);
        }
        final gx = w * 0.28;
        final gw = w * 0.06;
        canvas.drawPath(
          Path()
            ..moveTo(gx - gw / 2, groundTop)
            ..lineTo(gx - gw / 2, groundTop - h * 0.07)
            ..arcTo(
              Rect.fromCircle(center: Offset(gx, groundTop - h * 0.07), radius: gw / 2),
              math.pi,
              math.pi,
              false,
            )
            ..lineTo(gx + gw / 2, groundTop)
            ..close(),
          paint..color = spec.accent,
        );
      case Backdrop.garden:
        canvas.drawPath(_hillPath(w, groundTop, h * 0.08, 1.7, 0.4, h * 0.03), paint..color = palette.farAlt);
        canvas.drawPath(_hillPath(w, groundTop, h * 0.05, 3.2, 1.9, 0), paint..color = palette.far);
      case Backdrop.stars:
        for (var i = 0; i < 90; i++) {
          final d = decor.dots[i];
          canvas.drawCircle(
            Offset(d.x * w, d.y * groundTop * 0.95),
            math.max(0.4, d.r * w * 0.0035),
            paint..color = palette.light.withValues(alpha: 0.35 + 0.6 * d.k),
          );
        }
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w, groundTop),
          Paint()
            ..shader = ui.Gradient.linear(
              Offset.zero,
              Offset(w, groundTop),
              [
                palette.light.withValues(alpha: 0),
                palette.light.withValues(alpha: 0.13),
                palette.light.withValues(alpha: 0),
              ],
              [0.3, 0.5, 0.7],
            ),
        );
        final mx = w * 0.18;
        final my = h * 0.16;
        final mr = math.max(4.0, w * 0.035);
        canvas.drawCircle(Offset(mx, my), mr, paint..color = spec.accent);
        canvas.drawCircle(
          Offset(mx + mr * 0.45, my - mr * 0.15),
          mr * 0.85,
          paint..color = palette.skyTop,
        );
      case Backdrop.river:
        // Far bank and hills, then the river itself between them and the near
        // bank the tree stands on - the reader is on the Jordan's shore.
        canvas.drawPath(_hillPath(w, groundTop, h * 0.08, 1.4, 0.6, h * 0.04), paint..color = palette.farAlt);
        canvas.drawPath(_hillPath(w, groundTop, h * 0.05, 2.3, 2.9, 0), paint..color = palette.far);
        final top = groundTop - h * 0.085;
        canvas.drawRect(
          Rect.fromLTRB(0, top, w, groundTop),
          paint..color = palette.water ?? palette.far,
        );
        final streak = Paint()
          ..color = palette.light.withValues(alpha: 0.35)
          ..strokeWidth = math.max(1.0, h * 0.003);
        for (var i = 0; i < 5; i++) {
          final d = decor.dots[50 + i];
          final y = top + (0.2 + d.y * 0.6) * (groundTop - top);
          final drift = still ? 0.0 : math.sin(timeMs * 0.0006 + d.k * 6.283) * w * 0.01;
          final half = w * 0.04 * (0.5 + d.r);
          canvas.drawLine(Offset(d.x * w - half + drift, y), Offset(d.x * w + half + drift, y), streak);
        }
      case Backdrop.vineyard:
        canvas.drawPath(_hillPath(w, groundTop, h * 0.08, 1.4, 0.6, h * 0.04), paint..color = palette.farAlt);
        canvas.drawPath(_hillPath(w, groundTop, h * 0.05, 2.3, 2.9, 0), paint..color = palette.far);
        // Rows of vines on posts, smaller as they recede up the hill.
        final post = Paint()..color = palette.groundDeep.withValues(alpha: 0.55);
        for (var row = 0; row < 4; row++) {
          final perspective = 1 - row * 0.18;
          final y = groundTop - h * (0.015 + row * 0.03);
          final step = w * 0.07 * perspective;
          final offset = step * (row % 2 == 0 ? 0.25 : 0.6);
          var k = 0;
          for (var x = offset; x < w; x += step, k++) {
            final d = decor.dots[(row * 17 + k) % 120];
            post.strokeWidth = math.max(0.7, w * 0.004 * perspective);
            canvas.drawLine(Offset(x, y), Offset(x, y - h * 0.03 * perspective), post);
            canvas.drawOval(
              Rect.fromCenter(
                center: Offset(x, y - h * 0.028 * perspective),
                width: math.max(3.0, w * 0.044 * perspective),
                height: math.max(2.0, h * 0.028 * perspective),
              ),
              paint..color = palette.farAlt.withValues(alpha: 0.9),
            );
            if (d.k > 0.5) {
              canvas.drawCircle(
                Offset(x + (d.x - 0.5) * w * 0.02, y - h * 0.018 * perspective),
                math.max(0.6, w * 0.004 * perspective),
                paint..color = spec.accent.withValues(alpha: 0.9),
              );
            }
          }
        }
      case Backdrop.field:
        canvas.drawPath(_hillPath(w, groundTop, h * 0.06, 1.1, 1.9, h * 0.03), paint..color = palette.farAlt);
        canvas.drawPath(_hillPath(w, groundTop, h * 0.04, 1.9, 4.1, 0), paint..color = palette.far);
      case Backdrop.sea:
        final horizon = groundTop - h * 0.16;
        canvas.drawRect(
          Rect.fromLTRB(0, horizon, w, groundTop),
          paint..color = palette.water ?? palette.far,
        );
        // Swell: rows of low scallops, drifting sideways.
        final swell = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, h * 0.004);
        for (var i = 0; i < 5; i++) {
          final y = horizon + (0.18 + i * 0.17) * (groundTop - horizon);
          final count = 9 + i * 2;
          final shift = still ? 0.0 : (timeMs * 0.012 * (1 + i * 0.2)) % (w / count) - w / count;
          canvas.drawPath(
            _wavePath(w, y, h * 0.006 * (1 + i * 0.3), count, shift),
            swell..color = spec.accent.withValues(alpha: 0.2 + i * 0.07),
          );
        }
      case Backdrop.rainbow:
        // The bow: six bands on a centre below the horizon; the earth band
        // covers the part that would run under the ground.
        final cx = w * 0.62;
        final cy = groundTop + h * 0.32;
        final r = h * 0.78;
        final band = math.max(1.5, h * 0.014);
        const colours = [
          Color(0xFFE4483F),
          Color(0xFFF0933A),
          Color(0xFFF2D24A),
          Color(0xFF6DBA5C),
          Color(0xFF4E9CD6),
          Color(0xFF7A5FB8),
        ];
        final bow = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = band;
        for (var i = 0; i < colours.length; i++) {
          canvas.drawArc(
            Rect.fromCircle(center: Offset(cx, cy), radius: r - i * band),
            math.pi,
            math.pi,
            false,
            bow..color = colours[i].withValues(alpha: 0.5),
          );
        }
        canvas.drawPath(
          _hillPath(w, groundTop, h * 0.04, 1.2, 1.1, 0),
          paint..color = palette.far.withValues(alpha: 0.55),
        );
      case Backdrop.sunrise:
        final sx = w * 0.5;
        final sy = groundTop - h * 0.1;
        final sr = math.max(6.0, w * 0.09);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w, groundTop),
          Paint()
            ..shader = ui.Gradient.radial(Offset(sx, sy), sr * 3, [
              palette.glow.withValues(alpha: 0.4),
              palette.glow.withValues(alpha: 0),
            ]),
        );
        // Rays, turning very slowly.
        final ray = Paint()
          ..color = spec.accent.withValues(alpha: 0.18)
          ..strokeWidth = math.max(1.0, w * 0.006);
        final turn = still ? 0.0 : timeMs * 0.00008;
        for (var i = 0; i < 9; i++) {
          final a = math.pi + (i / 8) * math.pi + turn;
          canvas.drawLine(
            Offset(sx + math.cos(a) * sr * 1.15, sy + math.sin(a) * sr * 1.15),
            Offset(sx + math.cos(a) * sr * 2.4, sy + math.sin(a) * sr * 2.4),
            ray,
          );
        }
        canvas.drawCircle(Offset(sx, sy), sr, paint..color = spec.accent);
        canvas.drawPath(_hillPath(w, groundTop, h * 0.1, 1.2, 0.4, h * 0.05), paint..color = palette.farAlt);
        canvas.drawPath(_hillPath(w, groundTop, h * 0.06, 2.0, 2.4, 0), paint..color = palette.far);
      case Backdrop.shepherds:
        // One bright star over the fields, and a flock on the near hill.
        final sx = w * 0.72;
        final sy = h * 0.14;
        final sr = math.max(3.0, w * 0.02);
        final twinkle = still ? 1.0 : 0.92 + 0.08 * math.sin(timeMs * 0.002);
        canvas.drawRect(
          Rect.fromLTWH(sx - sr * 5, sy - sr * 5, sr * 10, sr * 10),
          Paint()
            ..shader = ui.Gradient.radial(Offset(sx, sy), sr * 5, [
              spec.accent.withValues(alpha: 0x55 / 255),
              spec.accent.withValues(alpha: 0),
            ]),
        );
        paint.color = spec.accent;
        canvas.drawPath(
          Path()
            ..moveTo(sx, sy - sr * 3 * twinkle)
            ..lineTo(sx + sr * 0.3, sy)
            ..lineTo(sx, sy + sr * 3 * twinkle)
            ..lineTo(sx - sr * 0.3, sy)
            ..close(),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(sx - sr * 2.2 * twinkle, sy)
            ..lineTo(sx, sy - sr * 0.3)
            ..lineTo(sx + sr * 2.2 * twinkle, sy)
            ..lineTo(sx, sy + sr * 0.3)
            ..close(),
          paint,
        );
        canvas.drawPath(_hillPath(w, groundTop, h * 0.09, 1.1, 1.5, h * 0.04), paint..color = palette.farAlt);
        canvas.drawPath(_hillPath(w, groundTop, h * 0.05, 1.8, 3.6, 0), paint..color = palette.far);
        paint.color = palette.light.withValues(alpha: 0.8);
        for (var i = 0; i < 5; i++) {
          final d = decor.dots[70 + i];
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(w * (0.08 + d.x * 0.84), groundTop - h * 0.012 - d.y * h * 0.03),
              width: math.max(2.4, w * 0.016),
              height: math.max(1.6, w * 0.01),
            ),
            paint,
          );
        }
      case Backdrop.meadow:
        canvas.drawPath(
          _hillPath(w, groundTop, h * 0.04, 1.2, 1.1, 0),
          paint..color = palette.far.withValues(alpha: 0.55),
        );
    }
  }

  /// Details that sit on the earth band: the stream, the pool, flowers, stones.
  void paintNearBackdrop(Canvas canvas, TreeFrame frame) {
    final w = frame.width;
    final h = frame.height;
    final groundTop = frame.groundTop;
    final band = h - groundTop;
    final spec = sceneSpec(palette.scene);
    final paint = Paint();

    switch (spec.backdrop) {
      case Backdrop.river:
        // Reeds along the near bank, swaying at the head.
        final stem = Paint()
          ..color = palette.groundDeep
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, band * 0.03);
        for (var i = 0; i < 10; i++) {
          final d = decor.dots[54 + i];
          final x = w * (0.03 + d.x * 0.94);
          final base = groundTop + band * (0.5 + d.y * 0.45);
          final top = base - band * (0.5 + d.r * 0.35);
          final sway = still ? 0.0 : math.sin(timeMs * 0.0015 + d.k * 6.283) * band * 0.04;
          canvas.drawPath(
            Path()
              ..moveTo(x, base)
              ..quadraticBezierTo(x, (base + top) / 2, x + sway, top),
            stem,
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(x + sway, top - band * 0.06),
              width: math.max(2.0, band * 0.06),
              height: math.max(4.0, band * 0.18),
            ),
            paint..color = spec.accent,
          );
        }
      case Backdrop.field:
        // Standing wheat, heads nodding in the wind.
        final stem = Paint()
          ..color = palette.groundDeep
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, band * 0.025);
        paint.color = spec.accent;
        for (var i = 0; i < 22; i++) {
          final d = decor.dots[60 + i];
          final x = w * (0.02 + d.x * 0.96);
          final base = groundTop + band * (0.35 + d.y * 0.6);
          final top = base - band * (0.5 + d.r * 0.4);
          final sway = still ? 0.0 : math.sin(timeMs * 0.0013 + d.k * 6.283) * band * 0.05;
          canvas.drawPath(
            Path()
              ..moveTo(x, base)
              ..quadraticBezierTo(x, (base + top) / 2, x + sway, top),
            stem,
          );
          canvas.save();
          canvas.translate(x + sway, top - band * 0.08);
          if (band > 0) canvas.rotate(sway / band);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: math.max(2.0, band * 0.07),
              height: math.max(4.0, band * 0.22),
            ),
            paint,
          );
          canvas.restore();
        }
      case Backdrop.sea:
        // Foam where the last wave reaches the sand.
        final shift = still ? 0.0 : math.sin(timeMs * 0.0009) * w * 0.01;
        canvas.drawPath(
          _wavePath(w, groundTop + band * 0.04, band * 0.05, 11, shift),
          Paint()
            ..color = spec.accent.withValues(alpha: 0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.5, band * 0.06),
        );
        // Two shells.
        paint.color = palette.light;
        for (var i = 0; i < 2; i++) {
          final d = decor.dots[44 + i];
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(w * (0.1 + d.x * 0.8), groundTop + band * (0.45 + d.y * 0.4)),
              width: math.max(2.4, w * 0.016),
              height: math.max(2.0, w * 0.012),
            ),
            paint,
          );
        }
      case Backdrop.vineyard:
      case Backdrop.rainbow:
      case Backdrop.sunrise:
      case Backdrop.shepherds:
      case Backdrop.meadow:
        final water = palette.water;
        if (water == null) return;
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.66, groundTop)
            ..quadraticBezierTo(w * 0.72, groundTop + band * 0.45, w * 0.98, groundTop + band * 0.75)
            ..lineTo(w * 1.02, h)
            ..lineTo(w * 0.84, h)
            ..quadraticBezierTo(w * 0.7, groundTop + band * 0.55, w * 0.7, groundTop)
            ..close(),
          paint..color = water,
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.7, groundTop + band * 0.2)
            ..quadraticBezierTo(w * 0.76, groundTop + band * 0.5, w * 0.9, groundTop + band * 0.7),
          Paint()
            ..color = spec.accent.withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, band * 0.04),
        );
        paint.color = palette.farAlt;
        for (var i = 0; i < 4; i++) {
          final d = decor.dots[20 + i];
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(w * (0.05 + d.x * 0.5), groundTop + band * (0.3 + d.y * 0.5)),
              width: math.max(3.0, w * 0.024 * (0.5 + d.r)),
              height: math.max(2.0, w * 0.014 * (0.5 + d.r)),
            ),
            paint,
          );
        }
      case Backdrop.dunes:
        final water = palette.water;
        if (water == null) return;
        final px = w * 0.2;
        final py = groundTop + band * 0.45;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(px, py), width: w * 0.26, height: band * 0.56),
          paint..color = water,
        );
        paint.color = spec.accent.withValues(alpha: 0.8);
        for (final ox in [-1.15, 1.1]) {
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(px + ox * w * 0.13, py - band * 0.05),
              width: math.max(4.0, w * 0.04),
              height: math.max(3.0, band * 0.32),
            ),
            paint,
          );
        }
      case Backdrop.garden:
        final water = palette.water;
        if (water != null) {
          canvas.drawPath(
            Path()
              ..moveTo(-w * 0.02, groundTop + band * 0.35)
              ..quadraticBezierTo(w * 0.18, groundTop + band * 0.2, w * 0.3, groundTop + band * 0.8)
              ..lineTo(w * 0.22, h)
              ..lineTo(-w * 0.02, h)
              ..close(),
            paint..color = water,
          );
        }
        final colours = [spec.accent, const Color(0xFFF5D76E), const Color(0xFFFFFFFF), const Color(0xFFF28C6B)];
        for (var i = 0; i < 16; i++) {
          final d = decor.dots[30 + i];
          final x = w * (0.32 + d.x * 0.66);
          final y = groundTop + band * (0.15 + d.y * 0.7);
          final r = math.max(1.2, w * 0.006 * (0.7 + d.r));
          canvas.drawLine(
            Offset(x, y + r * 2.4),
            Offset(x, y),
            Paint()
              ..color = palette.groundDeep
              ..strokeWidth = math.max(0.8, r * 0.4),
          );
          canvas.drawCircle(
            Offset(x, y),
            r,
            paint..color = colours[(d.k * colours.length).floor() % colours.length],
          );
        }
      case Backdrop.mountain:
      case Backdrop.wall:
      case Backdrop.hills:
      case Backdrop.lake:
        paint.color = palette.farAlt.withValues(alpha: 0.6);
        for (var i = 0; i < 3; i++) {
          final d = decor.dots[40 + i];
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(w * (0.05 + d.x * 0.9), groundTop + band * (0.35 + d.y * 0.45)),
              width: math.max(3.0, w * 0.028 * (0.5 + d.r)),
              height: math.max(2.0, w * 0.016 * (0.5 + d.r)),
            ),
            paint,
          );
        }
      case Backdrop.stars:
        break;
    }
  }

  void _drawSheep(Canvas canvas, Offset p, double scale, double facing) {
    final s = math.max(3.0, 1.8 * scale);
    final x = p.dx;
    final y = p.dy;
    final graze = still ? 0.0 : math.max(0.0, math.sin(timeMs * 0.0012 + x)) * 0.25;
    final legs = Paint()
      ..color = const Color(0xFF3B3330)
      ..strokeWidth = math.max(1.0, s * 0.18)
      ..strokeCap = StrokeCap.round;
    for (final lx in const [-0.9, -0.35, 0.35, 0.9]) {
      canvas.drawLine(Offset(x + lx * s, y - s * 0.5), Offset(x + lx * s, y), legs);
    }
    final fleece = Paint()..color = const Color(0xFFF2EFE6);
    for (final (ox, oy, r) in const [(-0.7, -0.95, 0.75), (0.1, -1.05, 0.85), (0.8, -0.9, 0.7)]) {
      canvas.drawCircle(Offset(x + ox * s, y + oy * s), r * s, fleece);
    }
    canvas.drawOval(Rect.fromCenter(center: Offset(x, y - s * 0.8), width: s * 3, height: s * 1.5), fleece);
    final hx = x + facing * s * 1.55;
    final hy = y - s * (0.85 - graze);
    final head = Paint()..color = const Color(0xFF3B3330);
    canvas.drawOval(Rect.fromCenter(center: Offset(hx, hy), width: s * 0.84, height: s * 1.1), head);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(hx - facing * s * 0.3, hy - s * 0.35), width: s * 0.56, height: s * 0.28),
      head,
    );
  }

  void _drawDeer(Canvas canvas, Offset p, double scale) {
    final s = math.max(3.0, 2 * scale);
    final x = p.dx;
    final y = p.dy;
    final nod = still ? 0.0 : math.sin(timeMs * 0.0009) * 0.08;
    const body = Color(0xFF8B6A4A);
    const dark = Color(0xFF5C4530);
    final legs = Paint()
      ..color = dark
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, s * 0.16);
    for (final lx in const [-1.1, -0.6, 0.6, 1.1]) {
      canvas.drawLine(Offset(x + lx * s, y - s * 1.1), Offset(x + lx * s * 1.05, y), legs);
    }
    final fill = Paint()..color = body;
    canvas.drawOval(Rect.fromCenter(center: Offset(x, y - s * 1.5), width: s * 3.4, height: s * 1.7), fill);
    final nx = x - s * 1.5;
    final ny = y - s * 2.1;
    canvas.drawLine(
      Offset(x - s * 1.2, y - s * 1.6),
      Offset(nx, ny - s * (0.9 - nod)),
      Paint()
        ..color = body
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.5, s * 0.5),
    );
    final hx = nx - s * 0.2;
    final hy = ny - s * (1.15 - nod);
    canvas.save();
    canvas.translate(hx, hy);
    canvas.rotate(-0.3);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: s * 1.24, height: s * 0.76), fill);
    canvas.restore();
    final antler = Paint()
      ..color = dark
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, s * 0.14);
    canvas.drawLine(Offset(hx + s * 0.2, hy - s * 0.3), Offset(hx + s * 0.45, hy - s * 0.75), antler);
    canvas.drawLine(Offset(hx + s * 0.35, hy - s * 0.25), Offset(hx + s * 0.55, hy - s * 1.15), antler);
    canvas.drawLine(Offset(hx + s * 0.45, hy - s * 0.7), Offset(hx + s * 0.75, hy - s * 1.0), antler);
    canvas.drawLine(Offset(hx + s * 0.5, hy - s * 0.95), Offset(hx + s * 0.3, hy - s * 1.35), antler);
    canvas.drawCircle(Offset(hx - s * 0.25, hy - s * 0.08), math.max(0.5, s * 0.07), Paint()..color = const Color(0xFF2B2B2B));
    canvas.drawCircle(Offset(x + s * 1.65, y - s * 1.6), s * 0.22, Paint()..color = const Color(0xFFF2EFE6));
  }

  /// Sitting on the left of the trunk, looking at it.
  void _drawFox(Canvas canvas, Offset p, double scale) {
    final s = math.max(3.0, 1.7 * scale);
    final x = p.dx;
    final y = p.dy;
    final wag = still ? 0.0 : math.sin(timeMs * 0.002) * 0.08;
    final body = Paint()..color = const Color(0xFFD2692E);
    final dark = Paint()..color = const Color(0xFF8E4A1E);
    final cream = Paint()..color = const Color(0xFFF4EDE2);
    // The tail curls round the front.
    fillEllipse(canvas, Offset(x - s * 1.1, y - s * 0.45), s * 1.3, s * 0.5, body, rotation: -0.5 + wag);
    canvas.drawCircle(Offset(x - s * 2.1, y - s * 0.85), s * 0.3, cream);
    // Body, chest.
    fillEllipse(canvas, Offset(x, y - s * 1.0), s * 0.85, s * 1.05, body);
    fillEllipse(canvas, Offset(x + s * 0.25, y - s * 0.75), s * 0.4, s * 0.6, cream);
    // Head and ears.
    canvas.drawCircle(Offset(x + s * 0.35, y - s * 2.05), s * 0.55, body);
    canvas.drawPath(
      Path()
        ..moveTo(x + s * 0.05, y - s * 2.4)
        ..lineTo(x + s * 0.2, y - s * 3.0)
        ..lineTo(x + s * 0.45, y - s * 2.45)
        ..close(),
      body,
    );
    canvas.drawPath(
      Path()
        ..moveTo(x + s * 0.5, y - s * 2.45)
        ..lineTo(x + s * 0.75, y - s * 3.0)
        ..lineTo(x + s * 0.85, y - s * 2.35)
        ..close(),
      body,
    );
    // Snout, nose, eye, paws.
    fillEllipse(canvas, Offset(x + s * 0.7, y - s * 1.95), s * 0.35, s * 0.22, cream);
    canvas.drawCircle(Offset(x + s * 0.98, y - s * 1.97), math.max(0.5, s * 0.08), dark);
    canvas.drawCircle(Offset(x + s * 0.5, y - s * 2.15), math.max(0.5, s * 0.07), dark);
    for (final px in const [0.35, 0.75]) {
      fillEllipse(canvas, Offset(x + s * px, y - s * 0.05), s * 0.22, s * 0.12, dark);
    }
  }

  /// Standing on the right, facing the tree.
  void _drawDonkey(Canvas canvas, Offset p, double scale) {
    final s = math.max(3.0, 1.9 * scale);
    final x = p.dx;
    final y = p.dy;
    const grey = Color(0xFF8C8A86);
    const dark = Color(0xFF5E5C58);
    final flick = still ? 0.0 : math.max(0.0, math.sin(timeMs * 0.003)) * 0.3;
    final legs = Paint()
      ..color = dark
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, s * 0.2);
    for (final lx in const [-0.95, -0.5, 0.5, 0.95]) {
      canvas.drawLine(Offset(x + lx * s, y - s * 1.05), Offset(x + lx * s, y), legs);
    }
    final fill = Paint()..color = grey;
    fillEllipse(canvas, Offset(x, y - s * 1.45), s * 1.5, s * 0.75, fill);
    // Neck, head, muzzle.
    canvas.drawLine(
      Offset(x - s * 1.2, y - s * 1.7),
      Offset(x - s * 1.75, y - s * 2.55),
      Paint()
        ..color = grey
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.5, s * 0.5),
    );
    fillEllipse(canvas, Offset(x - s * 1.95, y - s * 2.7), s * 0.55, s * 0.38, fill, rotation: 0.35);
    fillEllipse(
      canvas,
      Offset(x - s * 2.35, y - s * 2.55),
      s * 0.3,
      s * 0.22,
      Paint()..color = const Color(0xFFC9C4BB),
      rotation: 0.35,
    );
    // Ears.
    fillEllipse(canvas, Offset(x - s * 1.75, y - s * 3.3), s * 0.14, s * 0.5, fill, rotation: -0.25 - flick);
    fillEllipse(canvas, Offset(x - s * 1.5, y - s * 3.2), s * 0.14, s * 0.5, fill, rotation: 0.15);
    // Mane, eye, tail.
    final line = Paint()
      ..color = dark
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.8, s * 0.12);
    for (var i = 0; i < 3; i++) {
      final mx = x - s * (1.25 + i * 0.18);
      final my = y - s * (1.85 + i * 0.28);
      canvas.drawLine(Offset(mx, my), Offset(mx + s * 0.2, my - s * 0.12), line);
    }
    final darkFill = Paint()..color = dark;
    canvas.drawCircle(Offset(x - s * 2.05, y - s * 2.8), math.max(0.5, s * 0.07), darkFill);
    canvas.drawLine(Offset(x + s * 1.4, y - s * 1.6), Offset(x + s * 1.75, y - s * 0.9), line);
    canvas.drawCircle(Offset(x + s * 1.78, y - s * 0.82), s * 0.15, darkFill);
  }

  /// On one leg, on the right, facing the tree.
  void _drawStork(Canvas canvas, Offset p, double scale) {
    final s = math.max(3.0, 2 * scale);
    final x = p.dx;
    final y = p.dy;
    const white = Color(0xFFF6F6F2);
    const black = Color(0xFF2B2B2E);
    const red = Color(0xFFD9432F);
    final nod = still ? 0.0 : math.sin(timeMs * 0.0015) * 0.06;
    canvas.drawPath(
      Path()
        ..moveTo(x, y - s * 1.6)
        ..lineTo(x, y)
        ..moveTo(x + s * 0.1, y - s * 1.6)
        ..lineTo(x + s * 0.35, y - s * 1.0)
        ..lineTo(x + s * 0.1, y - s * 0.75),
      Paint()
        ..color = red
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(0.8, s * 0.12),
    );
    fillEllipse(canvas, Offset(x + s * 0.1, y - s * 2.1), s * 0.9, s * 0.5, Paint()..color = white, rotation: -0.15);
    fillEllipse(canvas, Offset(x + s * 0.7, y - s * 2.05), s * 0.45, s * 0.28, Paint()..color = black, rotation: -0.2);
    // Neck and head.
    final hy = y - s * (3.55 - nod);
    canvas.drawLine(
      Offset(x - s * 0.5, y - s * 2.3),
      Offset(x - s * 0.85, hy + s * 0.15),
      Paint()
        ..color = white
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.5, s * 0.28),
    );
    canvas.drawCircle(Offset(x - s * 0.9, hy), s * 0.3, Paint()..color = white);
    canvas.drawPath(
      Path()
        ..moveTo(x - s * 1.1, hy)
        ..lineTo(x - s * 2.0, hy + s * 0.2)
        ..lineTo(x - s * 1.1, hy + s * 0.1)
        ..close(),
      Paint()..color = red,
    );
    canvas.drawCircle(Offset(x - s * 0.98, hy - s * 0.07), math.max(0.5, s * 0.06), Paint()..color = black);
  }

  /// Lying down on the right, facing the tree, tail tip twitching.
  void _drawLion(Canvas canvas, Offset p, double scale) {
    final s = math.max(3.0, 2.1 * scale);
    final x = p.dx;
    final y = p.dy;
    final tan = Paint()..color = const Color(0xFFC9973F);
    final mane = Paint()..color = const Color(0xFF8E5E1E);
    final dark = Paint()..color = const Color(0xFF5C3A12);
    final sway = still ? 0.0 : math.sin(timeMs * 0.0018) * 0.15;
    canvas.drawPath(
      Path()
        ..moveTo(x + s * 1.6, y - s * 0.7)
        ..quadraticBezierTo(x + s * 2.2, y - s * 0.7, x + s * (2.4 + sway), y - s * 0.2),
      Paint()
        ..color = tan.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(0.8, s * 0.14),
    );
    canvas.drawCircle(Offset(x + s * (2.45 + sway), y - s * 0.18), s * 0.2, mane);
    fillEllipse(canvas, Offset(x + s * 0.2, y - s * 0.75), s * 1.7, s * 0.7, tan);
    for (final (ox, oy) in const [(-1.0, -0.25), (-0.8, -0.1)]) {
      fillEllipse(canvas, Offset(x + s * ox, y + s * oy), s * 0.7, s * 0.21, tan);
    }
    canvas.drawCircle(Offset(x - s * 1.05, y - s * 1.5), s * 0.85, mane);
    canvas.drawCircle(Offset(x - s * 1.15, y - s * 1.45), s * 0.55, tan);
    for (final ex in const [-0.75, -1.45]) {
      canvas.drawCircle(Offset(x + s * ex, y - s * 1.95), s * 0.16, tan);
    }
    fillEllipse(canvas, Offset(x - s * 1.35, y - s * 1.3), s * 0.32, s * 0.22, Paint()..color = const Color(0xFFEBD9A8));
    canvas.drawCircle(Offset(x - s * 1.6, y - s * 1.38), math.max(0.5, s * 0.08), dark);
    for (final ex in const [-1.3, -1.0]) {
      canvas.drawCircle(Offset(x + s * ex, y - s * 1.6), math.max(0.5, s * 0.06), dark);
    }
  }

  void _drawBees(Canvas canvas, TreeFrame frame) {
    final b = scene.bounds;
    final scale = frame.scale;
    final cx = frame.originX + ((b.minX + b.maxX) / 2) * scale;
    final cy = frame.originY + ((b.minY + kGroundY) / 2) * scale;
    final rx = ((b.maxX - b.minX) / 2) * scale;
    final ry = ((kGroundY - b.minY) / 2) * scale;
    final size = math.max(1.2, 0.6 * scale);
    final wing = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.7);
    final body = Paint()..color = const Color(0xFFF2C744);
    final stripe = Paint()..color = const Color(0xFF3B3330);
    for (final bee in decor.bees) {
      final p = bee.phase * math.pi * 2;
      final tt = still ? 0.0 : timeMs * 0.0011 * bee.speed;
      final x = cx + math.cos(tt + p) * rx * bee.rx;
      final y = cy +
          math.sin(tt * 1.7 + p) * ry * bee.ry +
          (still ? 0.0 : math.sin(timeMs * 0.02 + p) * size * 0.3);
      for (final side in const [-1.0, 1.0]) {
        fillEllipse(
          canvas,
          Offset(x + side * size * 0.4, y - size * 0.7),
          size * 0.45,
          size * 0.3,
          wing,
          rotation: side * -0.6,
        );
      }
      fillEllipse(canvas, Offset(x, y), size, size * 0.65, body);
      canvas.drawRect(Rect.fromLTWH(x - size * 0.18, y - size * 0.6, size * 0.36, size * 1.2), stripe);
    }
  }

  /// A silhouette circling high in the sky, in viewport fractions.
  void _drawEagle(Canvas canvas, TreeFrame frame) {
    final w = frame.width;
    final h = frame.height;
    final cx = w * 0.5;
    final cy = h * 0.16;
    final rx = w * 0.3;
    final ry = h * 0.06;
    final a = (still ? 0.0 : timeMs * 0.00035) + decor.eaglePhase * math.pi * 2;
    final x = cx + math.cos(a) * rx;
    final y = cy + math.sin(a) * ry;
    final heading = math.atan2(math.cos(a) * ry, -math.sin(a) * rx);
    final s = math.max(4.0, w * 0.03);
    final glide = 1 + (still ? 0.0 : 0.08 * math.sin(timeMs * 0.006));
    final paint = Paint()..color = palette.bark.withValues(alpha: 0.85);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(heading);
    canvas.drawPath(
      Path()
        ..moveTo(0, -s * 1.6 * glide)
        ..quadraticBezierTo(-s * 0.45, -s * 0.8, -s * 0.1, 0)
        ..quadraticBezierTo(-s * 0.45, s * 0.8, 0, s * 1.6 * glide)
        ..quadraticBezierTo(s * 0.25, s * 0.8, s * 0.15, 0)
        ..quadraticBezierTo(s * 0.25, -s * 0.8, 0, -s * 1.6 * glide)
        ..close(),
      paint,
    );
    fillEllipse(canvas, Offset.zero, s * 0.55, s * 0.2, paint);
    canvas.drawCircle(Offset(s * 0.6, 0), s * 0.14, paint);
    canvas.restore();
  }

  void _drawButterflies(Canvas canvas, TreeFrame frame) {
    final b = scene.bounds;
    final scale = frame.scale;
    final cx = frame.originX + ((b.minX + b.maxX) / 2) * scale;
    final cy = frame.originY + ((b.minY + kGroundY) / 2) * scale;
    final rx = ((b.maxX - b.minX) / 2) * scale;
    final ry = ((kGroundY - b.minY) / 2) * scale;
    const colours = [Color(0xFFF6C453), Color(0xFFF28CB1), Color(0xFF7EC8E3)];
    final size = math.max(2.0, 1.1 * scale);
    final wing = Paint();
    final bodyPaint = Paint()
      ..color = const Color(0xFF3B3330)
      ..strokeWidth = math.max(0.6, size * 0.16)
      ..strokeCap = StrokeCap.round;
    for (final fly in decor.butterflies) {
      final p = fly.phase * math.pi * 2;
      final tt = still ? 0.0 : timeMs * 0.0004 * fly.speed;
      final x = cx + math.cos(tt + p) * rx * fly.rx;
      final y = cy + math.sin(tt * 1.6 + p) * ry * fly.ry;
      final flap = still ? 0.85 : 0.35 + 0.65 * math.sin(timeMs * 0.018 + p).abs();
      wing.color = colours[fly.hue % colours.length];
      for (final side in const [-1.0, 1.0]) {
        canvas.save();
        canvas.translate(x + side * size * 0.55 * flap, y);
        canvas.rotate(side * 0.4);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: size * 1.2 * flap, height: size * 0.9), wing);
        canvas.restore();
      }
      canvas.drawLine(Offset(x, y - size * 0.45), Offset(x, y + size * 0.45), bodyPaint);
    }
  }

  // ---------------------------------------------------------- foreground

  void paintForeground(Canvas canvas, TreeFrame frame) {
    final scale = frame.scale;
    final groundY = framing == TreeFraming.portrait ? frame.pivotY : frame.pivotY + 0.4 * scale;

    if (animal == TreeAnimal.schaap) {
      _drawSheep(canvas, Offset(frame.pivotX + decor.sheep.$1 * scale, groundY), scale, 1);
      _drawSheep(canvas, Offset(frame.pivotX + decor.sheep.$2 * scale, groundY), scale, -1);
    }
    if (animal == TreeAnimal.hert) {
      _drawDeer(canvas, Offset(frame.pivotX + decor.deer * scale, groundY), scale);
    }
    if (animal == TreeAnimal.vos) {
      _drawFox(canvas, Offset(frame.pivotX + decor.fox * scale, groundY), scale);
    }
    if (animal == TreeAnimal.ezel) {
      _drawDonkey(canvas, Offset(frame.pivotX + decor.donkey * scale, groundY), scale);
    }
    if (animal == TreeAnimal.ooievaar) {
      _drawStork(canvas, Offset(frame.pivotX + decor.stork * scale, groundY), scale);
    }
    if (animal == TreeAnimal.leeuw) {
      _drawLion(canvas, Offset(frame.pivotX + decor.lion * scale, groundY), scale);
    }
    if (animal == TreeAnimal.vlinders) _drawButterflies(canvas, frame);
    if (animal == TreeAnimal.bijen) _drawBees(canvas, frame);
    // The eagle needs a sky: it circles in the scene framing only.
    if (animal == TreeAnimal.adelaar && framing == TreeFraming.scene) _drawEagle(canvas, frame);

    if (animal == TreeAnimal.vuurvliegjes && palette.night) {
      final b = scene.bounds;
      final paint = Paint();
      for (final fly in decor.fireflies) {
        final pulse = 0.25 + 0.75 * math.sin(timeMs * 0.0013 + fly.phase * 6.283).abs();
        final drift = still ? 0.0 : math.sin(timeMs * 0.0005 + fly.phase * 6.283) * 1.6;
        canvas.drawCircle(
          Offset(
            frame.originX + (b.minX + fly.x * (b.maxX - b.minX) + drift) * scale,
            frame.originY + (b.minY + fly.y * (kGroundY - b.minY)) * scale,
          ),
          math.max(0.8, 0.6 * scale),
          paint..color = const Color(0xFFFFE9A8).withValues(alpha: pulse),
        );
      }
    }

    if (framing == TreeFraming.portrait) return;

    // Drifting petals and falling leaves. Autumn drops the occasional leaf for
    // everyone but the evergreens; the blossom storm is the level-25 `seasons`
    // trait and only blows in spring. Both are the same drifters, so a season
    // change costs a colour and nothing else.
    final hasSeasons = level >= kSeasonsTraitLevel;
    final blossom = palette.blossom;
    final drifterColor = palette.season == Season.autumn && !sp.evergreen
        ? palette.leafAlt
        : (hasSeasons && palette.season == Season.spring && blossom != null)
        ? blossom
        : null;
    if (drifterColor != null) {
      // Three at a time in autumn - "occasional" is the point, and a constant
      // fall reads as the tree dying rather than as the season.
      final shown = palette.season == Season.autumn ? 3 : decor.drifters.length;
      final drifterPaint = Paint()..color = drifterColor.withValues(alpha: 0.75);
      for (var i = 0; i < shown; i++) {
        final d = decor.drifters[i];
        final fall = still ? 0.0 : (timeMs * 0.0055 * d.speed) % 130;
        final y = ((d.y + fall) % 130 + 130) % 130 - 15;
        if (y > 100 || y < 0) continue;
        final swayX = still ? 0.0 : math.sin(timeMs * 0.0012 + d.phase * 6.283) * d.drift * 3;
        canvas.save();
        canvas.translate((d.x + swayX) / 100 * frame.width, y / 100 * frame.height);
        canvas.rotate(still ? 0 : timeMs * 0.0016 + d.phase * 6.283);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: d.size * 2 * scale, height: d.size * scale),
          drifterPaint,
        );
        canvas.restore();
      }
    }

    // The level-up column of light.
    if (celebration && !still) {
      final column = Paint();
      for (var i = 0; i < 22; i++) {
        final phase = (i / 22 + timeMs * 0.00022) % 1;
        final y = frame.pivotY - phase * (frame.pivotY - frame.originY);
        final spread = (1 - phase) * 9 * scale;
        canvas.drawCircle(
          Offset(frame.pivotX + math.sin(timeMs * 0.0015 + i) * spread, y),
          math.max(0.7, 0.7 * scale),
          column
            ..color = palette.light.withValues(
              alpha: (0.5 * math.sin(phase * math.pi)).clamp(0.0, 1.0),
            ),
        );
      }
    }

    // Pollen in the sunbeam. Cheap, and most of what makes a still image read
    // as a living scene.
    final paint = Paint();
    for (final mote in decor.motes) {
      final rise = still ? 0.0 : (timeMs * 0.004 * mote.speed) % 100;
      final y = ((mote.y - rise) % 100 + 100) % 100;
      final wobble = still ? 0.0 : math.sin(timeMs * 0.0009 + mote.phase * 6.283) * 1.2;
      final alpha = 0.16 + 0.14 * math.sin(timeMs * 0.001 + mote.phase * 6.283);
      canvas.drawCircle(
        Offset((mote.x + wobble) / 100 * frame.width, y / 100 * frame.height),
        math.max(0.6, mote.r * scale),
        paint..color = palette.light.withValues(alpha: alpha.clamp(0.0, 1.0)),
      );
    }
  }
}
