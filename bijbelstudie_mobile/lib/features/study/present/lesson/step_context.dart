import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../../core/ui/skeleton.dart';
import '../../data/context_repository.dart';
import '../../domain/lesson_models.dart';
import '../../domain/summary_format.dart';

/// The background screen: where this happened, and what the book is about.
///
/// A step of its own rather than two more panels on Verdieping. Both halves are
/// context rather than exposition - nice to have looked at, not something to
/// read *while* working through the uitleg - so they get their own stop on the
/// rail where there is room for a photograph to actually be a photograph.
///
/// The shell only puts this on the rail when there is something to show, so
/// neither half needs to justify an empty screen.
class LessonContextStep extends ConsumerWidget {
  const LessonContextStep({super.key, required this.lesson});

  final LessonPayload lesson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passage = lesson.passage;
    final images = ref.watch(geoImagesProvider(GeoRef(passage.book, passage.chapter)));
    final summary = ref.watch(bookSummaryProvider(passage.book));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const Eyebrow('Achtergrond'),
        const SizedBox(height: 6),
        Text('${passage.book} in beeld', style: AppTheme.displaySmall),
        const SizedBox(height: 16),

        images.when(
          loading: () => const SkeletonCard(height: 180, child: SkeletonText(lines: 2)),
          // Context is a bonus; a failure to fetch it says nothing worth
          // interrupting the lesson for.
          error: (_, _) => const SizedBox.shrink(),
          data: (list) {
            if (list.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final image in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PlaceCard(image: image),
                  ),
                if (list.any((image) => image.fromBook))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Deze plaatsen horen bij ${passage.book}, niet per se bij '
                      'dit hoofdstuk.',
                      style: AppTheme.caption,
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),

        summary.when(
          loading: () => const SkeletonText(lines: 5, lineHeight: 13, gap: 10),
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

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.image});

  final GeoImage image;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AppCard does not clip its tappable branch, and this card is not
          // tappable - but the rounding is applied here anyway so the image
          // cannot sit proud of the corners either way.
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusLg),
            ),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                image.url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return ColoredBox(color: AppTheme.paperSunken);
                },
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
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(image.placeName, style: AppTheme.bodyStrong),
                if (image.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    image.description!,
                    style: AppTheme.caption,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                // CC attribution has to be displayed, not merely recorded.
                Text(
                  '${image.credit} · ${image.license}',
                  style: AppTheme.metaLabel,
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
      SummaryParagraphKind.body => Text(paragraph.text, style: AppTheme.bodyLead),
    };
  }
}
