import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../progress_tree/domain/verse_scene.dart';
import '../../data/daily_verse_background_store.dart';
import 'daily_verse_background.dart';
import 'daily_verse_photo.dart';
import 'daily_verse_scrim.dart';

/// The share image's size in logical pixels; captured at [_pixelRatio] this
/// is 1440 x 2560, the 9:16 of a WhatsApp or Instagram status. Above the
/// 1080 x 1920 those apps show, so they only ever scale it down.
const Size _logicalSize = Size(360, 640);
const double _pixelRatio = 4;

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
/// On the photo background the photo is fetched full size from Pexels first,
/// so it is not the bundled 900x1200 copy blown up; offline it is that copy.
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
  final photo = background == DailyVerseBackground.photo
      ? await _fullSizePhoto(context, scene.key)
      : null;
  if (!context.mounted) throw StateError('Share source is gone');
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
                photo: photo,
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

/// The day's photo at the share image's full pixel size, decoded and cached;
/// null when it cannot be had (offline, slow, a bad response), so the caller
/// falls back to the bundled asset rather than failing the share.
Future<ImageProvider?> _fullSizePhoto(BuildContext context, String dayKey) async {
  try {
    final uri = dailyVersePhotoUrl(
      dayKey,
      width: (_logicalSize.width * _pixelRatio).round(),
      height: (_logicalSize.height * _pixelRatio).round(),
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
    if (!context.mounted) return null;
    final image = MemoryImage(response.bodyBytes);
    var decoded = true;
    await precacheImage(image, context, onError: (_, _) => decoded = false);
    return decoded ? image : null;
  } on Object {
    return null;
  }
}

/// The status image itself, at [_logicalSize], laid out like the card on the
/// Start tab: the reader's background under the card's scrim, "Tekst van de
/// dag" and the reference at the top left, the verse left aligned in serif
/// below it, the licence notice and a small wordmark at the foot.
class DailyVerseShareCanvas extends StatelessWidget {
  const DailyVerseShareCanvas({
    super.key,
    required this.background,
    required this.scene,
    this.photo,
    required this.text,
    required this.reference,
    required this.version,
    this.attribution,
  });

  final DailyVerseBackground background;
  final VerseScene scene;

  /// The full-size photo, when it could be fetched; else the bundled asset.
  final ImageProvider? photo;

  final String text;
  final String reference;
  final String version;
  final String? attribution;

  static const double _side = 28;

  /// The card's text shadow, see `_VerseFace`.
  static const _shadow = [
    Shadow(offset: Offset(0, 1), blurRadius: 3, color: Color(0x59000000)),
  ];

  @override
  Widget build(BuildContext context) {
    final label = version.isEmpty ? reference : '$reference $version';
    final notice = attribution;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (background == DailyVerseBackground.photo)
          DailyVersePhoto(dayKey: scene.key, image: photo)
        else
          DailyVerseBackgroundView(kind: background, scene: scene, still: true),
        const DailyVersePhotoScrim(),
        Padding(
          // Clear of the status viewer's progress bar and name at the top,
          // and of its reply field at the bottom.
          padding: const EdgeInsets.fromLTRB(_side, 76, _side, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TEKST VAN DE DAG',
                style: AppTheme.overline.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppTheme.bodyStrong.copyWith(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  shadows: _shadow,
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => Align(
                    alignment: Alignment.centerLeft,
                    child: _Verse(
                      text: text,
                      width: box.maxWidth,
                      height: box.maxHeight - 2 * _Verse.gap,
                    ),
                  ),
                ),
              ),
              if (notice != null) ...[
                Text(
                  notice,
                  style: TextStyle(
                    fontFamily: AppTheme.sansFontName,
                    fontSize: 11,
                    height: 1.3,
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              const _Wordmark(),
              const SizedBox(height: 44),
            ],
          ),
        ),
      ],
    );
  }
}

/// The verse in the card's serif, left aligned, at the card's full screen size
/// (21) when it fits and a step smaller until it does.
class _Verse extends StatelessWidget {
  const _Verse({required this.text, required this.width, required this.height});

  final String text;
  final double width;
  final double height;

  /// Clear space above and below the verse.
  static const double gap = 16;

  static const double _maxSize = 21;
  static const double _minSize = 13;
  static const double _lineHeight = 1.5;

  TextStyle _style(double size) => TextStyle(
    fontFamily: AppTheme.serifFontName,
    fontSize: size,
    height: _lineHeight,
    fontWeight: FontWeight.w500,
    color: Colors.white,
    shadows: DailyVerseShareCanvas._shadow,
  );

  double _measure(double size) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _style(size)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    final h = painter.height;
    painter.dispose();
    return h;
  }

  double _fittedSize() {
    for (var size = _maxSize; size > _minSize; size -= 0.5) {
      if (_measure(size) <= height) return size;
    }
    return _minSize;
  }

  @override
  Widget build(BuildContext context) {
    final size = _fittedSize();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: gap),
      // Past the smallest size a verse is cut off with an ellipsis rather
      // than pushing the notice and wordmark out.
      child: Text(
        text,
        textAlign: TextAlign.left,
        style: _style(size),
        overflow: TextOverflow.ellipsis,
        maxLines: (height / (size * _lineHeight)).floor().clamp(1, 60),
      ),
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
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            'bijbelstudie.io',
            style: AppTheme.bodyStrong.copyWith(
              fontSize: 13,
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
