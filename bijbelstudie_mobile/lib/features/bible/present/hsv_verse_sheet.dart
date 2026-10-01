import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../domain/bible_models.dart';
import 'bible_providers.dart';

/// One verse in the Herziene Statenvertaling, opened from the verse action
/// sheet - the app's counterpart of `HsvVersePanel.tsx` on the website.
///
/// The HSV is not a translation this product may serve; it is one it may quote,
/// fifty verses of it, free of charge, with the source named. So this is a
/// sheet and not a reading mode: there is no HSV in the version picker, no HSV
/// chapter, and this sheet only ever opens on a verse the server's index says
/// is one of the fifty.
///
/// The text is shown, not handed over: a plain [Text], never a
/// [SelectableText], and the verse sheet's Kopiëren row keeps copying the
/// translation the reader is actually in. The attribution sits under the words
/// every time, in the publisher's own wording - it is the condition the
/// quotation rests on, not a credit we may tuck away.
Future<void> showHsvVerseSheet({
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
    ),
    builder: (_) => _HsvVerseSheet(chapter: chapter, verse: verse),
  );
}

class _HsvVerseSheet extends ConsumerWidget {
  const _HsvVerseSheet({required this.chapter, required this.verse});

  final ChapterContent chapter;
  final Verse verse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final async = ref.watch(
      hsvChapterProvider(ChapterRef('hsv', chapter.book, chapter.chapter)),
    );
    final index = ref.watch(hsvIndexProvider).asData?.value;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('Herziene Statenvertaling'),
            const SizedBox(height: 6),
            Text(
              '${chapter.book} ${chapter.chapter}:${verse.number}',
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            async.when(
              loading: () => const SkeletonText(lines: 3, lineHeight: 14),
              error: (_, __) => const _Unavailable(),
              data: (verses) {
                final text = verses[verse.number];
                if (text == null || text.isEmpty) return const _Unavailable();
                return Text(text, style: AppTheme.bodyLead);
              },
            ),
            const SizedBox(height: 16),
            const RuleLine(),
            const SizedBox(height: 12),
            Text(
              [
                if (index != null && index.attribution.isNotEmpty)
                  index.attribution
                else
                  'Copyright ©2010/2016 Stichting HSV',
                if (index != null && index.notice.isNotEmpty) index.notice,
              ].join(' '),
              style: AppTheme.bodyMuted.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Dit vers is nu niet beschikbaar in de HSV.',
      style: AppTheme.bodyMuted,
    );
  }
}
