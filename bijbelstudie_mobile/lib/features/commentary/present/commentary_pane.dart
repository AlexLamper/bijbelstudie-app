import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../bible/domain/bible_models.dart';
import '../../bible/present/bible_providers.dart';
import '../../premium/present/upgrade_prompt.dart';
import '../../settings/data/reading_settings.dart';
import 'commentary_body.dart';

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
                // Mirrors CommentaryComponent.tsx lines ~503-508: the server
                // already withholds everything past the free excerpt, so this
                // mask is cosmetic - it makes the truncation read as "the text
                // trails off" rather than "the text stops dead".
                if (chapter.locked)
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black, Colors.black, Colors.transparent],
                      stops: [0.0, 0.82, 1.0],
                    ).createShader(bounds),
                    blendMode: BlendMode.dstIn,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (index, entry) in chapter.verses.indexed)
                          _CommentaryEntry(
                            entry: entry,
                            settings: settings,
                            isLast: index == chapter.verses.length - 1,
                          ),
                      ],
                    ),
                  )
                else
                  for (final (index, entry) in chapter.verses.indexed)
                    _CommentaryEntry(
                      entry: entry,
                      settings: settings,
                      isLast: index == chapter.verses.length - 1,
                    ),
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
  const _CommentaryEntry({
    required this.entry,
    required this.settings,
    required this.isLast,
  });

  final Verse entry;
  final ReadingSettings settings;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    // Matthew Henry keys the chapter introduction as verse 0 - confirmed
    // against the live API. Labelling it "Vers 0" would be nonsense.
    final label = entry.number == 0 ? 'Inleiding' : 'Vers ${entry.number}';
    if (entry.text.trim().isEmpty) return const SizedBox.shrink();

    // `border-b border-gray-100 ... pb-6 last:border-0 mb-6 last:mb-0` on the
    // entry wrapper in `CommentaryComponent.tsx` (around line 519).
    return Container(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
      margin: EdgeInsets.only(bottom: isLast ? 0 : 20),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _VerseLabel(label),
          const SizedBox(height: 6),
          CommentaryBody(text: entry.text, settings: settings),
        ],
      ),
    );
  }
}

/// The `Inleiding` / `Vers N` pill.
///
/// Mirrors the label span in `CommentaryComponent.tsx` (around lines 517-524):
/// `text-[11px] font-semibold tracking-wider uppercase`, teal on an eight
/// percent teal wash, `rounded-full`. The website only pills the HTML sources
/// and gives the plain-text ones a bare heading; the app pills both, because
/// the plain-text source is Matthew Henry - the one the reader spends nearly
/// all of their time in, and the one that most needs its entries to look like
/// entries rather than like one unbroken column of prose.
class _VerseLabel extends StatelessWidget {
  const _VerseLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.teal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTheme.eyebrow.copyWith(fontSize: 11, color: AppTheme.teal),
      ),
    );
  }
}

/// The Grondtekst tab: the STEPBible Hebrew/Greek, word by word.
///
/// The server already truncates this chapter to the free allowance and
/// reports `locked` when it did (see `gateOriginal` in `lib/proContent.ts`),
/// so the pane never gates on the client - it renders whatever verses arrived
/// and, when locked, fades the tail and shows the upgrade prompt beneath it.
/// Mirrors how [CommentaryPane] above handles its own `locked` flag.
///
/// The CC BY 4.0 attribution at the foot is a licence condition, not a
/// footnote, so it renders even when the word list is short, including in
/// the free preview.
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
          // Mirrors CommentaryPane above: the server already withholds
          // everything past the free preview, so this mask is cosmetic - it
          // makes the truncation read as "the text trails off" rather than
          // "the text stops dead".
          if (original.locked)
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0.0, 0.82, 1.0],
              ).createShader(bounds),
              blendMode: BlendMode.dstIn,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final verse in original.verses)
                    _OriginalVerseBlock(verse: verse),
                ],
              ),
            )
          else
            for (final verse in original.verses) _OriginalVerseBlock(verse: verse),
          if (original.locked) const _OriginalTextPaywall(),
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
///
/// Mirrors how `CommentaryComponent.tsx` invokes `UpgradePrompt` (around
/// lines 536-546): same title, body and CTA copy, same `commentary` surface.
class _CommentaryPaywall extends StatelessWidget {
  const _CommentaryPaywall();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: UpgradePrompt(
        surface: 'commentary',
        title: 'Lees het volledige commentaar',
        body:
            'Je leest nu het begin. Met Pro lees je elk commentaar bij elk '
            'hoofdstuk volledig.',
        cta: 'Verder lezen met Pro',
      ),
    );
  }
}

/// Shown under the preview when the server withheld the rest of the chapter.
///
/// The verses above are the real grondtekst, not a teaser: the free allowance
/// is the opening of the chapter, so the reader sees what they would be
/// buying before being asked to buy it.
///
/// Mirrors `_CommentaryPaywall` above and how `OriginalText.tsx` invokes
/// `UpgradePrompt`, on the same `original_text` surface.
class _OriginalTextPaywall extends StatelessWidget {
  const _OriginalTextPaywall();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: UpgradePrompt(
        surface: 'original_text',
        title: 'Bekijk de volledige grondtekst',
        body:
            'Je ziet nu het begin van het hoofdstuk. Met Pro open je het hele '
            'hoofdstuk woord voor woord, in het Hebreeuws en Grieks, met '
            'transliteratie en Strong-nummers.',
        cta: 'Verder lezen met Pro',
      ),
    );
  }
}
