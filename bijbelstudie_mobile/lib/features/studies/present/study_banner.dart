import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/server_image.dart';
import '../data/study_models.dart';

/// The 16:6 banner on a study card and at the top of its detail screen.
///
/// `GET /api/v1/studies` hands out `image` as an absolute URL to a hand-authored
/// SVG under `/images/studies` (see `lib/data/curated-studies.ts`). Those went
/// through `Image.network`, which has no SVG decoder, so every banner failed and
/// the cards showed a flat tint instead of a picture. [ServerImage] now routes
/// vectors to flutter_svg; this widget adds the ground they are drawn on, so a
/// study with no image - or one whose request fails - still gets a banner with
/// its own character rather than an empty box.
class StudyBanner extends StatelessWidget {
  const StudyBanner({super.key, required this.study});

  final CuratedStudy study;

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
          colors: const [AppTheme.tealStrong, Color(0xFF0F172A)],
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

  @override
  Widget build(BuildContext context) {
    if (study.image.trim().isEmpty) return _painted();
    return ServerImage(imagePath: study.image, fallback: _painted());
  }
}
