/// Where the tree sits in a frame, growth v2 (plan §4.8). Mirror of the
/// website's `lib/levensboom/camera.ts`, same arithmetic in the same order.
///
/// v1 fitted the tree to the frame, so from level 3 on every tree filled it and
/// growth was invisible as size. Now the landscape stays put and the tree
/// takes a designed share of it: [fillScene] of the position, about 22 % at
/// step 1 to 84 % at step 20, of whichever dimension binds (a tall, narrow
/// frame like the lesson card shows growth as width, a wide one as height).
/// The share is exact for every seed, so every step is bigger on screen than
/// the last and a level-up never zooms out past the tree. Bounds include
/// wilted leaves, so health never moves the camera.
///
/// One function for every renderer: `measureTreeFrame` in
/// `present/backdrop_painter.dart` delegates here.
library;

import 'dart:math' as math;

import 'growth.dart';
import 'tree_generator.dart';

/// Two framings. [TreeFraming.scene] is the landscape: sky, backdrop, a band
/// of earth the trunk stands *in*, animals. [TreeFraming.portrait] is the
/// avatar: the tree alone on a sky disc, for the tab bar and every other place
/// a small face has to read.
enum TreeFraming { scene, portrait }

/// The website's camera `Frame`: where tree space lands in pixels.
class CameraFrame {
  const CameraFrame({
    required this.scale,
    required this.originX,
    required this.originY,
    required this.pivotX,
    required this.pivotY,
    required this.groundTop,
    required this.guarded,
  });

  final double scale;
  final double originX;
  final double originY;

  /// The trunk base on screen.
  final double pivotX;
  final double pivotY;

  /// Top of the earth band (scene) or of the ground disc (portrait).
  final double groundTop;

  /// True when the extents (a ground animal) forced the camera out past the designed fill.
  final bool guarded;
}

/// Share of a scene frame's height that is earth under the ground line.
const double kEarthBand = 0.12;

/// Share of the frame width either side of the trunk a scene may use.
const double kHalfWidth = 0.48;

/// Extra room, in tree units either side of the trunk / above the ground, that
/// must stay in frame (a ground animal). The website's `FrameExtents`.
class FrameExtents {
  const FrameExtents({this.left, this.right, this.top});

  final double? left;
  final double? right;
  final double? top;
}

CameraFrame measureFrame(
  double width,
  double height,
  TreeScene scene,
  TreeFraming framing, [
  FrameExtents? extents,
]) {
  final minX = scene.bounds.minX;
  final maxX = scene.bounds.maxX;
  final minY = scene.bounds.minY;
  final treeH = math.max(1.0, kGroundY - minY);

  if (framing == TreeFraming.portrait) {
    final padX = width * 0.1;
    final padY = height * 0.1;
    final contentW = math.max(1.0, maxX - minX);
    final fit = math.min((width - 2 * padX) / contentW, (height - 2 * padY) / treeH);
    // Below 32 px legibility beats the growth story: fit the bounds.
    final scale = math.min(width, height) >= portraitFitBelowPx ? fit * fillPortrait(scene.position) : fit;
    final originX = width / 2 - ((minX + maxX) / 2) * scale;
    final pivotY = height - padY * 1.15;
    final originY = pivotY - kGroundY * scale;
    return CameraFrame(
      scale: scale,
      originX: originX,
      originY: originY,
      pivotX: originX + kTrunkX * scale,
      pivotY: pivotY,
      groundTop: pivotY,
      guarded: false,
    );
  }

  final band = height * kEarthBand;
  final groundTop = height - band;
  final half = math.max(math.max(kTrunkX - minX, maxX - kTrunkX), 1e-6);
  final designed = fillScene(scene.position) * math.min(groundTop / treeH, (width * kHalfWidth) / half);
  // Centred on the trunk base, so an asymmetric crown never slides the tree
  // sideways as it grows.
  final room = math.max(math.max(half, extents?.left ?? 0.0), extents?.right ?? 0.0);
  final guard = math.min(
    (groundTop * 0.95) / math.max(treeH, extents?.top ?? 0.0),
    (width * kHalfWidth) / room,
  );
  final scale = math.min(designed, guard);
  final pivotY = groundTop + 0.6 * scale;
  final originX = width / 2 - kTrunkX * scale;
  final originY = pivotY - kGroundY * scale;
  return CameraFrame(
    scale: scale,
    originX: originX,
    originY: originY,
    pivotX: width / 2,
    pivotY: pivotY,
    groundTop: groundTop,
    guarded: designed > guard,
  );
}
