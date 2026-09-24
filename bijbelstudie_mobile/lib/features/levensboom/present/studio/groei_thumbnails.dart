import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/catalog.dart';
import '../../domain/palette.dart';
import '../../domain/scenes.dart';
import '../../domain/species.dart';
import '../../domain/tree_generator.dart';
import '../tree_view.dart';

/// A small still portrait of the reader's own tree at one level, for the rows
/// of the Groei ladder.
///
/// Twenty live [TreeView]s in a scrolling list are twenty generator runs and
/// twenty custom painters repainting on every scroll frame - too much for a
/// low-end Android. So each thumbnail is rendered once into an image, kept for
/// the session, and drawn as a plain [RawImage] after that. Rendering is lazy
/// (only rows the list actually builds ask) and spread out: at most one
/// thumbnail is rendered per frame, the rest wait their turn behind a quiet
/// placeholder.
///
/// Daylight and full health on purpose: the ladder shows how the tree grows,
/// not how it looks tonight or after a week away.
///
/// [silhouette] greys the picture out: the step the tree reaches next is a
/// shape to look forward to, not a finished portrait.
class GroeiThumbnail extends StatefulWidget {
  const GroeiThumbnail({
    super.key,
    required this.seed,
    required this.level,
    required this.species,
    required this.scene,
    this.size = 44,
    this.silhouette = false,
  });

  final String seed;
  final int level;
  final TreeSpecies species;
  final TreeSceneId scene;
  final double size;
  final bool silhouette;

  @override
  State<GroeiThumbnail> createState() => _GroeiThumbnailState();
}

class _GroeiThumbnailState extends State<GroeiThumbnail> {
  /// This widget's own handle on the cached image; disposed with the widget.
  ui.Image? _image;
  String? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(GroeiThumbnail old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final spec = _ThumbSpec(
      seed: widget.seed,
      level: widget.level,
      species: widget.species,
      scene: widget.scene,
      size: widget.size,
      dpr: (MediaQuery.maybeDevicePixelRatioOf(context) ?? 2).clamp(1.0, 3.0),
      season: seasonForMonth(DateTime.now().month),
    );
    if (spec.key == _key) return;
    _GroeiThumbnailCache.cancel(this);
    _key = spec.key;
    _image?.dispose();
    _image = _GroeiThumbnailCache.take(spec.key);
    if (_image == null) _GroeiThumbnailCache.request(this, spec);
  }

  void _ready(String key) {
    if (!mounted || key != _key) return;
    final image = _GroeiThumbnailCache.take(key);
    if (image == null) return;
    setState(() {
      _image?.dispose();
      _image = image;
    });
  }

  @override
  void dispose() {
    _GroeiThumbnailCache.cancel(this);
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final size = widget.size;
    final image = _image;
    Widget child = image == null
        ? ColoredBox(color: AppTheme.paperSunken)
        : RawImage(image: image, width: size, height: size, fit: BoxFit.cover);
    if (widget.silhouette && image != null) {
      child = Opacity(
        opacity: 0.45,
        child: ColorFiltered(colorFilter: _greyscale, child: child),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(child: child),
    );
  }
}

/// Luminance only: the silhouette keeps the shape and loses the colour.
const ColorFilter _greyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// The empty ring with a question mark for a step further out than the next.
class GroeiThumbnailUnknown extends StatelessWidget {
  const GroeiThumbnailUnknown({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.ruleStrong, width: 1.5),
      ),
      child: Text(
        '?',
        style: AppTheme.bodyStrong.copyWith(color: AppTheme.inkFaint),
      ),
    );
  }
}

class _ThumbSpec {
  const _ThumbSpec({
    required this.seed,
    required this.level,
    required this.species,
    required this.scene,
    required this.size,
    required this.dpr,
    required this.season,
  });

  final String seed;
  final int level;
  final TreeSpecies species;
  final TreeSceneId scene;
  final double size;
  final double dpr;
  final Season season;

  int get pixels => (size * dpr).round().clamp(1, 512);

  String get key =>
      '$seed|${kSpeciesIds[species]}|${scene.name}|$level|$pixels|${season.name}';
}

class _Request {
  _Request(this.owner, this.spec);

  final _GroeiThumbnailState owner;
  final _ThumbSpec spec;
}

/// The session's rendered thumbnails, least recently used out first, and the
/// one-per-frame render queue.
class _GroeiThumbnailCache {
  _GroeiThumbnailCache._();

  /// The ladder has 20 rows; a species or scene change in the studio renders
  /// a second set, so room for two.
  static const int _maxEntries = 48;

  static final Map<String, ui.Image> _images = {};
  static final List<_Request> _queue = [];
  static bool _scheduled = false;

  /// A clone of the cached image for [key], owned by the caller, or null.
  static ui.Image? take(String key) {
    final hit = _images.remove(key);
    if (hit == null) return null;
    _images[key] = hit;
    return hit.clone();
  }

  static void request(_GroeiThumbnailState owner, _ThumbSpec spec) {
    _queue.add(_Request(owner, spec));
    _schedule();
  }

  static void cancel(_GroeiThumbnailState owner) {
    _queue.removeWhere((r) => identical(r.owner, owner));
  }

  static void _schedule() {
    if (_scheduled || _queue.isEmpty) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _renderNext());
    SchedulerBinding.instance.scheduleFrame();
  }

  static void _renderNext() {
    _scheduled = false;
    if (_queue.isEmpty) return;
    final next = _queue.removeAt(0);
    final key = next.spec.key;
    if (!_images.containsKey(key)) {
      final image = _render(next.spec);
      if (image != null) _store(key, image);
    }
    // Everyone waiting on the same picture gets it now.
    final served = [next, ..._queue.where((r) => r.spec.key == key)];
    _queue.removeWhere((r) => r.spec.key == key);
    for (final request in served) {
      request.owner._ready(key);
    }
    _schedule();
  }

  static void _store(String key, ui.Image image) {
    _images[key] = image;
    while (_images.length > _maxEntries) {
      final oldest = _images.keys.first;
      _images.remove(oldest)?.dispose();
    }
  }

  static ui.Image? _render(_ThumbSpec spec) {
    final layer = BranchLayer();
    try {
      final scene = generateTree(
        seed: spec.seed,
        level: spec.level,
        frac: 0,
        health: 1,
        species: spec.species,
      );
      final palette = buildPalette(
        spec.season,
        DayPhase.day,
        scene: spec.scene,
        species: spec.species,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(spec.dpr);
      TreePainter(
        scene: scene,
        palette: palette,
        decor: TreeDecor(spec.seed),
        layer: layer,
        reveal: 1,
        timeMs: 0,
        still: true,
        level: scene.level,
        celebration: false,
        bloomFruit: null,
        framing: TreeFraming.portrait,
        animal: TreeAnimal.geen,
      ).paint(canvas, Size.square(spec.size));
      final picture = recorder.endRecording();
      try {
        return picture.toImageSync(spec.pixels, spec.pixels);
      } finally {
        picture.dispose();
      }
    } catch (_) {
      // A thumbnail that cannot be drawn stays a placeholder.
      return null;
    } finally {
      layer.dispose();
    }
  }
}
