import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible/present/read_screen.dart' show pendingVerseAnchorProvider;
import '../../settings/data/reading_settings.dart';
import '../data/daily_verse_store.dart';
import '../data/dashboard_repository.dart';
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
  bool _syncedArchive = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rememberToday();
    _syncArchive();
  }

  /// Pulls the shared archive down once per card mount and folds it into the
  /// device's copy.
  ///
  /// Without this the archive only ever holds the days this install was opened,
  /// so a new phone or a reinstall shows "Voorgaande dagen" as empty however
  /// long the account has existed. Failures are silent by design - the sheet
  /// falls back to whatever the device recorded itself.
  void _syncArchive() {
    if (_syncedArchive) return;
    _syncedArchive = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final entries = await ref
          .read(dashboardRepositoryProvider)
          .getDayTextHistory();
      if (!mounted) return;
      await ref.read(dailyVerseStoreProvider.notifier).mergeServer(entries);
    });
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
    final verseNumber = verse?.verse ?? fallback?.verse;
    final photo = dailyVersePhoto(DateTime.now());

    // Tapping the photo opens the same card full screen. The action buttons on
    // top of it keep their own taps: a tap recognizer nested inside this one
    // is the deeper entry in the gesture arena and wins it.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openExpanded(
        photo: photo,
        text: text,
        reference: reference,
        version: version,
        book: book,
        chapter: chapter,
        verseNumber: verseNumber,
      ),
      child: SizedBox(
        height: _cardHeight,
        child: Hero(
          tag: dailyVerseHeroTag,
          flightShuttleBuilder: dailyVerseFlightShuttle,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            child: _VerseFace(
              photo: photo,
              text: text,
              reference: reference,
              version: version,
              liked: liked,
              expanded: false,
              onLike: () =>
                  ref.read(dailyVerseStoreProvider.notifier).toggleLike(reference),
              onShare: () => _share(text, reference, version),
              onMore: () => _showMore(book, chapter, verseNumber),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the card full screen: the same photograph, the same reference and
  /// the same actions, edge to edge and with the verse in full rather than
  /// clipped at six lines.
  ///
  /// A route rather than a dialog, so the photograph can fly from the card's
  /// place on the dashboard to the whole screen as one continuous movement
  /// ([Hero], with [dailyVerseFlightShuttle] rounding the corners off along the
  /// way). A dialog cannot do that: it is inset by its own padding, so it can
  /// never reach the corners, and it appears with a scale-and-fade of its own
  /// that has nothing to do with where the card was.
  Future<void> _openExpanded({
    required String photo,
    required String text,
    required String reference,
    required String version,
    required String book,
    required int chapter,
    required int? verseNumber,
  }) {
    // The root navigator, not the shell's: a route pushed on the shell
    // navigator is laid out inside MainScaffold's body, so it stops short of
    // the bottom navigation bar instead of covering the screen.
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        // Transparent underneath so the dashboard stays visible while the
        // photograph is still on its way up.
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 340),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (routeContext, _, _) => _ExpandedVerseScreen(
          photo: photo,
          text: text,
          reference: reference,
          version: version,
          onShare: () => _share(text, reference, version),
          onReadChapter: () {
            Navigator.of(routeContext).pop();
            _openChapterAtVerse(book, chapter, verseNumber);
          },
          onHistory: () => _showHistorySheet(
            routeContext,
            beforeOpen: () => Navigator.of(routeContext).pop(),
          ),
        ),
        // Only the chrome around the photograph fades; the photograph itself
        // is carried by the hero flight, so fading it too would read as a
        // dissolve laid over a movement.
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
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
        await _showHistorySheet(context);
    }
  }

  /// The local archive, as a sheet on [host]'s navigator — the dashboard's for
  /// the card, the dialog's for the modal, so the sheet lands on top of it.
  ///
  /// [beforeOpen] runs after the sheet closes and before the reader is sent to
  /// a chapter; that is where the expanded card dismisses itself.
  Future<void> _showHistorySheet(
    BuildContext host, {
    VoidCallback? beforeOpen,
  }) {
    return showModalBottomSheet<void>(
      context: host,
      isScrollControlled: true,
      builder: (sheetContext) => _HistorySheet(
        onOpenChapter: (book, chapter, verse) {
          Navigator.of(sheetContext).pop();
          beforeOpen?.call();
          _openChapterAtVerse(book, chapter, verse);
        },
      ),
    );
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

/// Everything painted on the photograph: scrim, eyebrow and reference, the
/// verse, and the action row.
///
/// Shared by the 330px card on the dashboard and by the modal it opens, which
/// differ only in type scale, in whether the verse is clipped at six lines or
/// scrolls in full, and in the extra actions the modal has room to spell out.
class _VerseFace extends StatelessWidget {
  const _VerseFace({
    required this.photo,
    required this.text,
    required this.reference,
    required this.version,
    required this.liked,
    required this.expanded,
    required this.onLike,
    required this.onShare,
    this.onMore,
    this.onReadChapter,
    this.onHistory,
    this.onClose,
  });

  final String photo;
  final String text;
  final String reference;
  final String version;
  final bool liked;

  /// True in the modal: bigger type, the whole verse, and a close button.
  final bool expanded;

  final VoidCallback onLike;
  final VoidCallback onShare;

  /// Card only — the "…" sheet that holds what the modal spells out.
  final VoidCallback? onMore;

  /// Modal only.
  final VoidCallback? onReadChapter;
  final VoidCallback? onHistory;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(photo, fit: BoxFit.cover),

        // Colours from here down sit on top of a photograph, so they are
        // literal white/black rather than theme tokens: the scrim has to
        // hold WCAG AA over any of the six images, in either brightness.
        const _PhotoScrim(),

        Padding(
          // Full screen means under the notch and under the home indicator, so
          // the text insets by the system padding on top of its own.
          padding: expanded
              ? EdgeInsets.fromLTRB(22, 16, 22, 10) +
                    MediaQuery.paddingOf(context)
              : const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: expanded ? 10 : 0),
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
                              fontSize: expanded ? 17 : 15,
                              fontWeight: FontWeight.w700,
                              shadows: const [
                                Shadow(
                                  offset: Offset(0, 1),
                                  blurRadius: 3,
                                  color: Color(0x59000000),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (onClose != null)
                    _PhotoAction(
                      icon: Icons.close,
                      tooltip: 'Sluiten',
                      onPressed: onClose!,
                    ),
                ],
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    // Platform default in the modal, so a long verse scrolls;
                    // the card clips at six lines instead.
                    physics: expanded
                        ? null
                        : const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.symmetric(vertical: expanded ? 12 : 0),
                    child: Text(
                      text,
                      textAlign: TextAlign.left,
                      maxLines: expanded ? null : 6,
                      overflow: expanded
                          ? TextOverflow.clip
                          : TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.serifFontName,
                        fontSize: expanded ? 21 : 19,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        // Does most of the work the scrim would otherwise have
                        // to do with brute darkness: it separates the letters
                        // from whatever is directly behind them, so the
                        // photograph can stay visible. The website has carried
                        // this on the verse since it shipped; this card never
                        // did, which is the whole reason its text read as
                        // less crisp than the same verse in a browser.
                        shadows: const [
                          Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 3,
                            color: Color(0x59000000),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _VerseActions(
                liked: liked,
                onLike: onLike,
                onShare: onShare,
                onMore: onMore,
                onReadChapter: onReadChapter,
                onHistory: onHistory,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The actions along the bottom of the photo.
///
/// On the card: favourite, share and the "…" sheet. In the modal, where there
/// is room, the sheet's two entries are spelled out instead — "Lees het hele
/// hoofdstuk" as a button and the archive as an icon — so both surfaces offer
/// the same four things and the modal never stacks a sheet on a dialog.
class _VerseActions extends StatelessWidget {
  const _VerseActions({
    required this.liked,
    required this.onLike,
    required this.onShare,
    this.onMore,
    this.onReadChapter,
    this.onHistory,
  });

  final bool liked;
  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback? onMore;
  final VoidCallback? onReadChapter;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final icons = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PhotoAction(
          icon: liked ? Icons.favorite : Icons.favorite_border,
          tooltip: liked ? 'Verwijder uit favorieten' : 'Favoriet',
          onPressed: onLike,
        ),
        _PhotoAction(
          icon: Icons.ios_share,
          tooltip: 'Delen',
          onPressed: onShare,
        ),
        if (onMore != null)
          _PhotoAction(
            icon: Icons.more_horiz,
            tooltip: 'Meer',
            onPressed: onMore!,
          ),
        if (onHistory != null)
          _PhotoAction(
            icon: Icons.history,
            tooltip: 'Bekijk voorgaande dagen',
            onPressed: onHistory!,
          ),
      ],
    );

    if (onReadChapter == null) return icons;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: onReadChapter,
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: Text(
              'Lees het hele hoofdstuk',
              style: AppTheme.bodyStrong.copyWith(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.34)),
              ),
            ),
          ),
        ),
        icons,
      ],
    );
  }
}

/// The tag that links the card on the dashboard to the full-screen version.
const String dailyVerseHeroTag = 'daily-verse-card';

/// Rounds the card's corners off as it grows into the screen, and back on the
/// way down.
///
/// Without this the hero would jump to square corners the instant the flight
/// starts - the default shuttle renders the destination subtree throughout -
/// which is exactly the seam this transition is meant not to have.
Widget dailyVerseFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromContext,
  BuildContext toContext,
) {
  final pushing = direction == HeroFlightDirection.push;
  final hero = (pushing ? toContext : fromContext).widget as Hero;

  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final t = pushing ? animation.value : 1 - animation.value;
      return ClipRRect(
        borderRadius: BorderRadius.circular(
          lerpDouble(AppTheme.radiusLg, 0, Curves.easeOut.transform(t))!,
        ),
        // The shuttle is built in the Navigator's overlay, outside both
        // routes, so it inherits no Material and no DefaultTextStyle. Without
        // one, every Text in the card falls back to Flutter's "missing style"
        // default - yellow double underlines - for the length of the flight.
        // Transparency, so this adds a text style and nothing else.
        child: Material(
          type: MaterialType.transparency,
          child: hero.child,
        ),
      );
    },
  );
}

/// The card again, filling the screen.
///
/// A [ConsumerWidget] rather than a snapshot of the card's state: it sits on
/// its own route, so the heart only follows [dailyVerseStoreProvider] if it
/// watches the store itself.
class _ExpandedVerseScreen extends ConsumerStatefulWidget {
  const _ExpandedVerseScreen({
    required this.photo,
    required this.text,
    required this.reference,
    required this.version,
    required this.onShare,
    required this.onReadChapter,
    required this.onHistory,
  });

  final String photo;
  final String text;
  final String reference;
  final String version;
  final VoidCallback onShare;
  final VoidCallback onReadChapter;
  final VoidCallback onHistory;

  @override
  ConsumerState<_ExpandedVerseScreen> createState() =>
      _ExpandedVerseScreenState();
}

class _ExpandedVerseScreenState extends ConsumerState<_ExpandedVerseScreen> {
  /// How far the reader has dragged the photograph down, in logical pixels.
  double _drag = 0;

  /// Past this, letting go closes rather than springs back.
  static const double _dismissAt = 120;

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() => _drag = (_drag + details.delta.dy).clamp(0.0, 400.0));
  }

  void _onDragEnd(DragEndDetails details) {
    final flung = details.velocity.pixelsPerSecond.dy > 700;
    if (flung || _drag > _dismissAt) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _drag = 0);
  }

  @override
  Widget build(BuildContext context) {
    final liked = ref.watch(dailyVerseStoreProvider).isLiked(widget.reference);

    // The drag both moves the photograph and thins the black behind it, so
    // pulling down reveals the dashboard rather than sliding a black sheet
    // over it.
    final progress = (_drag / (_dismissAt * 2)).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 1 - progress),
      // Edge to edge on purpose: no insets, no rounded corners, no visible
      // route beneath. SafeArea lives inside _VerseFace, where it can pad the
      // text without letting the photograph stop short of the notch.
      body: GestureDetector(
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: Transform.translate(
          offset: Offset(0, _drag),
          child: Hero(
            tag: dailyVerseHeroTag,
            flightShuttleBuilder: dailyVerseFlightShuttle,
            child: _VerseFace(
              photo: widget.photo,
              text: widget.text,
              reference: widget.reference,
              version: widget.version,
              liked: liked,
              expanded: true,
              onLike: () => ref
                  .read(dailyVerseStoreProvider.notifier)
                  .toggleLike(widget.reference),
              onShare: widget.onShare,
              onReadChapter: widget.onReadChapter,
              onHistory: widget.onHistory,
              onClose: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dark wash between photo and text.
///
/// A flat layer plus a top-and-bottom gradient: the flat part is what
/// guarantees contrast over a bright sky, the gradient is what keeps the
/// eyebrow and the action row legible over a light patch at either edge.
///
/// The two compose, so what the reader sees is the product of both: roughly
/// 71% dark at the eyebrow, 58% across the middle where the verse sits, and
/// 75% behind the action row. That middle figure is the one that matters and
/// the one that moved - it was 48%, which held up over the darker photographs
/// and left the serif text washy over the bright ones. Going further starts
/// costing the photograph, which is half of what the card is for.
class _PhotoScrim extends StatelessWidget {
  const _PhotoScrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.50),
            Colors.black.withValues(alpha: 0.28),
            Colors.black.withValues(alpha: 0.56),
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
