import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/palette.dart';
import '../domain/tree_generator.dart';
import '../domain/tree_state.dart';
import '../domain/verse_scene.dart';
import '../present/tree_view.dart';
import '../present/verse_scene_painter.dart';

/// The two PNGs a notification can carry: the wide scene for Android's big
/// picture and the iOS attachment, and a square portrait for Android's large
/// icon and the iOS collapsed thumbnail.
class TreeImageFiles {
  const TreeImageFiles({required this.scenePath, required this.iconPath});

  final String scenePath;
  final String iconPath;
}

/// Android expands a big picture at 2:1; the old 1024x640 lost its top and
/// bottom to that crop.
const Size kNotifSceneSize = Size(1024, 512);

/// iOS centre-crops an attachment for the collapsed banner, so the thumbnail is
/// rendered square rather than cropped out of the wide scene.
const Size kNotifThumbSize = Size(512, 512);

/// Chrome never enters the outer margin: OEMs crop big pictures differently.
const double _kSafe = 0.06;

/// What the picture is of.
enum NotifArtKind {
  /// The reader's own Levensboom.
  tree,

  /// The day's generated landscape, for the daily verse.
  verse,
}

/// One notification's picture, described (`AVATAR_NOTIFICATIONS_PLAN.md` §2.3).
///
/// Everything is optional except the subject: a spec with no streak, no
/// countdown and no level renders exactly the bare scene the app shipped
/// before, which is also the fallback when a value cannot be trusted.
class NotifArtSpec {
  const NotifArtSpec.tree({
    required TreeState this.tree,
    this.healthOverride,
    this.celebration = false,
    this.streak,
    this.countdown,
    this.level,
    this.levelFrac,
  })  : kind = NotifArtKind.tree,
        verse = null,
        verseText = null,
        verseRef = null;

  const NotifArtSpec.verse({
    required VerseScene this.verse,
    this.verseText,
    this.verseRef,
  })  : kind = NotifArtKind.verse,
        tree = null,
        healthOverride = null,
        celebration = false,
        streak = null,
        countdown = null,
        level = null,
        levelFrac = null;

  final NotifArtKind kind;

  final TreeState? tree;

  /// Shows the tree as it *will* look - the loss frame the wilting nudge uses
  /// (§4, D13). Null keeps the tree honest.
  final double? healthOverride;

  final bool celebration;

  /// Burned into the picture bottom-left. Null, or under 2, draws no chip: a
  /// "1" is not a streak and drawing it teaches the reader the number is noise.
  final int? streak;

  /// Already resolved to words - "Nog 3 uur". Null draws no pill.
  final String? countdown;

  final int? level;

  /// 0..1 through the current level, for the ring beside [level].
  final double? levelFrac;

  final VerseScene? verse;
  final String? verseText;
  final String? verseRef;

  /// Long verses go to the app; the picture keeps the opening.
  static const int kVerseLimit = 180;
}

/// Renders [spec] to a scene PNG and a thumbnail PNG under the notification art
/// cache, and returns their paths.
///
/// No widget tree: the painters are driven through a [ui.PictureRecorder], so
/// this runs from the scheduler with the app backgrounded. Files are
/// overwritten per [name] rather than accumulating. Everything is best-effort -
/// a notification without a picture is still a notification, so every failure
/// path returns null instead of throwing.
Future<TreeImageFiles?> renderNotificationArt(
  NotifArtSpec spec, {
  required String name,
  Duration budget = const Duration(milliseconds: 900),
  DateTime? at,
}) async {
  final stopwatch = Stopwatch()..start();
  try {
    final dir = await notifArtDir();
    final scenePath = '${dir.path}/$name-scene.png';
    final thumbPath = '${dir.path}/$name-thumb.png';

    final subject = _Subject.of(spec, at);
    if (subject == null) return null;

    await _paintToFile(kNotifSceneSize, TreeFraming.scene, subject, spec, scenePath);
    // A slow device gets the big picture and skips the thumbnail rather than
    // holding the scheduler up for a 512 px square.
    if (stopwatch.elapsed > budget) {
      return TreeImageFiles(scenePath: scenePath, iconPath: scenePath);
    }
    await _paintToFile(kNotifThumbSize, TreeFraming.portrait, subject, spec, thumbPath);
    return TreeImageFiles(scenePath: scenePath, iconPath: thumbPath);
  } catch (_) {
    return null;
  }
}

/// Where rendered notification art lives. Created on demand.
Future<Directory> notifArtDir() async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/levensboom/notif');
  await dir.create(recursive: true);
  return dir;
}

/// What actually gets painted, resolved once and reused for both sizes.
class _Subject {
  _Subject.tree(this.scene, this.palette, this.decor, this.tree)
      : verseArt = null;
  _Subject.verse(this.verseArt, this.palette)
      : scene = null,
        decor = null,
        tree = null;

  static _Subject? of(NotifArtSpec spec, DateTime? at) {
    if (spec.kind == NotifArtKind.verse) {
      final verse = spec.verse!;
      return _Subject.verse(
        VerseSceneArt(verse),
        verseScenePalette(verse, at: at),
      );
    }
    final tree = spec.tree!;
    if (tree.seed.isEmpty || tree.disabled) return null;
    final health = spec.healthOverride ?? tree.health;
    return _Subject.tree(
      generateTree(
        seed: tree.seed,
        level: tree.level,
        frac: tree.progress,
        health: health,
        species: tree.avatar.species,
      ),
      paletteForNow(
        health: health,
        scene: tree.avatar.scene,
        species: tree.avatar.species,
        now: at,
      ),
      TreeDecor(tree.seed),
      tree,
    );
  }

  final TreeScene? scene;
  final TreeDecor? decor;
  final TreeState? tree;
  final VerseSceneArt? verseArt;
  final TreePalette palette;
}

Future<void> _paintToFile(
  Size size,
  TreeFraming framing,
  _Subject subject,
  NotifArtSpec spec,
  String path,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  BranchLayer? layer;

  if (subject.verseArt != null) {
    VerseScenePainter(art: subject.verseArt!, palette: subject.palette)
        .paint(canvas, size);
  } else {
    layer = BranchLayer();
    TreePainter(
      scene: subject.scene!,
      palette: subject.palette,
      decor: subject.decor!,
      layer: layer,
      reveal: 1,
      timeMs: 0,
      still: true,
      level: subject.scene!.level,
      celebration: spec.celebration,
      bloomFruit: null,
      framing: framing,
      animal: subject.tree!.avatar.animal,
    ).paint(canvas, size);
  }

  // The thumbnail is a face, not a dashboard: chrome would be illegible at the
  // size it is actually shown.
  if (framing == TreeFraming.scene) {
    _paintChrome(canvas, size, spec, subject.palette);
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    await File(path).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  } finally {
    image.dispose();
    picture.dispose();
    layer?.dispose();
  }
}

// --------------------------------------------------------------- chrome

void _paintChrome(Canvas canvas, Size size, NotifArtSpec spec, TreePalette palette) {
  final hasStreak = spec.streak != null && spec.streak! >= 2;
  final hasCountdown = spec.countdown != null && spec.countdown!.isNotEmpty;
  final hasVerse = spec.verseText != null && spec.verseText!.trim().isNotEmpty;
  final hasLevel = spec.level != null;
  if (!hasStreak && !hasCountdown && !hasVerse && !hasLevel) return;

  final inset = size.width * _kSafe;

  if (hasStreak || hasCountdown || hasVerse) {
    canvas.drawRect(
      Rect.fromLTRB(0, size.height * 0.42, size.width, size.height),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, size.height * 0.42),
          Offset(0, size.height),
          [const Color(0x00000000), const Color(0x8C000000)],
        ),
    );
  }

  if (hasVerse) _paintVerse(canvas, size, spec, inset);
  if (hasStreak) _paintStreak(canvas, size, spec.streak!, inset, palette);
  if (hasCountdown) _paintCountdown(canvas, size, spec.countdown!, inset);
  if (hasLevel) _paintLevelRing(canvas, size, spec, inset, palette);
}

TextPainter _text(
  String value,
  double fontSize, {
  FontWeight weight = FontWeight.w600,
  Color color = Colors.white,
  double maxWidth = double.infinity,
  int? maxLines,
  double height = 1.15,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: value,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: weight,
        height: height,
        letterSpacing: -0.2,
        shadows: const [Shadow(color: Color(0x66000000), blurRadius: 8)],
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: maxLines,
    ellipsis: maxLines == null ? null : '…',
  )..layout(maxWidth: maxWidth);
  return painter;
}

/// A flame, drawn rather than borrowed from an icon font: the render can run
/// with no widget binding, where a font lookup is not something to rely on.
Path _flamePath(Rect box) {
  final w = box.width;
  final h = box.height;
  final x = box.left;
  final y = box.top;
  return Path()
    ..moveTo(x + w * 0.5, y)
    ..cubicTo(x + w * 0.86, y + h * 0.3, x + w * 0.98, y + h * 0.56, x + w * 0.82, y + h * 0.78)
    ..cubicTo(x + w * 0.7, y + h * 0.96, x + w * 0.3, y + h * 0.96, x + w * 0.18, y + h * 0.78)
    ..cubicTo(x + w * 0.02, y + h * 0.56, x + w * 0.16, y + h * 0.32, x + w * 0.4, y + h * 0.16)
    ..cubicTo(x + w * 0.42, y + h * 0.4, x + w * 0.56, y + h * 0.46, x + w * 0.5, y)
    ..close();
}

void _paintStreak(
  Canvas canvas, Size size, int streak, double inset, TreePalette palette) {
  final number = _text('$streak', size.height * 0.19, weight: FontWeight.w800);
  final unit = _text(
    streak == 1 ? 'dag' : 'dagen',
    size.height * 0.062,
    weight: FontWeight.w600,
    color: Colors.white.withValues(alpha: 0.86),
  );

  final flameBox = Rect.fromLTWH(
    inset,
    size.height - inset - number.height * 0.92,
    number.height * 0.62,
    number.height * 0.82,
  );
  canvas.drawPath(
    _flamePath(flameBox),
    Paint()
      ..shader = ui.Gradient.linear(
        flameBox.topCenter,
        flameBox.bottomCenter,
        [palette.light, palette.accent],
      ),
  );

  final numberX = flameBox.right + size.width * 0.014;
  number.paint(canvas, Offset(numberX, size.height - inset - number.height));
  unit.paint(
    canvas,
    Offset(numberX + number.width + size.width * 0.01,
        size.height - inset - unit.height * 1.25),
  );
}

void _paintCountdown(Canvas canvas, Size size, String label, double inset) {
  final text = _text(label, size.height * 0.062, weight: FontWeight.w600);
  final padX = size.width * 0.016;
  final padY = size.height * 0.022;
  final rect = Rect.fromLTWH(
    size.width - inset - text.width - padX * 2,
    size.height - inset - text.height - padY * 2,
    text.width + padX * 2,
    text.height + padY * 2,
  );
  final radius = RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
  canvas.drawRRect(radius, Paint()..color = const Color(0x40000000));
  canvas.drawRRect(
    radius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, size.height * 0.004)
      ..color = Colors.white.withValues(alpha: 0.4),
  );
  text.paint(canvas, Offset(rect.left + padX, rect.top + padY));
}

void _paintLevelRing(
    Canvas canvas, Size size, NotifArtSpec spec, double inset, TreePalette palette) {
  final radius = size.height * 0.09;
  final centre = Offset(size.width - inset - radius, inset + radius);
  final stroke = math.max(2.0, size.height * 0.012);

  canvas.drawCircle(centre, radius, Paint()..color = const Color(0x38000000));
  canvas.drawCircle(
    centre,
    radius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withValues(alpha: 0.28),
  );
  final frac = (spec.levelFrac ?? 0).clamp(0.0, 1.0);
  if (frac > 0) {
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      math.pi * 2 * frac,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = palette.light,
    );
  }
  final number = _text('${spec.level}', radius * 0.9, weight: FontWeight.w700);
  number.paint(canvas, centre - Offset(number.width / 2, number.height / 2));
}

void _paintVerse(Canvas canvas, Size size, NotifArtSpec spec, double inset) {
  var body = spec.verseText!.trim();
  if (body.length > NotifArtSpec.kVerseLimit) {
    body = '${body.substring(0, NotifArtSpec.kVerseLimit).trimRight()}…';
  }
  final maxWidth = size.width * 0.78;
  final text = _text(
    body,
    size.height * 0.072,
    weight: FontWeight.w600,
    maxWidth: maxWidth,
    maxLines: 4,
    height: 1.3,
  );
  final ref = spec.verseRef == null || spec.verseRef!.isEmpty
      ? null
      : _text(
          spec.verseRef!,
          size.height * 0.056,
          weight: FontWeight.w500,
          color: Colors.white.withValues(alpha: 0.82),
          maxWidth: maxWidth,
          maxLines: 1,
        );

  final block = text.height + (ref == null ? 0 : ref.height + size.height * 0.028);
  var top = size.height - inset - block;
  // Keep the verse off the horizon when it runs long.
  top = math.max(top, size.height * 0.2);

  text.paint(canvas, Offset(inset, top));
  ref?.paint(canvas, Offset(inset, top + text.height + size.height * 0.028));
}
