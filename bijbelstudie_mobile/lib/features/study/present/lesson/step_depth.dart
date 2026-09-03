import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../bible/present/bible_providers.dart';
import '../../../commentary/present/commentary_pane.dart';
import '../../../settings/data/reading_settings.dart';
import '../../domain/lesson_models.dart';

/// Step 3 - the uitleg, and the words behind it.
///
/// Two panes and nothing else. This step used to carry the commentary, a
/// three-way panel switcher over images, grondtekst and notes, *and* the
/// assistant, all on one scroll - a direct port of the website's two-column
/// layout that on a phone became a page nobody could find anything on. The
/// images and the book's background now have a screen of their own, notes are
/// reachable from the reader where they are written, and the assistant lives
/// behind the icon in the top bar so it is available on every step instead of
/// taking up room on this one.
///
/// The payload's `commentaryId` - resolved server-side from the enrollment,
/// then the account preference, then the default - is only the starting point.
/// Once the reader picks a source in the pane it is their choice, not the
/// payload's, for the rest of the lesson; the lesson screen holds that pick so
/// it survives stepping away from Verdieping and back.
class LessonDepthStep extends ConsumerWidget {
  const LessonDepthStep({
    super.key,
    required this.lesson,
    required this.panel,
    required this.translation,
    required this.commentaryId,
    required this.onPanelChanged,
    required this.onCommentaryChanged,
  });

  final LessonPayload lesson;

  final String commentaryId;

  /// `original` for the grondtekst; anything else reads as the uitleg, which
  /// keeps the older stored values (`media`, `notes`) harmless.
  final String panel;

  final String translation;
  final ValueChanged<String> onPanelChanged;
  final ValueChanged<String> onCommentaryChanged;

  static const _commentary = 'commentary';
  static const _original = 'original';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passage = lesson.passage;
    final settings = ref.watch(readingSettingsProvider);
    final showOriginal = panel == _original;

    final location = ReaderLocation(
      versionId: translation,
      book: passage.book,
      chapter: passage.chapter,
      restored: true,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('Verdieping'),
              const SizedBox(height: 6),
              Text(
                'Uitleg bij ${passage.reference}',
                style: AppTheme.displaySmall,
              ),
              const SizedBox(height: 14),
              _PaneTabs(
                active: showOriginal ? _original : _commentary,
                onChanged: onPanelChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Each pane scrolls on its own and fills the step, rather than being a
        // fixed-height box inside a longer page.
        Expanded(
          child: showOriginal
              ? OriginalTextPane(location: location)
              : CommentaryPane(
                  location: location,
                  settings: settings.copyWith(lastCommentaryId: commentaryId),
                  onSourceSelected: onCommentaryChanged,
                ),
        ),
      ],
    );
  }
}

class _PaneTabs extends StatelessWidget {
  const _PaneTabs({required this.active, required this.onChanged});

  final String active;
  final ValueChanged<String> onChanged;

  static const _panes = <(String, String, IconData)>[
    (LessonDepthStep._commentary, 'Uitleg', Icons.chat_bubble_outline),
    (LessonDepthStep._original, 'Grondtekst', Icons.translate),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final pane in _panes) ...[
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              onTap: () => onChanged(pane.$1),
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: pane.$1 == active
                      ? AppTheme.tealTint
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(
                    color: pane.$1 == active ? AppTheme.teal : AppTheme.rule,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      pane.$3,
                      size: 14,
                      color: pane.$1 == active
                          ? AppTheme.tealStrong
                          : AppTheme.inkMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      pane.$2,
                      style: AppTheme.caption.copyWith(
                        color: pane.$1 == active
                            ? AppTheme.tealStrong
                            : AppTheme.inkSoft,
                        fontWeight: pane.$1 == active
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (pane != _panes.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}
