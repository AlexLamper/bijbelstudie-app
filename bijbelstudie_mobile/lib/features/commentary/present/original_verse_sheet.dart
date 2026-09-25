import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible/domain/bible_models.dart';
import '../../bible/present/bible_providers.dart';
import '../../premium/present/upgrade_prompt.dart';
import 'commentary_pane.dart' show OriginalVerseBlock;

/// "Grondtekst" for one verse, from the verse action sheet: the STEPBible
/// Hebrew/Greek of that verse alone, word by word.
///
/// The app's counterpart of the per-verse grondtekst panel `ChapterViewer.tsx`
/// opens under a verse. It reads the same chapter as the Grondtekst tab
/// ([originalChapterProvider]), so a verse opened here is already cached when
/// the reader moves on to the tab, and the other way round.
///
/// No client-side Pro gate: the server truncates the chapter to the free
/// allowance, so a verse inside it simply renders and one past it is missing
/// from a `locked` chapter - which is when the upgrade prompt shows instead.
Future<void> showOriginalVerseSheet({
  required BuildContext context,
  required ChapterContent chapter,
  required Verse verse,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusLg),
      ),
    ),
    builder: (_) => _OriginalVerseSheet(chapter: chapter, verse: verse),
  );
}

class _OriginalVerseSheet extends ConsumerWidget {
  const _OriginalVerseSheet({required this.chapter, required this.verse});

  final ChapterContent chapter;
  final Verse verse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final async = ref.watch(
      originalChapterProvider(
        ChapterRef('stepbible', chapter.book, chapter.chapter),
      ),
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('Grondtekst'),
                const SizedBox(height: 6),
                Text(
                  '${chapter.book} ${chapter.chapter}:${verse.number}',
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const RuleLine(),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: async.when(
                loading: () => const [SkeletonText(lines: 4, lineHeight: 14)],
                error: (_, __) => const [_Unavailable()],
                data: (original) => _body(original),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(OriginalChapter original) {
    final match = original.verses.where((v) => v.number == verse.number);
    if (match.isEmpty) {
      return [original.locked ? const _Paywall() : const _Unavailable()];
    }
    return [
      OriginalVerseBlock(verse: match.first),
      const RuleLine(),
      const SizedBox(height: 12),
      // CC BY 4.0: the attribution goes wherever the words are shown.
      Text(
        original.attribution,
        style: AppTheme.bodyMuted.copyWith(fontSize: 11),
      ),
    ];
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.translate_outlined,
      title: 'Geen grondtekst',
      description:
          'De Hebreeuwse/Griekse tekst is voor dit vers niet beschikbaar.',
    );
  }
}

class _Paywall extends StatelessWidget {
  const _Paywall();

  @override
  Widget build(BuildContext context) {
    return const UpgradePrompt(
      surface: 'original_text',
      title: 'Bekijk de grondtekst van dit vers',
      body:
          'Met Pro open je elk vers woord voor woord in de originele grondtekst, '
          'in het Hebreeuws en Grieks, met uitspraak en betekenis.',
      cta: 'Ontgrendel met Pro',
    );
  }
}
