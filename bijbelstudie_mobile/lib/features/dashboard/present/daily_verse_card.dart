import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible/present/read_screen.dart' show pendingVerseAnchorProvider;
import '../../settings/data/reading_settings.dart';
import '../data/daily_verse_store.dart';
import '../data/dashboard_models.dart';
import 'dashboard_providers.dart';

/// "Tekst van de dag" — the photo card at the top of the Start tab.
///
/// Modelled on the verse-of-the-day card in the YouVersion app: a full-bleed
/// nature photograph, an eyebrow and the reference at the top left, the verse
/// itself set large and left-aligned in the middle, and a centred row of
/// actions along the bottom.
///
/// Everything the card remembers is local. `GET /daytext` serves one verse and
/// nothing else, so the heart and the archive behind "Bekijk voorgaande dagen"
/// are backed by [dailyVerseStoreProvider] rather than by the server.
class DailyVerseCard extends ConsumerStatefulWidget {
  const DailyVerseCard({
    super.key,
    required this.verse,
    required this.onOpenChapter,
  });

  /// Today's verse, or null when `/dashboard` could not supply one — offline,
  /// or a feed hiccup. The card then falls back to the newest verse it has in
  /// its local archive, and renders nothing at all if that is empty too.
  final DailyVerse? verse;

  final void Function(String book, int chapter) onOpenChapter;

  @override
  ConsumerState<DailyVerseCard> createState() => _DailyVerseCardState();
}

class _DailyVerseCardState extends ConsumerState<DailyVerseCard> {
  /// The card sits at a fixed height so the dashboard does not reflow when a
  /// long verse lands where a short one was.
  static const double _cardHeight = 330;

  bool _remembered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rememberToday();
  }

  @override
  void didUpdateWidget(covariant DailyVerseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.verse?.reference != widget.verse?.reference) {
      _remembered = false;
      _rememberToday();
    }
  }

  /// Appends today's verse to the local archive, once per mount.
  ///
  /// Deferred past the current frame: this runs from `didChangeDependencies`,
  /// where writing to a provider would be a mutation during build.
  void _rememberToday() {
    final verse = widget.verse;
    if (verse == null || _remembered) return;
    _remembered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(dailyVerseStoreProvider.notifier)
          .remember(verse, version: _versionLabel(verse));
    });
  }

  /// The abbreviation printed after the reference, e.g. `SV` in
  /// "Johannes 3:16 SV".
  ///
  /// The feed does not send a translation today (see [DailyVerse.version]), so
  /// this normally names the translation the reader has selected — which is
  /// also the one "Lees het hele hoofdstuk" will open.
  String _versionLabel(DailyVerse verse) {
    final fromFeed = verse.version;
    if (fromFeed != null && fromFeed.isNotEmpty) {
      return versionAbbreviation(fromFeed);
    }
    return versionAbbreviation(ref.read(readingSettingsProvider).lastVersionId);
  }

  @override
  Widget build(BuildContext context) {
    final memory = ref.watch(dailyVerseStoreProvider);
    final verse = widget.verse;

    // Offline or a failed feed: show the last verse that did arrive rather
    // than an empty hole where the card was yesterday.
    final fallback = memory.history.isEmpty ? null : memory.history.first;
    if (verse == null && fallback == null) {
      // Nothing to show yet. While the archive is still coming off disk that
      // is a loading state; once it has been read and is empty, the card
      // simply stays out of the dashboard's way.
      if (memory.loaded) return const SizedBox.shrink();
      return const SkeletonCard(
        height: _cardHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Skeleton(height: 10, width: 110),
            SizedBox(height: 12),
            Skeleton(height: 14, width: 160),
            SizedBox(height: 28),
            SkeletonText(lines: 4, lineHeight: 13),
          ],
        ),
      );
    }

    final text = verse?.text ?? fallback!.text;
    final reference = verse?.reference ?? fallback!.reference;
    final book = verse?.book ?? fallback!.book;
    final chapter = verse?.chapter ?? fallback!.chapter;
    final version = verse == null ? fallback!.version : _versionLabel(verse);
    final liked = memory.isLiked(reference);

    return SizedBox(
      height: _cardHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(dailyVersePhoto(DateTime.now()), fit: BoxFit.cover),

            // Colours from here down sit on top of a photograph, so they are
            // literal white/black rather than theme tokens: the scrim has to
            // hold WCAG AA over any of the six images, in either brightness.
            const _PhotoScrim(),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TEKST VAN DE DAG',
                    style: AppTheme.overline.copyWith(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 9.5,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    version.isEmpty ? reference : '$reference $version',
                    style: AppTheme.bodyStrong.copyWith(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: Text(
                          text,
                          textAlign: TextAlign.left,
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.serifFontName,
                            fontSize: 19,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _PhotoAction(
                        icon: liked ? Icons.favorite : Icons.favorite_border,
                        tooltip: liked ? 'Verwijder uit favorieten' : 'Favoriet',
                        onPressed: () => ref
                            .read(dailyVerseStoreProvider.notifier)
                            .toggleLike(reference),
                      ),
                      _PhotoAction(
                        icon: Icons.ios_share,
                        tooltip: 'Delen',
                        onPressed: () => _share(text, reference, version),
                      ),
                      _PhotoAction(
                        icon: Icons.more_horiz,
                        tooltip: 'Meer',
                        onPressed: () => _showMore(
                          book,
                          chapter,
                          verse?.verse ?? fallback?.verse,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share(String text, String reference, String version) {
    final attribution = version.isEmpty ? reference : '$reference ($version)';
    return Share.share('"$text"\n\n$attribution', subject: reference);
  }

  Future<void> _showMore(String book, int chapter, int? verseNumber) async {
    final action = await showModalBottomSheet<_MoreAction>(
      context: context,
      builder: (context) => const _MoreSheet(),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _MoreAction.readChapter:
        _openChapterAtVerse(book, chapter, verseNumber);
      case _MoreAction.history:
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) => _HistorySheet(
            onOpenChapter: (book, chapter, verse) {
              Navigator.of(context).pop();
              _openChapterAtVerse(book, chapter, verse);
            },
          ),
        );
    }
  }

  /// Names the verse the reader should scroll to and highlight, then hands
  /// the actual navigation to [widget.onOpenChapter] as before — that keeps
  /// this card out of routing, which stays the dashboard's job.
  void _openChapterAtVerse(String book, int chapter, int? verseNumber) {
    if (verseNumber != null) {
      ref.read(pendingVerseAnchorProvider.notifier).set(verseNumber);
    }
    widget.onOpenChapter(book, chapter);
  }
}

/// The dark wash between photo and text.
///
/// A flat layer plus a top-and-bottom gradient: the flat part is what
/// guarantees contrast over a bright sky, the gradient is what keeps the
/// eyebrow and the action row legible over a light patch at either edge.
class _PhotoScrim extends StatelessWidget {
  const _PhotoScrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.46),
            Colors.black.withValues(alpha: 0.22),
            Colors.black.withValues(alpha: 0.52),
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
    );
  }
}

/// One of the three round buttons on the photo.
class _PhotoAction extends StatelessWidget {
  const _PhotoAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 22),
      color: Colors.white,
      splashRadius: 22,
      style: IconButton.styleFrom(
        highlightColor: Colors.white.withValues(alpha: 0.18),
      ),
    );
  }
}

enum _MoreAction { readChapter, history }

class _MoreSheet extends StatelessWidget {
  const _MoreSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.menu_book_outlined, color: AppTheme.inkMuted),
            title: Text('Lees het hele hoofdstuk', style: AppTheme.bodyStrong),
            onTap: () => Navigator.of(context).pop(_MoreAction.readChapter),
          ),
          ListTile(
            leading: Icon(Icons.history, color: AppTheme.inkMuted),
            title: Text('Bekijk voorgaande dagen', style: AppTheme.bodyStrong),
            onTap: () => Navigator.of(context).pop(_MoreAction.history),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// The local archive, newest day first.
class _HistorySheet extends ConsumerWidget {
  const _HistorySheet({required this.onOpenChapter});

  final void Function(String book, int chapter, int? verse) onOpenChapter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(dailyVerseStoreProvider);
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Text('Voorgaande dagen', style: AppTheme.displaySmall),
            ),
            if (memory.history.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: Text(
                  'Nog geen eerdere teksten bewaard. Vanaf vandaag wordt de '
                  'tekst van de dag hier verzameld.',
                  style: AppTheme.bodyMuted,
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: memory.history.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 24,
                    color: scheme.outline,
                  ),
                  itemBuilder: (context, index) {
                    final entry = memory.history[index];
                    return InkWell(
                      onTap: () =>
                          onOpenChapter(entry.book, entry.chapter, entry.verse),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _dayLabel(entry.date).toUpperCase(),
                            style: AppTheme.overline,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            entry.referenceWithVersion,
                            style: AppTheme.bodyStrong.copyWith(
                              color: AppTheme.teal,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.text,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.bodyMuted,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "maandag 1 september" for a stored `yyyy-mm-dd`, falling back to the raw
/// key for a value this build cannot parse.
String _dayLabel(String date) {
  final parsed = DateTime.tryParse(date);
  return parsed == null ? date : dutchLongDate(parsed);
}

/// Six royalty-free nature photographs, one per day, rotating.
const List<String> _photos = [
  'assets/images/daytext/1418065460487.jpg',
  'assets/images/daytext/1441974231531.jpg',
  'assets/images/daytext/1447752875215.jpg',
  'assets/images/daytext/1470071459604.jpg',
  'assets/images/daytext/1472214103451.jpg',
  'assets/images/daytext/1506905925346.jpg',
];

/// The photo behind the card on [date].
///
/// Picked from the calendar day rather than at random so it is stable across
/// rebuilds — the card must not flicker through six backgrounds while the
/// dashboard scrolls — while still changing from one day to the next.
String dailyVersePhoto(DateTime date) {
  final days = DateTime.utc(date.year, date.month, date.day)
      .difference(DateTime.utc(1970))
      .inDays;
  return _photos[days % _photos.length];
}

/// The short label for a translation id, as it is printed after a reference.
///
/// Hand-mapped for the translations the app ships; anything the server starts
/// serving falls back to its id in capitals, which is wrong-looking but never
/// blank.
String versionAbbreviation(String versionId) {
  return switch (versionId) {
    'statenvertaling' => 'SV',
    'nbg51' => 'NBG51',
    'canisiusbijbel' => 'CANIS',
    'heilige_schrift_1917' => 'HS1917',
    'kjv' => 'KJV',
    'asv' => 'ASV',
    'web' => 'WEB',
    'geneva' => 'GNV',
    'coverdale' => 'CVDL',
    _ => versionId.replaceAll('_', '').toUpperCase(),
  };
}
