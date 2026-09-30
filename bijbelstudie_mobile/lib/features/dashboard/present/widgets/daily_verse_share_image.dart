import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../levensboom/domain/verse_scene.dart';
import '../../data/daily_verse_background_store.dart';
import 'daily_verse_background.dart';
import 'daily_verse_photo.dart';

/// The share image's size in logical pixels; captured at [_pixelRatio] this
/// is 1080 x 1920, the 9:16 of a WhatsApp or Instagram status.
const Size _logicalSize = Size(360, 640);
const double _pixelRatio = 3;

const String _logoAsset = 'assets/images/app_icon.png';

/// Renders the daily verse as a portrait status image, YouVersion style, and
/// writes it to the temp directory as a PNG. Returns the file's path.
///
/// The image is laid out and painted for real, off screen: an [OverlayEntry]
/// parked well outside the visible area holds a [RepaintBoundary], which is
/// captured with [RenderRepaintBoundary.toImage] once the frame it was painted
/// in has finished. The day's photo and the logo are precached first so the
/// capture never catches either mid-decode (the tree page falls back to the
/// photo too); the tree is painted, with `still: true`, on its first frame.
Future<String> renderDailyVerseShareImage(
  BuildContext context, {
  required DailyVerseBackground background,
  required VerseScene scene,
  required String text,
  required String reference,
  required String version,
  String? attribution,
}) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  final mediaQuery = MediaQuery.of(context);
  await Future.wait([
    precacheImage(AssetImage(dailyVersePhotoAsset(scene.key)), context),
    precacheImage(const AssetImage(_logoAsset), context),
  ]);

  final boundaryKey = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -(_logicalSize.width * 4),
      top: 0,
      width: _logicalSize.width,
      height: _logicalSize.height,
      child: IgnorePointer(
        child: MediaQuery(
          // Fixed type and no motion: the image must not depend on the
          // phone's text size, and nothing should be mid-animation.
          data: mediaQuery.copyWith(
            size: _logicalSize,
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
            viewInsets: EdgeInsets.zero,
            textScaler: TextScaler.noScaling,
            disableAnimations: true,
          ),
          child: RepaintBoundary(
            key: boundaryKey,
            child: Material(
              type: MaterialType.transparency,
              child: DailyVerseShareCanvas(
                background: background,
                scene: scene,
                text: text,
                reference: reference,
                version: version,
                attribution: attribution,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  try {
    // One frame to build, lay out and paint; a second so anything that
    // settled on the first (a provider value, a painter's first layout) is
    // in the layer that gets captured.
    await WidgetsBinding.instance.endOfFrame;
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;

    final boundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('PNG encoding failed');
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final stamp =
          '${now.year}${_two(now.month)}${_two(now.day)}-'
          '${now.millisecondsSinceEpoch % 100000}';
      final file = File('${dir.path}/tekst-van-de-dag-$stamp.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      return file.path;
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// The status image itself, at [_logicalSize]: the reader's background edge to
/// edge, a wash for legibility, the verse centred and as large as it fits,
/// the reference under it and a small wordmark at the foot.
class DailyVerseShareCanvas extends StatelessWidget {
  const DailyVerseShareCanvas({
    super.key,
    required this.background,
    required this.scene,
    required this.text,
    required this.reference,
    required this.version,
    this.attribution,
  });

  final DailyVerseBackground background;
  final VerseScene scene;
  final String text;
  final String reference;
  final String version;
  final String? attribution;

  static const double _side = 34;
  static const _shadow = [
    Shadow(offset: Offset(0, 1), blurRadius: 4, color: Color(0x66000000)),
  ];

  @override
  Widget build(BuildContext context) {
    final label = version.isEmpty ? reference : '$reference $version';
    return Stack(
      fit: StackFit.expand,
      children: [
        DailyVerseBackgroundView(kind: background, scene: scene, still: true),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.35),
                Colors.black.withValues(alpha: 0.45),
                Colors.black.withValues(alpha: 0.45),
                Colors.black.withValues(alpha: 0.62),
              ],
              stops: const [0, 0.3, 0.7, 1],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(_side, 72, _side, 0),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => Center(
                    child: _Verse(
                      text: text,
                      label: label,
                      attribution: attribution,
                      width: box.maxWidth,
                      height: box.maxHeight,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const _Wordmark(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }
}

/// Verse, reference and licence notice, centred; the verse's size is the
/// largest step that lets all three fit the box.
class _Verse extends StatelessWidget {
  const _Verse({
    required this.text,
    required this.label,
    required this.attribution,
    required this.width,
    required this.height,
  });

  final String text;
  final String label;
  final String? attribution;
  final double width;
  final double height;

  static const double _maxSize = 30;
  static const double _minSize = 13;

  TextStyle _verseStyle(double size) => TextStyle(
    fontFamily: AppTheme.serifFontName,
    fontSize: size,
    height: 1.45,
    fontWeight: FontWeight.w500,
    color: Colors.white,
    shadows: DailyVerseShareCanvas._shadow,
  );

  static const TextStyle _labelStyle = TextStyle(
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
    color: Colors.white,
    shadows: DailyVerseShareCanvas._shadow,
  );

  static TextStyle get _noticeStyle => TextStyle(
    fontSize: 9.5,
    height: 1.3,
    color: Colors.white.withValues(alpha: 0.8),
  );

  double _measure(String value, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    final h = painter.height;
    painter.dispose();
    return h;
  }

  double _fittedSize(double reserved) {
    for (var size = _maxSize; size > _minSize; size -= 1) {
      if (_measure(text, _verseStyle(size)) + reserved <= height) return size;
    }
    return _minSize;
  }

  @override
  Widget build(BuildContext context) {
    final notice = attribution;
    final reserved =
        22 +
        _measure(label, _labelStyle) +
        (notice == null ? 0 : 10 + _measure(notice, _noticeStyle));
    final size = _fittedSize(reserved);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Flexible as a last resort: past the smallest size a verse is cut
        // off with an ellipsis rather than pushing the reference out.
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: _verseStyle(size),
            overflow: TextOverflow.ellipsis,
            maxLines: (height / (size * 1.45)).floor().clamp(1, 60),
          ),
        ),
        const SizedBox(height: 22),
        Text(label, textAlign: TextAlign.center, style: _labelStyle),
        if (notice != null) ...[
          const SizedBox(height: 10),
          Text(notice, textAlign: TextAlign.center, style: _noticeStyle),
        ],
      ],
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.85,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Image.asset(
              _logoAsset,
              width: 18,
              height: 18,
              filterQuality: FilterQuality.medium,
            ),
          ),
          const SizedBox(width: 7),
          const Text(
            'bijbelstudie.io',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: Colors.white,
              shadows: DailyVerseShareCanvas._shadow,
            ),
          ),
        ],
      ),
    );
  }
}
