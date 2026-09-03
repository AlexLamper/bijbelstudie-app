import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../../core/ui/skeleton.dart';
import '../../data/context_repository.dart';
import '../../domain/lesson_models.dart';
import '../../domain/summary_format.dart';
import '../geo_image_view.dart';

/// Whether this lesson's background screen carries the book's introduction.
///
/// Only the first one does. The introduction is a property of the *book*, not
/// of the lesson, so `GET /summary` answers every lesson in a study with the
/// same text - and a fourteen-lesson study showed the reader that same page of
/// prose fourteen times, under a heading promising background. Reading it once
/// is the point; re-reading it on every sitting is noise.
///
/// The photographs are not treated this way on purpose: they are a different
/// set per chapter, so they stay useful for the whole study.
///
/// [LessonScreen] applies the same rule when it decides whether the background
/// screen has anything on it at all, so a later lesson with no photographs
/// simply has no background step rather than an empty one.
bool lessonShowsBookSummary(int day) => day <= 1;

/// The background screen: where this happened, and what the book is about.
///
/// A step of its own rather than two more panels on Verdieping. Both halves are
/// context rather than exposition - what you want in hand *before* the uitleg,
/// not something to read while working through it - so they get their own stop
/// on the rail, ahead of Verdieping.
///
/// The shell only puts this on the rail when there is something to show, so
/// neither half needs to justify an empty screen.
class LessonContextStep extends ConsumerWidget {
  const LessonContextStep({super.key, required this.lesson});

  final LessonPayload lesson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passage = lesson.passage;
    final images = ref.watch(
      geoImagesProvider(GeoRef(passage.book, passage.chapter)),
    );
    final summary = ref.watch(bookSummaryProvider(passage.book));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const Eyebrow('Achtergrond'),
        const SizedBox(height: 6),
        Text('${passage.book} in beeld', style: AppTheme.displaySmall),
        const SizedBox(height: 16),

        images.when(
          loading: () =>
              const SkeletonCard(height: 126, child: SkeletonText(lines: 2)),
          // Context is a bonus; a failure to fetch it says nothing worth
          // interrupting the lesson for.
          error: (_, _) => const SizedBox.shrink(),
          data: (list) {
            if (list.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PlaceStrip(images: list),
                const SizedBox(height: 8),
                Text(
                  list.any((image) => image.fromBook)
                      ? 'Deze plaatsen horen bij ${passage.book}, niet per se bij '
                            'dit hoofdstuk. Tik op een foto voor een grote weergave.'
                      : 'Tik op een foto voor een grote weergave.',
                  style: AppTheme.caption,
                ),
                const SizedBox(height: 20),
              ],
            );
          },
        ),

        if (!lessonShowsBookSummary(lesson.day))
          const SizedBox.shrink()
        else
          summary.when(
            loading: () =>
                const SkeletonText(lines: 5, lineHeight: 13, gap: 10),
            error: (_, _) => const SizedBox.shrink(),
            data: (text) {
              final paragraphs = formatSummary(text);
              if (paragraphs.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    eyebrow: 'Algemene informatie',
                    title: 'Over ${passage.book}',
                  ),
                  const SizedBox(height: 10),
                  for (final paragraph in paragraphs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SummaryText(paragraph: paragraph),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// The photographs, as a row of small tiles rather than a stack of full-width
/// cards.
///
/// A 16:9 card per place turned three photographs into three screens of
/// scrolling before the book's introduction - the part of this step actually
/// worth reading - came into view at all. Tiles put several places side by
/// side, keep the introduction near the top, and the photograph at full size is
/// one tap away in [_PlaceLightbox], where it can be looked at properly.
class _PlaceStrip extends StatelessWidget {
  const _PlaceStrip({required this.images});

  final List<GeoImage> images;

  static const double _tile = 104;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _tile + 22,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final image = images[index];
          return SizedBox(
            width: _tile,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  button: true,
                  label: 'Foto van ${image.placeName}, vergroten',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    onTap: () => _openLightbox(context, index),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      child: SizedBox(
                        width: _tile,
                        height: _tile,
                        // Asked for at 2x the drawn size so the tile stays
                        // sharp on a retina screen without pulling the 5000px
                        // original for a 104pt box.
                        child: GeoImageView(
                          image: image,
                          width: (_tile * 2).round(),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  image.placeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.metaLabel,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openLightbox(BuildContext context, int index) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) =>
            _PlaceLightbox(images: images, initialIndex: index),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}

/// The photographs at full size: one per page, pinchable, with the caption and
/// the CC credit under them.
class _PlaceLightbox extends StatefulWidget {
  const _PlaceLightbox({required this.images, required this.initialIndex});

  final List<GeoImage> images;
  final int initialIndex;

  @override
  State<_PlaceLightbox> createState() => _PlaceLightboxState();
}

class _PlaceLightboxState extends State<_PlaceLightbox> {
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
                    itemBuilder: (context, index) => InteractiveViewer(
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

class _SummaryText extends StatelessWidget {
  const _SummaryText({required this.paragraph});

  final SummaryParagraph paragraph;

  @override
  Widget build(BuildContext context) {
    return switch (paragraph.kind) {
      SummaryParagraphKind.heading => Text(
        paragraph.text,
        style: AppTheme.eyebrow.copyWith(color: AppTheme.tealStrong),
      ),
      SummaryParagraphKind.numbered => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, size: 5, color: AppTheme.teal),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(paragraph.text, style: AppTheme.bodyMuted)),
        ],
      ),
      SummaryParagraphKind.body => Text(
        paragraph.text,
        style: AppTheme.bodyLead,
      ),
    };
  }
}
