import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../ai/present/ai_assistant_pane.dart';
import '../../../bible/present/bible_providers.dart';
import '../../../commentary/present/commentary_pane.dart';
import '../../../settings/data/reading_settings.dart';
import '../../data/context_repository.dart';
import '../../domain/lesson_models.dart';

/// Step 3 - the commentary, plus the panels that put the passage in its world.
///
/// The commentary source is whatever the payload's `commentaryId` says: the
/// server resolves it from the enrollment, then the account preference, then
/// the default. Picking one here would quietly override the reader's choice.
///
/// The panels reuse the reader's own panes, so commentary, grondtekst, notes
/// and the assistant behave identically inside a lesson and outside it.
class LessonDepthStep extends ConsumerWidget {
  const LessonDepthStep({
    super.key,
    required this.lesson,
    required this.panel,
    required this.translation,
    required this.onPanelChanged,
  });

  final LessonPayload lesson;

  /// `media`, `original` or `notes`.
  final String panel;

  final String translation;
  final ValueChanged<String> onPanelChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passage = lesson.passage;
    final settings = ref.watch(readingSettingsProvider);

    final location = ReaderLocation(
      versionId: translation,
      book: passage.book,
      chapter: passage.chapter,
      restored: true,
    );

    // A passage with no place named has nothing to show under Beeld, so the
    // tab is dropped rather than opening onto an empty strip.
    final showMedia = lesson.content.depth?.showMedia ?? true;
    final panels = <_DepthPanel>[
      if (showMedia) const _DepthPanel('media', 'Beeld', Icons.image_outlined),
      const _DepthPanel('original', 'Grondtekst', Icons.translate),
      const _DepthPanel('notes', 'Notities', Icons.edit_note_outlined),
    ];
    final active = panels.any((p) => p.id == panel) ? panel : panels.first.id;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const Eyebrow('Verdieping'),
        const SizedBox(height: 8),
        Text('Uitleg bij ${passage.reference}', style: AppTheme.displaySmall),
        const SizedBox(height: 16),

        // The commentary itself, in the source the server chose.
        SizedBox(
          height: 360,
          child: AppCard(
            padding: EdgeInsets.zero,
            clip: true,
            child: CommentaryPane(
              location: location,
              settings: settings.copyWith(lastCommentaryId: lesson.commentaryId),
            ),
          ),
        ),

        if (lesson.content.depth?.terms.isNotEmpty ?? false) ...[
          const SizedBox(height: 18),
          const SectionHeader(eyebrow: 'Woorden', title: 'Begrippen'),
          const SizedBox(height: 10),
          AppCard(
            child: Column(
              children: [
                for (final term in lesson.content.depth!.terms)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(term.term, style: AppTheme.bodyStrong),
                        Text(term.meaning, style: AppTheme.bodyMuted),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),
        _PanelTabs(
          panels: panels,
          active: active,
          onChanged: onPanelChanged,
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 340,
          child: switch (active) {
            'original' => AppCard(
              padding: EdgeInsets.zero,
              clip: true,
              child: OriginalTextPane(location: location),
            ),
            'notes' => _NotesPanel(passage: passage),
            _ => _MediaPanel(passage: passage),
          },
        ),

        const SizedBox(height: 20),
        const SectionHeader(
          eyebrow: 'Vraag het na',
          title: 'AI-assistent',
          description: 'Stelt alleen vragen over dit bijbelgedeelte.',
        ),
        const SizedBox(height: 10),
        const SizedBox(height: 420, child: AiAssistantPane()),
      ],
    );
  }
}

class _DepthPanel {
  const _DepthPanel(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

class _PanelTabs extends StatelessWidget {
  const _PanelTabs({
    required this.panels,
    required this.active,
    required this.onChanged,
  });

  final List<_DepthPanel> panels;
  final String active;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final panel in panels) ...[
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              onTap: () => onChanged(panel.id),
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: panel.id == active ? AppTheme.tealTint : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(
                    color: panel.id == active ? AppTheme.teal : AppTheme.rule,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      panel.icon,
                      size: 14,
                      color: panel.id == active ? AppTheme.tealStrong : AppTheme.inkMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      panel.label,
                      style: AppTheme.caption.copyWith(
                        color: panel.id == active
                            ? AppTheme.tealStrong
                            : AppTheme.inkSoft,
                        fontWeight: panel.id == active
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (panel != panels.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

/// Photographs of the places the passage names.
class _MediaPanel extends ConsumerWidget {
  const _MediaPanel({required this.passage});

  final LessonPassage passage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final images = ref.watch(geoImagesProvider(GeoRef(passage.book, passage.chapter)));

    return images.when(
      loading: () => const Center(child: AppLoader()),
      error: (_, _) => const AppEmptyState(
        icon: Icons.image_not_supported_outlined,
        title: 'Geen beeld',
        description: 'De afbeeldingen konden niet worden geladen.',
      ),
      data: (list) {
        if (list.isEmpty) {
          return const AppEmptyState(
            icon: Icons.image_not_supported_outlined,
            title: 'Geen plaats of kaart',
            description: 'Bij dit gedeelte hoort geen plaats of kaart.',
          );
        }
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final image = list[index];
            return AppCard(
              padding: EdgeInsets.zero,
              clip: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      image.url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: AppTheme.teal.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(image.placeName, style: AppTheme.bodyStrong),
                        const SizedBox(height: 2),
                        // CC attribution has to be shown, not just recorded.
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
          },
        );
      },
    );
  }
}

/// The reader's own notes on this chapter.
class _NotesPanel extends ConsumerWidget {
  const _NotesPanel({required this.passage});

  final LessonPassage passage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(bookSummaryProvider(passage.book));

    // Notes for a chapter are reachable from the reader; inside a lesson the
    // useful thing is the book's own introduction, which sets up the passage.
    return summary.when(
      loading: () => const Center(child: AppLoader()),
      error: (_, _) => const AppEmptyState(
        icon: Icons.info_outline,
        title: 'Geen achtergrond',
        description: 'De achtergrond bij dit boek kon niet worden geladen.',
      ),
      data: (text) {
        if (text == null || text.isEmpty) {
          return const AppEmptyState(
            icon: Icons.info_outline,
            title: 'Geen achtergrond',
            description: 'Bij dit boek is nog geen achtergrond geschreven.',
          );
        }
        return ListView(
          children: [
            Text('Achtergrond bij ${passage.book}', style: AppTheme.bodyStrong),
            const SizedBox(height: 10),
            Text(text, style: AppTheme.bodyLead),
          ],
        );
      },
    );
  }
}
