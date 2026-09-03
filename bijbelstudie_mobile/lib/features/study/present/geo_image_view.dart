import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/context_repository.dart';

/// A Wikimedia photograph, asked for at a given pixel width.
///
/// Two things it cannot skip: the User-Agent - Wikimedia answers 403 without
/// one - and a fallback to the untouched original, so a resize that fails still
/// shows the photograph rather than a grey box. Every place in the app that
/// renders a [GeoImage] goes through here, because the naive
/// `Image.network(image.thumbnailUrl)` those places used to do does not load at
/// all; see [GeoImage.sizedUrl].
class GeoImageView extends StatelessWidget {
  const GeoImageView({
    super.key,
    required this.image,
    required this.width,
    this.fit = BoxFit.cover,
  });

  final GeoImage image;

  /// The width to fetch, in device pixels - so twice the drawn size on a
  /// retina screen.
  final int width;

  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      image.sizedUrl(width),
      fit: fit,
      headers: wikimediaImageHeaders,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return ColoredBox(color: AppTheme.paperSunken);
      },
      errorBuilder: (_, _, _) => Image.network(
        image.fileUrl,
        fit: fit,
        headers: wikimediaImageHeaders,
        errorBuilder: (_, _, _) => ColoredBox(
          color: AppTheme.paperSunken,
          child: Center(
            child: Icon(
              Icons.image_not_supported_outlined,
              size: 20,
              color: AppTheme.inkFaint,
            ),
          ),
        ),
      ),
    );
  }
}
