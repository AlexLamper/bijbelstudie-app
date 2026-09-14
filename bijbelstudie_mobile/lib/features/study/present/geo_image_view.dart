import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/skeleton.dart';
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
    AppTheme.dependOn(context);
    return Image.network(
      image.sizedUrl(width),
      fit: fit,
      headers: wikimediaImageHeaders,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        // Same box the photograph will land in, so nothing reflows.
        return LayoutBuilder(
          builder: (context, constraints) => Skeleton(
            width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
            height: constraints.hasBoundedHeight ? constraints.maxHeight : 120,
            radius: 0,
          ),
        );
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

/// Opens [_GeoImageLightbox] over [images] at [index]. Shared by the lesson's
/// place tiles and gallery cards and the study panel's photo strip - one
/// lightbox, however the thumbnails upstream are laid out.
void openGeoImageLightbox(BuildContext context, List<GeoImage> images, int index) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) =>
          _GeoImageLightbox(images: images, initialIndex: index),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// The photographs at full size: one per page, pinchable, with the caption and
/// the CC credit under them.
class _GeoImageLightbox extends StatefulWidget {
  const _GeoImageLightbox({required this.images, required this.initialIndex});

  final List<GeoImage> images;
  final int initialIndex;

  @override
  State<_GeoImageLightbox> createState() => _GeoImageLightboxState();
}

class _GeoImageLightboxState extends State<_GeoImageLightbox> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.images[_index];
    final width =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .clamp(320.0, 1280.0)
            .round();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Tapping the backdrop closes, as the website's lightbox does; the
          // photograph keeps its own gestures for panning and zooming.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    color: Colors.white,
                    tooltip: 'Sluiten',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: widget.images.length,
                    onPageChanged: (value) => setState(() => _index = value),
                    // The page fills the screen, so without this the letterbox
                    // beside the photograph would swallow the backdrop tap.
                    itemBuilder: (context, index) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(),
                      child: LayoutBuilder(
                        builder: (context, constraints) => Center(
                          // Loose constraints let the image size itself to its
                          // own aspect ratio, so the absorbing box is the
                          // photograph and not the letterbox around it.
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth,
                              maxHeight: constraints.maxHeight,
                            ),
                            child: GestureDetector(
                              // The photograph keeps its own gestures: this
                              // absorbs the tap so zooming and panning still
                              // work and tapping the image does not close.
                              onTap: () {},
                              child: InteractiveViewer(
                                minScale: 1,
                                maxScale: 4,
                                child: GeoImageView(
                                  image: widget.images[index],
                                  width: width,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        image.placeName,
                        style: AppTheme.bodyStrong.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      if (image.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          image.description!,
                          style: AppTheme.caption.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      // CC attribution has to be displayed, not merely recorded.
                      Text(
                        '${image.credit} · ${image.license}',
                        style: AppTheme.metaLabel.copyWith(
                          color: Colors.white54,
                        ),
                      ),
                      if (widget.images.length > 1) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${_index + 1} / ${widget.images.length}',
                          style: AppTheme.metaLabel.copyWith(
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
