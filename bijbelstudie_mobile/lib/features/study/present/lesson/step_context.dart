import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../../core/ui/skeleton.dart';
import '../../data/context_repository.dart';
import '../../domain/lesson_models.dart';
import '../../domain/summary_format.dart';
import '../geo_image_view.dart';

/// Bijbelse context: who wrote this book, where this chapter sits in it, the
/// words worth knowing, and the places it names.
///
/// Everything but the photographs comes from the server now
/// ([LessonContextContent]). The client used to fetch `/summary` itself and
/// repeat the same page of prose on every lesson of a fourteen-lesson study,
/// with no way to tell orientation for *this* chapter from a description of the
/// whole book. The server sends the section the chapter falls in instead, so
/// the step says something different each sitting.
///
/// The photographs stay a client fetch: they come from Wikimedia by place name,
/// not from the lesson payload.
class LessonContextStep extends ConsumerWidget {
  const LessonContextStep({super.key, required this.lesson});

  final LessonPayload lesson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final passage = lesson.passage;
    final content = lesson.content.context;

    // An older server sends the step with no block behind it, and a lesson
    // whose passage names no place asks for the photographs to be left off.
    final hasText = content?.hasText ?? false;
    final images = (content?.showMedia ?? true)
        ? ref.watch(geoImagesProvider(GeoRef(passage.book, passage.chapter)))
        : null;

    // The server names the book in Dutch; the passage's own name is the
    // fallback for a payload that carries no context block at all.
    final bookName = switch (content?.book?.name.trim()) {
      final String name when name.isNotEmpty => name,
      _ => passage.book,
    };

    final paragraphs = formatSummary(content?.body.join('\n\n'));
    final facts = content?.facts ?? const <LessonFact>[];
    final outline = content?.outline ?? const <LessonBookSection>[];
    final placement = content?.placement;
    final terms = content?.terms ?? const <LessonTerm>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const Eyebrow('Bijbelse context'),
        const SizedBox(height: 6),
        Text(bookName, style: AppTheme.displaySmall),
        const SizedBox(height: 16),

        if (images != null)
          images.when(
            loading: () =>
                const SkeletonCard(height: 126, child: SkeletonText(lines: 2)),
            // Context is a bonus; a failure to fetch it says nothing worth
            // interrupting the lesson for.
            error: (_, _) => const SizedBox.shrink(),
            data: (list) {
              if (list.isEmpty) return const SizedBox.shrink();
              // The strip is sized for a row above the prose. With no prose to
              // sit above, a row of small tiles would leave the screen empty,
              // so the photographs become the point instead.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  hasText
                      ? _PlaceStrip(images: list)
                      : _PlaceGallery(images: list),
                  SizedBox(height: hasText ? 8 : 14),
                  Text(
                    list.any((image) => image.fromBook)
                        ? 'Deze plaatsen horen bij ${passage.book}, niet per se bij '
                              'dit hoofdstuk. Tik op een foto voor een grote weergave.'
                        : 'Tik op een foto voor een grote weergave.',
                    style: AppTheme.caption,
                  ),
                  SizedBox(height: hasText ? 20 : 4),
                ],
              );
            },
          ),

        for (final paragraph in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SummaryText(paragraph: paragraph),
          ),

        if (facts.isNotEmpty) ...[
          const SizedBox(height: 10),
          _FactList(facts: facts),
        ],

        if (placement != null || outline.isNotEmpty) ...[
          const SizedBox(height: 22),
          SectionHeader(
            eyebrow: 'Waar je bent',
            title: 'Dit gedeelte in $bookName',
          ),
          const SizedBox(height: 10),
          if (outline.isEmpty)
            _SectionRow(section: placement!, current: true)
          else
            for (final section in outline)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SectionRow(
                  section: section,
                  current: section.current,
                  // Only the section the reader is in gets its summary; the
                  // rest are there to show the shape of the book.
                  summary: section.current ? placement?.summary : null,
                ),
              ),
        ],

        if (terms.isNotEmpty) ...[
          const SizedBox(height: 22),
          const SectionHeader(eyebrow: 'Woorden', title: 'Goed om te weten'),
          const SizedBox(height: 10),
          for (final term in terms)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(term.term, style: AppTheme.bodyStrong),
                  const SizedBox(height: 2),
                  Text(term.meaning, style: AppTheme.bodyMuted),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// Schrijver, Geschreven, Soort boek, Kern - as rows rather than as a
/// paragraph, because they are looked up rather than read.
class _FactList extends StatelessWidget {
  const _FactList({required this.facts});

  final List<LessonFact> facts;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final fact in facts) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(fact.label, style: AppTheme.metaLabel),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(fact.value, style: AppTheme.bodyMuted)),
              ],
            ),
            if (fact != facts.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

/// One stretch of the book's outline. The section the reader is in carries the
/// brand tint, so "waar je bent" is answered by looking rather than by reading.
class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.section,
    required this.current,
    this.summary,
  });

  final LessonBookSection section;
  final bool current;
  final String? summary;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final text = summary ?? (current ? section.summary : null);
    return AppCard(
      color: current ? AppTheme.tealTint : null,
      borderColor: current ? AppTheme.teal : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 52,
                child: Text(
                  section.range,
                  style: AppTheme.metaLabel.copyWith(
                    color: current ? AppTheme.tealStrong : AppTheme.inkFaint,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.title,
                  style: current
                      ? AppTheme.bodyStrong.copyWith(color: AppTheme.tealStrong)
                      : AppTheme.bodyMuted,
                ),
              ),
            ],
          ),
          if (text != null && text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(text, style: AppTheme.caption),
          ],
        ],
      ),
    );
  }
}

/// The photographs, as a row of small tiles rather than a stack of full-width
/// cards.
///
/// A 16:9 card per place turned three photographs into three screens of
/// scrolling before the prose - the part of this step actually worth reading -
/// came into view at all. Tiles put several places side by side, keep the text
/// near the top, and the photograph at full size is one tap away in
/// [openGeoImageLightbox], where it can be looked at properly.
class _PlaceStrip extends StatelessWidget {
  const _PlaceStrip({required this.images});

  final List<GeoImage> images;

  static const double _tile = 104;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
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
                    onTap: () => openGeoImageLightbox(context, images, index),
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
}

/// The photographs for a context step with no text on it: a strip
/// of small tiles would leave the rest of the screen empty, so the
/// photographs become the point instead - one hero card, or a hero plus a
/// mosaic of the rest, edge to edge within the page's own margins.
///
/// Layout depends only on the count: a single photograph gets one large
/// card; two stack full-width so both get the same weight; three or more put
/// the first photograph on top as the hero and tile the remainder two per
/// row underneath.
class _PlaceGallery extends StatelessWidget {
  const _PlaceGallery({required this.images});

  final List<GeoImage> images;

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    switch (images.length) {
      case 1:
        return _GalleryTile(images: images, index: 0, aspectRatio: 4 / 3);

      case 2:
        return Column(
          children: [
            _GalleryTile(images: images, index: 0, aspectRatio: 16 / 10),
            const SizedBox(height: _gap),
            _GalleryTile(images: images, index: 1, aspectRatio: 16 / 10),
          ],
        );

      default:
        // Three or more: the first photograph is the hero, the rest tile two
        // per row beneath it.
        final rest = images.length - 1;
        return Column(
          children: [
            _GalleryTile(images: images, index: 0, aspectRatio: 16 / 9),
            const SizedBox(height: _gap),
            for (var row = 0; row * 2 < rest; row++)
              Padding(
                padding: EdgeInsets.only(top: row == 0 ? 0 : _gap),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _GalleryTile(
                        images: images,
                        index: 1 + row * 2,
                        aspectRatio: 1,
                      ),
                    ),
                    if (row * 2 + 1 < rest) ...[
                      const SizedBox(width: _gap),
                      Expanded(
                        child: _GalleryTile(
                          images: images,
                          index: 2 + row * 2,
                          aspectRatio: 1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
    }
  }
}

/// One card in [_PlaceGallery]: a rounded, near-full-width photograph at a
/// fixed aspect ratio - so a portrait or panoramic source is cropped with
/// [BoxFit.cover] rather than stretched - with its place name underneath and
/// the same tap-to-zoom as [_PlaceStrip]'s tiles.
class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.images,
    required this.index,
    required this.aspectRatio,
  });

  final List<GeoImage> images;
  final int index;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final image = images[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: 'Foto van ${image.placeName}, vergroten',
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            onTap: () => openGeoImageLightbox(context, images, index),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: LayoutBuilder(
                  builder: (context, constraints) => GeoImageView(
                    image: image,
                    // Asked for at 2x the drawn width so the photograph
                    // stays sharp on a retina screen at whatever size this
                    // card lands at - a hero and a mosaic tile differ a lot.
                    width: constraints.hasBoundedWidth
                        ? (constraints.maxWidth * 2).round()
                        : 1200,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          image.placeName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.metaLabel,
        ),
      ],
    );
  }
}

class _SummaryText extends StatelessWidget {
  const _SummaryText({required this.paragraph});

  final SummaryParagraph paragraph;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
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
