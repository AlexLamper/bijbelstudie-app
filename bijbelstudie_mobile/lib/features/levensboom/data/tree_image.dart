import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/palette.dart';
import '../domain/tree_generator.dart';
import '../domain/tree_state.dart';
import '../present/tree_view.dart';

/// The two PNGs a notification can carry: the scene for Android's big picture
/// and the iOS attachment, and a small portrait for Android's large icon.
class TreeImageFiles {
  const TreeImageFiles({required this.scenePath, required this.iconPath});

  final String scenePath;
  final String iconPath;
}

/// Renders the reader's tree to files for a notification.
///
/// No widget tree: [TreePainter] is driven directly through a picture
/// recorder, so this can run from the scheduler while the app is backgrounded.
/// Files are overwritten per [name] rather than accumulating, and everything is
/// best-effort - a notification without a picture is still a notification.
///
/// [healthOverride] lets the wilting nudge show the tree as it will look on
/// day three, which is the point of sending it on day two.
Future<TreeImageFiles?> renderTreeImages({
  required TreeState tree,
  required String name,
  double? healthOverride,
  Duration budget = const Duration(milliseconds: 400),
}) async {
  if (tree.seed.isEmpty || tree.disabled) return null;
  final stopwatch = Stopwatch()..start();
  try {
    final dir = Directory('${(await getTemporaryDirectory()).path}/levensboom');
    await dir.create(recursive: true);
    final scenePath = '${dir.path}/$name-scene.png';
    final iconPath = '${dir.path}/$name-icon.png';

    final health = healthOverride ?? tree.health;
    final scene = generateTree(
      seed: tree.seed,
      level: tree.level,
      frac: tree.progress,
      health: health,
      species: tree.avatar.species,
    );
    final palette = paletteForNow(
      health: health,
      scene: tree.avatar.scene,
      species: tree.avatar.species,
    );
    final decor = TreeDecor(tree.seed);

    await _paintToFile(
      const Size(1024, 640),
      TreeFraming.scene,
      scene,
      palette,
      decor,
      tree,
      scenePath,
    );
    // A slow device gets the big picture and skips the icon rather than
    // holding the scheduler up for a 256 px thumbnail.
    if (stopwatch.elapsed > budget) return TreeImageFiles(scenePath: scenePath, iconPath: scenePath);
    await _paintToFile(
      const Size(256, 256),
      TreeFraming.portrait,
      scene,
      palette,
      decor,
      tree,
      iconPath,
    );
    return TreeImageFiles(scenePath: scenePath, iconPath: iconPath);
  } catch (_) {
    return null;
  }
}

Future<void> _paintToFile(
  Size size,
  TreeFraming framing,
  TreeScene scene,
  TreePalette palette,
  TreeDecor decor,
  TreeState tree,
  String path,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  final layer = BranchLayer();
  TreePainter(
    scene: scene,
    palette: palette,
    decor: decor,
    layer: layer,
    reveal: 1,
    timeMs: 0,
    still: true,
    level: scene.level,
    celebration: false,
    bloomFruit: null,
    framing: framing,
    animal: tree.avatar.animal,
  ).paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    await File(path).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  } finally {
    image.dispose();
    picture.dispose();
    layer.dispose();
  }
}
