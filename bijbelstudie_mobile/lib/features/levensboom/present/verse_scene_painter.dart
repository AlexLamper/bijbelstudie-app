import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../domain/palette.dart';
import '../domain/tree_generator.dart';
import '../domain/verse_scene.dart';
import 'backdrop_painter.dart';

/// The generated half of a [VerseScene]: everything the painter needs that is
/// worth computing once a day rather than once a frame.
///
/// A tree *is* generated - the frame, the ground extent and the species' own
/// details are measured from it - but no branch is ever painted. It is the
/// cheapest way to reuse the tree's world without special-casing every routine
/// in [SceneLayers].
class VerseSceneArt {
  VerseSceneArt._(this.verse, this.scene, this.decor);

  factory VerseSceneArt(VerseScene verse) {
    final cached = _cache[verse.key];
    if (cached != null) return cached;
    final art = VerseSceneArt._(
      verse,
      generateTree(
        seed: verse.seed,
        level: 18,
        frac: 0.6,
        health: 1,
        species: verse.species,
      ),
      TreeDecor(verse.seed),
    );
    // One day's art at a time: yesterday's is never asked for twice.
    if (_cache.length > 2) _cache.clear();
    _cache[verse.key] = art;
    return art;
  }

  static final Map<String, VerseSceneArt> _cache = {};

  final VerseScene verse;
  final TreeScene scene;
  final TreeDecor decor;
}

/// Paints a [VerseScene]: sky, weather, distance, earth and whatever lives on
/// it - and no tree.
class VerseScenePainter extends CustomPainter with SceneLayers {
  VerseScenePainter({
    required this.art,
    required this.palette,
    this.timeMs = 0,
  });

  final VerseSceneArt art;

  @override
  final TreePalette palette;

  @override
  final double timeMs;

  @override
  TreeScene get scene => art.scene;

  @override
  TreeDecor get decor => art.decor;

  @override
  TreeFraming get framing => TreeFraming.scene;

  @override
  TreeAnimal get animal => art.verse.animal;

  @override
  bool get still => timeMs == 0;

  @override
  bool get celebration => false;

  @override
  int get level => art.scene.level;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = measureTreeFrame(size, scene, framing, animal, decor);
    paintSky(canvas, frame);
    paintClouds(
      canvas,
      frame,
      seed: art.verse.cloudSeed,
      drift: art.verse.driftPhase,
    );
    // Draws the far and near backdrops on its way to the earth band.
    paintGround(canvas, frame);
    paintForeground(canvas, frame);
  }

  @override
  bool shouldRepaint(VerseScenePainter old) =>
      old.timeMs != timeMs ||
      !identical(old.palette, palette) ||
      !identical(old.art, art);
}
