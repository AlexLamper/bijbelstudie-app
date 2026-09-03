import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';
import 'skeleton.dart';

class ServerImage extends StatelessWidget {
  final String imagePath;
  final BoxFit fit;

  /// Painted instead of the default broken-image tile when the file is
  /// missing, undecodable, or the path resolves to nothing. Study cards pass
  /// their own banner so a failed request still reads as a card.
  final Widget? fallback;

  const ServerImage({
    super.key,
    required this.imagePath,
    this.fit = BoxFit.cover,
    this.fallback,
  });

  static final RegExp _httpUrlPattern = RegExp(
    r'^https?://',
    caseSensitive: false,
  );

  static final RegExp _fileExtensionPattern = RegExp(
    r'\.[a-z0-9]+$',
    caseSensitive: false,
  );

  /// Supports multiple backend formats:
  /// - /images/quizzes/img8.png
  /// - images/quizzes/img8.png
  /// - public/images/quizzes/img8.png
  /// - img8.png
  static String normalizePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') {
      return '';
    }

    if (_httpUrlPattern.hasMatch(trimmed)) {
      return trimmed;
    }

    final withForwardSlashes = trimmed.replaceAll(r'\', '/');
    final withoutPublicPrefix = withForwardSlashes.replaceFirst(
      RegExp(r'^/?public/'),
      '/',
    );

    String ensureQuizPngExtension(String path) {
      if (!path.toLowerCase().startsWith('/images/quizzes/')) {
        return path;
      }

      return _fileExtensionPattern.hasMatch(path) ? path : '$path.png';
    }

    if (withoutPublicPrefix.startsWith('/')) {
      return ensureQuizPngExtension(withoutPublicPrefix);
    }

    if (withoutPublicPrefix.startsWith('images/')) {
      return ensureQuizPngExtension('/$withoutPublicPrefix');
    }

    if (withoutPublicPrefix.contains('/')) {
      return ensureQuizPngExtension('/$withoutPublicPrefix');
    }

    // If only a file name is provided, default to the quizzes image folder.
    return ensureQuizPngExtension('/images/quizzes/$withoutPublicPrefix');
  }

  static String getFullUrl(String imagePath) {
    final String normalizedPath = normalizePath(imagePath);
    if (normalizedPath.isEmpty) return '';

    if (_httpUrlPattern.hasMatch(normalizedPath)) {
      return normalizedPath;
    }

    // Get the base host URL (without /api/mobile)
    final String host = AppConfig.baseUrl;

    // Combine them safely
    final fullUrl = '$host$normalizedPath';
    return fullUrl;
  }

  /// Whether the file behind [url] is a vector the raster codecs cannot read.
  ///
  /// The study banners `GET /api/v1/studies` hands out are hand-authored SVGs
  /// (`lib/data/curated-studies.ts` on the website), and `Image.network` has no
  /// SVG decoder - it fails every one of them and paints its error builder
  /// instead, which is why the study cards showed no image at all. The
  /// extension is read off the path so a query string cannot hide it.
  static bool isVector(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    return path.toLowerCase().endsWith('.svg');
  }

  String _buildFullUrl() {
    return getFullUrl(imagePath);
  }

  Widget _fallback() {
    return fallback ??
        Container(
          color: AppTheme.paperSunken,
          child: Icon(
            Icons.image_not_supported_outlined,
            color: AppTheme.inkMuted,
            size: 20,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final url = _buildFullUrl();
    if (url.isEmpty) return _fallback();

    if (isVector(url)) {
      return SvgPicture.network(
        url,
        fit: fit,
        placeholderBuilder: (_) => _loadingPlaceholder(),
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }

    return Image.network(
      url,
      fit: fit,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      // Same box as the finished image, so the card does not reflow once the
      // download completes - only its content changes.
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _loadingPlaceholder();
      },
      errorBuilder: (context, error, stackTrace) => _fallback(),
    );
  }

  /// Fills whatever box the image will occupy once it lands. [LayoutBuilder]
  /// reads that box from the constraints [Image.network]/[SvgPicture.network]
  /// are already laid out in, so the skeleton never has to guess a size and
  /// nothing shifts when the real picture replaces it.
  Widget _loadingPlaceholder() {
    return LayoutBuilder(
      builder: (context, constraints) => Skeleton(
        width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
        height: constraints.hasBoundedHeight ? constraints.maxHeight : 120,
        radius: 0,
      ),
    );
  }
}
