import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/server_image.dart';
import '../data/study_models.dart';
import '../data/study_photos.dart';

/// A study's picture: the 16:6 banner on a study card, the square thumbnail in
/// a list row, and the header of its detail screen.
///
/// First choice is the study's bundled photograph from [studyPhotoFor], the
/// same one the website shows (`lib/studyPhotos.ts`, `app/studies/StudyArtwork.tsx`).
/// Like the website, a box no wider than 1.5:1 gets the 240 px square crop and
/// anything wider gets the 800 px banner file.
///
/// A study without a photo (one added on the server after this build) falls
/// back to whatever `image` the API hands out, through [ServerImage], and then
/// to the painted teal ground - so a card never shows an empty or broken box.
/// The painted ground also stands in while a photo decodes.
class StudyBanner extends StatelessWidget {
  const StudyBanner({super.key, required this.study});

  final CuratedStudy study;

  /// The website's wash over a photo (`StudyArtwork.tsx`): slate 900, a
  /// little darker along the top and bottom edges where badges and pills sit,
  /// clear through the middle so the picture itself is not dimmed.
  static const LinearGradient photoScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x380F172A), // 22%
      Color(0x000F172A),
      Color(0x000F172A),
      Color(0x2E0F172A), // 18%
    ],
    stops: [0, 0.38, 0.62, 1],
  );

  /// A stable per-study tilt so the fallback banners in a list do not all look
  /// like the same rectangle. Derived from the id, never random, or it would
  /// change on every rebuild.
  static Alignment _gradientEnd(String id) {
    final hash = id.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    return switch (hash % 3) {
      0 => Alignment.bottomRight,
      1 => Alignment.bottomLeft,
      _ => Alignment.bottomCenter,
    };
  }

  static IconData _iconFor(String type) => switch (type) {
    'Persoon' => Icons.person_outline,
    'Gedeelte' => Icons.format_quote_outlined,
    'Boek' => Icons.menu_book_outlined,
    _ => Icons.lightbulb_outline,
  };

  Widget _painted() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: _gradientEnd(study.id),
          colors: [AppTheme.tealStrong, AppTheme.bannerEnd],
        ),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 18),
          child: Icon(
            _iconFor(study.type),
            size: 40,
            color: Colors.white.withValues(alpha: 0.22),
          ),
        ),
      ),
    );
  }

  /// The server image, or the painted ground when there is none.
  Widget _withoutPhoto() {
    if (study.image.trim().isEmpty) return _painted();
    return ServerImage(imagePath: study.image, fallback: _painted());
  }

  /// The same rule as the website: a square-ish box is a list thumbnail.
  static bool useThumb(BoxConstraints constraints) {
    if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
      return false;
    }
    if (constraints.maxHeight <= 0) return false;
    return constraints.maxWidth / constraints.maxHeight <= 1.5;
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final photo = studyPhotoFor(study.id);
    if (photo == null) return _withoutPhoto();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Image.asset(
          useThumb(constraints) ? photo.thumb : photo.banner,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame == null && !wasSynchronouslyLoaded) return _painted();
            return Stack(
              fit: StackFit.expand,
              children: [
                child,
                const DecoratedBox(
                  decoration: BoxDecoration(gradient: photoScrim),
                ),
              ],
            );
          },
          errorBuilder: (context, error, stackTrace) => _withoutPhoto(),
        );
      },
    );
  }
}
