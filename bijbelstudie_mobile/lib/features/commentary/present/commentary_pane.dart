import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../bible/domain/bible_models.dart';
import '../../bible/present/bible_providers.dart';
import '../../settings/data/reading_settings.dart';
import 'commentary_html.dart';

/// The Commentaar tab of the study page, locked to whatever the reader shows.
///
/// Its source picker is the site's commentary `<select>`; the choice is
/// persisted so reopening the app keeps the same commentator.
class CommentaryPane extends ConsumerWidget {
  const CommentaryPane({
    super.key,
    required this.location,
    required this.settings,
  });

  final ReaderLocation location;
  final ReadingSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commentaryId = settings.lastCommentaryId;
    final chapterAsync = ref.watch(
      commentaryChapterProvider(
        ChapterRef(commentaryId, location.book, location.chapter),
      ),
    );
    final sources = ref.watch(commentarySourcesProvider).value ?? const <BibleSource>[];

    return Column(
      children: [
        if (sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DropdownButtonFormField<String>(
              value: sources.any((s) => s.id == commentaryId)
                  ? commentaryId
                  : sources.first.id,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: [
                for (final source in sources)
                  DropdownMenuItem(value: source.id, child: Text(source.name)),
              ],
              onChanged: (value) {
                if (value == null) return;
                ref.read(readingSettingsProvider.notifier).setLastCommentary(value);
              },
            ),
          ),
        Expanded(
          child: chapterAsync.when(
            loading: () => const AppLoader(),
            error: (error, _) => AppEmptyState(
              icon: error is ContentNotLicensedException
                  ? Icons.gavel_outlined
                  : Icons.menu_book_outlined,
              title: error is ContentNotLicensedException
                  ? 'Niet beschikbaar in de app'
                  : 'Geen commentaar gevonden',
              description: error is ContentNotLicensedException
                  ? 'Dit commentaar mag alleen op de website worden aangeboden.'
                  : 'Voor dit hoofdstuk is geen commentaar beschikbaar in deze bron.',
            ),
            data: (chapter) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
              children: [
                for (final entry in chapter.verses)
                  _CommentaryEntry(entry: entry, settings: settings),
                if (chapter.locked) const _CommentaryPaywall(),
                const SizedBox(height: 20),
                const RuleLine(),
                const SizedBox(height: 12),
                Text(
                  chapter.attribution,
                  style: AppTheme.bodyMuted.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CommentaryEntry extends StatelessWidget {
  const _CommentaryEntry({required this.entry, required this.settings});

  final Verse entry;
  final ReadingSettings settings;

  @override
  Widget build(BuildContext context) {
    // Matthew Henry keys the chapter introduction as verse 0 — confirmed
    // against the live API. Labelling it "Vers 0" would be nonsense.
    final label = entry.number == 0 ? 'Inleiding' : 'Vers ${entry.number}';
    final body = commentaryToPlainText(entry.text);
    if (body.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(label),
          const SizedBox(height: 8),
          SelectableText(
            body,
            style: TextStyle(
              fontFamily: settings.fontFamily.fontName,
              fontSize: settings.fontSize.points * 0.92,
              height: settings.lineHeight.factor,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ],
      ),
    );
  }
}

/// The Grondtekst tab: the STEPBible Hebrew/Greek, word by word.
///
/// The CC BY 4.0 attribution at the foot is a licence condition, not a
/// footnote, so it renders even when the word list is short.
class OriginalTextPane extends ConsumerWidget {
  const OriginalTextPane({super.key, required this.location});

  final ReaderLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final originalAsync = ref.watch(
      originalChapterProvider(
        ChapterRef('stepbible', location.book, location.chapter),
      ),
    );

    return originalAsync.when(
      loading: () => const AppLoader(),
      error: (_, __) => const AppEmptyState(
        icon: Icons.translate_outlined,
        title: 'Geen grondtekst',
        description:
            'De Hebreeuwse/Griekse tekst is voor dit hoofdstuk niet beschikbaar.',
      ),
      data: (original) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
        children: [
          for (final verse in original.verses) _OriginalVerseBlock(verse: verse),
          const SizedBox(height: 20),
          const RuleLine(),
          const SizedBox(height: 12),
          Text(original.attribution, style: AppTheme.bodyMuted.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}

class _OriginalVerseBlock extends StatelessWidget {
  const _OriginalVerseBlock({required this.verse});

  final OriginalVerse verse;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('Vers ${verse.number}'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final word in verse.words)
                Semantics(
                  label: '${word.transliteration}, ${word.gloss}, Strong ${word.strongs}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        word.original,
                        style: const TextStyle(fontSize: 20, height: 1.4),
                        textDirection: TextDirection.rtl,
                      ),
                      Text(
                        word.transliteration,
                        style: AppTheme.bodyMuted.copyWith(fontSize: 11),
                      ),
                      if (word.gloss.isNotEmpty)
                        Text(word.gloss, style: AppTheme.caption.copyWith(fontSize: 11)),
                      if (word.strongs.isNotEmpty)
                        Text(
                          word.strongs,
                          style: AppTheme.bodyMuted.copyWith(fontSize: 10),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}


/// Shown under the preview when the server withheld the rest of the chapter.
///
/// The entries above are real commentary, not a teaser: the free allowance is
/// the opening of the chapter, so the reader can see what they would be buying
/// before being asked to buy it.
class _CommentaryPaywall extends ConsumerStatefulWidget {
  const _CommentaryPaywall();

  @override
  ConsumerState<_CommentaryPaywall> createState() => _CommentaryPaywallState();
}

class _CommentaryPaywallState extends ConsumerState<_CommentaryPaywall> {
  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).track(AnalyticsEvents.paywallHit, {
      'surface': 'commentary',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppEmptyState(
        icon: Icons.workspace_premium_outlined,
        title: 'Lees het hele commentaar met Pro',
        description:
            'Je ziet het begin van dit hoofdstuk. Met Pro lees je Matthew '
            'Henry en Dachsel volledig, bij elk hoofdstuk.',
        action: SiteButton(
          label: 'Bekijk Pro',
          expand: false,
          onPressed: () {
            ref.read(analyticsProvider).track(AnalyticsEvents.paywallCtaClicked, {
              'surface': 'commentary',
            });
            context.push('/premium?source=app_study');
          },
        ),
      ),
    );
  }
}
