import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible/present/read_screen.dart' show pendingVerseAnchorProvider;
import '../../levensboom/domain/verse_scene.dart';
import '../../settings/data/reading_settings.dart';
import '../data/daily_verse_background_store.dart';
import '../data/daily_verse_store.dart';
import '../data/dashboard_repository.dart';
import '../data/dashboard_models.dart';
import 'dashboard_providers.dart';
import 'widgets/daily_verse_background.dart';
import 'widgets/daily_verse_scrim.dart';
import 'widgets/daily_verse_share_image.dart';

/// "Tekst van de dag" - the photo card at the top of the Start tab.
///
/// Modelled on the verse-of-the-day card in the YouVersion app: a full-bleed
/// background, an eyebrow and the reference at the top left, the verse
/// itself set large and left-aligned in the middle, and a centred row of
/// actions along the bottom. The background is the reader's own Levensboom
/// (see [DailyVerseBackdrop]) once it has loaded, and a painted landscape
/// before then or when there is no tree to show.
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

  /// Today's verse, or null when `/dashboard` could not supply one - offline,
  /// or a feed hiccup. The card then falls back to the newest verse it has in
  /// its local archive, and renders nothing at all if that is empty too.
  final DailyVerse? verse;

  final void Function(String book, int chapter) onOpenChapter;

  @override
  ConsumerState<DailyVerseCard> createState() => _DailyVerseCardState();
}

class _DailyVerseCardState extends ConsumerState<DailyVerseCard>
    with SingleTickerProviderStateMixin {
  /// The card sits at a fixed height so the dashboard does not reflow when a
  /// long verse lands where a short one was.
  static const double _cardHeight = 330;

  /// The verse last written to the archive (reference, label and text), so a
  /// rebuild does not write it again but a translation switch does.
  String? _rememberedKey;
  bool _syncedArchive = false;

  /// The background pages (Levensboom, photo), swiped sideways on the card.
  late final DailyVersePaging _paging = DailyVersePaging(
    this,
    initial: ref.read(dailyVerseBackgroundProvider).index,
  );

  /// True while the share image is being rendered, so a second tap waits.
  bool _sharing = false;

  @override
  void dispose() {
    _paging.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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

  /// Writes today's verse to the local archive - once, and again only when it
  /// changes (a translation switch keeps the reference but not the text).
  ///
  /// Deferred past the current frame: this runs from `build`, where writing to
  /// a provider would be a mutation during build.
  void _rememberToday(DailyVerse verse, String version) {
    final key = '${verse.reference}|$version|${verse.text}';
    if (_rememberedKey == key) return;
    _rememberedKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(dailyVerseStoreProvider.notifier)
          .remember(verse, version: version);
    });
  }

  /// Today's verse in the translation the reader reads in.
  ///
  /// `/dashboard` answers in the translation the reader had when the tab
  /// loaded. When that is not the one selected now - switched in the reader
  /// since, or the setting was still coming off disk - the verse is fetched
  /// again in the current one, and the card shows the dashboard's copy until
  /// it lands. `settled` is false while that fetch is in flight, so the
  /// archive is not written with a verse about to be replaced.
  ({DailyVerse? verse, bool settled}) _verseInReaderVersion() {
    final base = widget.verse;
    if (base == null) return (verse: null, settled: true);
    final wanted = ref.watch(
      readingSettingsProvider.select((s) => s.lastVersionId),
    );
    if (base.isIn(wanted)) return (verse: base, settled: true);
    return switch (ref.watch(dailyVerseInVersionProvider(wanted))) {
      AsyncData(:final value) => (verse: value ?? base, settled: true),
      AsyncError() => (verse: base, settled: true),
      _ => (verse: base, settled: false),
    };
  }

  /// The abbreviation printed after the reference, e.g. `SV` in
  /// "Johannes 3:16 SV".
  ///
  /// Always the translation the text is actually in, as the server names it:
  /// `versionId` when sent, else the full name. Never the reader's selection -
  /// when a translation lacks the day's verse the server sends the
  /// Statenvertaling, and labelling that with the reader's choice would pass
  /// one translation off as another. A payload naming nothing is the feed's
  /// own Statenvertaling.
  String _versionLabel(DailyVerse verse) {
    final id = verse.versionId;
    if (id != null && id.isNotEmpty) return versionAbbreviation(id);
    final fromFeed = verse.version;
    if (fromFeed != null && fromFeed.isNotEmpty) {
      return versionAbbreviation(fromFeed);
    }
    return 'SV';
  }

  @override
  Widget build(BuildContext context) {
    final memory = ref.watch(dailyVerseStoreProvider);
    final resolved = _verseInReaderVersion();
    final verse = resolved.verse;
    if (verse != null && resolved.settled) {
      _rememberToday(verse, _versionLabel(verse));
    }

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
    // The licence notice travels with licensed text everywhere it is shown:
    // as the server sent it, or - for a stored day - from its label.
    final attribution =
        verse?.attribution ?? attributionForVersionLabel(version);
    final liked = memory.isLiked(reference);
    final verseNumber = verse?.verse ?? fallback?.verse;
    final scene = verseSceneForDay(DateTime.now());
    ref.listen(
      dailyVerseBackgroundProvider,
      (_, next) => _paging.sync(next.index),
    );

    // Tapping the photo opens the same card full screen. The action buttons on
    // top of it keep their own taps: a tap recognizer nested inside this one
    // is the deeper entry in the gesture arena and wins it.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Sideways swipes page between the two backgrounds; the one it settles
      // on becomes the reader's default.
      onHorizontalDragStart: (_) => _paging.dragStart(),
      onHorizontalDragUpdate: (details) =>
          _paging.dragUpdate(details, context.size?.width ?? 0),
      onHorizontalDragEnd: (details) => ref
          .read(dailyVerseBackgroundProvider.notifier)
          .select(DailyVerseBackground.values[_paging.dragEnd(details)]),
      onHorizontalDragCancel: _paging.dragCancel,
      onTap: () => _openExpanded(
        scene: scene,
        text: text,
        reference: reference,
        version: version,
        attribution: attribution,
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
              scene: scene,
              page: _paging.page,
              text: text,
              reference: reference,
              version: version,
              attribution: attribution,
              liked: liked,
              expanded: false,
              onLike: () => ref
                  .read(dailyVerseStoreProvider.notifier)
                  .toggleLike(reference),
              onShare: (buttonContext) => _share(
                buttonContext,
                text,
                reference,
                version,
                attribution,
              ),
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
    required VerseScene scene,
    required String text,
    required String reference,
    required String version,
    required String? attribution,
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
          scene: scene,
          text: text,
          reference: reference,
          version: version,
          attribution: attribution,
          onShare: (buttonContext) => _share(
            buttonContext,
            text,
            reference,
            version,
            attribution,
          ),
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

  /// Shares the verse through the system share sheet.
  ///
  /// Anchored on the share button's own on-screen rect: on iPad share_plus
  /// pops the sheet from [sharePositionOrigin] and has nothing to anchor to
  /// without it, which is how this used to fail silently - the same fault
  /// `shareRowText` in the notes list already carries a fix for. The call is
  /// awaited rather than fired and forgotten, so a platform failure lands as
  /// a SnackBar instead of nothing happening at all.
  Future<void> _share(
    BuildContext buttonContext,
    String text,
    String reference,
    String version,
    String? notice,
  ) async {
    if (_sharing) return;
    _sharing = true;
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    final messenger = ScaffoldMessenger.maybeOf(buttonContext);
    final source = version.isEmpty ? reference : '$reference ($version)';
    try {
      // A 9:16 status image on the reader's own background, the way
      // YouVersion shares a verse; the text beside it is only where it came
      // from. The licence notice is printed in the image itself.
      final path = await renderDailyVerseShareImage(
        buttonContext,
        background: ref.read(dailyVerseBackgroundProvider),
        scene: verseSceneForDay(DateTime.now()),
        text: text,
        reference: reference,
        version: version,
        attribution: notice,
      );
      await Share.shareXFiles(
        [XFile(path, mimeType: 'image/png')],
        text: '$source - ${AppConfig.baseUrl}',
        subject: 'Tekst van de dag - $reference',
        sharePositionOrigin: origin,
      );
    } on Object {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Delen is niet gelukt.')),
      );
    } finally {
      _sharing = false;
    }
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

  /// The local archive, as a sheet on [host]'s navigator - the dashboard's for
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
  /// the actual navigation to [widget.onOpenChapter] as before - that keeps
  /// this card out of routing, which stays the dashboard's job.
  void _openChapterAtVerse(String book, int chapter, int? verseNumber) {
    if (verseNumber != null) {
      ref.read(pendingVerseAnchorProvider.notifier).set(verseNumber);
    }
    widget.onOpenChapter(book, chapter);
  }
}

/// Everything painted on the background: scrim, eyebrow and reference, the
/// verse, and the action row.
///
/// Shared by the 330px card on the dashboard and by the modal it opens, which
/// differ only in type scale, in whether the verse is clipped at six lines or
/// scrolls in full, and in the extra actions the modal has room to spell out.
class _VerseFace extends StatelessWidget {
  const _VerseFace({
    required this.scene,
    this.page,
    required this.text,
    required this.reference,
    required this.version,
    this.attribution,
    required this.liked,
    required this.expanded,
    required this.onLike,
    required this.onShare,
    this.onMore,
    this.onReadChapter,
    this.onHistory,
    this.onClose,
  });

  final VerseScene scene;

  /// Card only: the background pager's position, 0..1. Null in the modal,
  /// which shows the chosen background without paging.
  final Animation<double>? page;

  final String text;
  final String reference;
  final String version;

  /// The licence notice, printed verbatim under the verse (NBG51); null for
  /// public-domain text.
  final String? attribution;
  final bool liked;

  /// True in the modal: bigger type, the whole verse, and a close button.
  final bool expanded;

  final VoidCallback onLike;
  final void Function(BuildContext buttonContext) onShare;

  /// Card only - the "…" sheet that holds what the modal spells out.
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
        if (page case final page?)
          DailyVerseBackgroundPager(scene: scene, page: page)
        else
          DailyVerseSelectedBackground(scene: scene),

        // Colours from here down sit on top of a photograph, so they are
        // literal white/black rather than theme tokens: the scrim has to
        // hold WCAG AA over any of the photographs, in either brightness.
        const DailyVersePhotoScrim(),

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
              if (attribution case final notice?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    notice,
                    style: TextStyle(
                      fontSize: expanded ? 12 : 10.5,
                      height: 1.3,
                      color: Colors.white.withValues(alpha: 0.78),
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

        // Which background is showing; level with the eyebrow.
        if (page case final page?)
          Positioned(
            top: 20,
            right: 20,
            child: IgnorePointer(child: DailyVersePageDots(page: page)),
          ),
      ],
    );
  }
}

/// The actions along the bottom of the photo.
///
/// On the card: favourite, share and the "…" sheet. In the modal, where there
/// is room, the sheet's two entries are spelled out instead - "Lees het hele
/// hoofdstuk" as a button and the archive as an icon - so both surfaces offer
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
  final void Function(BuildContext buttonContext) onShare;
  final VoidCallback? onMore;
  final VoidCallback? onReadChapter;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final icons = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _AnimatedHeartButton(liked: liked, onPressed: onLike),
        // Builder so the button's own context - and with it its RenderBox -
        // is available to anchor the iPad share popover on.
        Builder(
          builder: (buttonContext) => _PhotoAction(
            icon: Icons.ios_share,
            tooltip: 'Delen',
            onPressed: () => onShare(buttonContext),
          ),
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
        child: Material(type: MaterialType.transparency, child: hero.child),
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
    required this.scene,
    required this.text,
    required this.reference,
    required this.version,
    required this.attribution,
    required this.onShare,
    required this.onReadChapter,
    required this.onHistory,
  });

  final VerseScene scene;
  final String text;
  final String reference;
  final String version;
  final String? attribution;
  final void Function(BuildContext buttonContext) onShare;
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
              scene: widget.scene,
              text: widget.text,
              reference: widget.reference,
              version: widget.version,
              attribution: widget.attribution,
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

/// The favourite button on the photo, with a small "pop" when a verse is
/// liked.
///
/// Behaves like a [_PhotoAction] otherwise - same size, splash and tooltip -
/// but on the transition to liked it plays a one-shot scale overshoot, swaps
/// the outline heart for the filled one, fades the colour to [_heartRed]
/// and sends a single accent ring outward. Unliking just settles the colour
/// and fill back without the ring. When the platform asks for reduced motion
/// ([MediaQuery.disableAnimationsOf]) every part of this collapses to an
/// instant state change.
/// The liked heart: `#DC2626`, red-600, the same red as the web card's heart.
/// Its own colour rather than [AppTheme.flame], which is the streak's orange;
/// the heart sits on the photo, so one value reads in light and dark alike.
const Color _heartRed = Color(0xFFDC2626);

class _AnimatedHeartButton extends StatefulWidget {
  const _AnimatedHeartButton({required this.liked, required this.onPressed});

  final bool liked;
  final VoidCallback onPressed;

  @override
  State<_AnimatedHeartButton> createState() => _AnimatedHeartButtonState();
}

class _AnimatedHeartButtonState extends State<_AnimatedHeartButton>
    with SingleTickerProviderStateMixin {
  /// Idle at 0; a fresh like runs it once to 1 and leaves it there. Drives
  /// both the scale overshoot and the ring.
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  /// 1.0 → 1.24 on the way up, then eased back through a slight overshoot.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.24,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.24,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 60,
    ),
  ]).animate(_pop);

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void didUpdateWidget(covariant _AnimatedHeartButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.liked && !oldWidget.liked && !_reduceMotion) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: widget.onPressed,
      tooltip: widget.liked ? 'Verwijder uit favorieten' : 'Favoriet',
      color: Colors.white,
      splashRadius: 22,
      style: IconButton.styleFrom(
        highlightColor: Colors.white.withValues(alpha: 0.18),
      ),
      icon: AnimatedBuilder(
        animation: _pop,
        builder: (context, child) {
          final popping = _pop.isAnimating;
          return SizedBox(
            width: 22,
            height: 22,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (popping) _ring(_pop.value),
                Transform.scale(
                  scale: popping ? _scale.value : 1.0,
                  child: child,
                ),
              ],
            ),
          );
        },
        // Colour and fill follow the liked state both ways; the 1ms duration
        // under reduced motion turns the tween into an instant swap.
        child: TweenAnimationBuilder<double>(
          duration: Duration(milliseconds: _reduceMotion ? 1 : 220),
          curve: Curves.easeOut,
          tween: Tween(begin: 0, end: widget.liked ? 1.0 : 0.0),
          builder: (context, t, _) => Icon(
            t > 0.5 ? Icons.favorite : Icons.favorite_border,
            size: 22,
            color: Color.lerp(Colors.white, _heartRed, t),
          ),
        ),
      ),
    );
  }

  /// A single expanding, fading circle in the accent colour - one clean pulse
  /// rather than a particle burst, which only reads as noise at this size.
  Widget _ring(double t) {
    final eased = Curves.easeOut.transform(t);
    return IgnorePointer(
      child: Opacity(
        opacity: (1 - eased) * 0.6,
        child: Container(
          width: 22 + eased * 26,
          height: 22 + eased * 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _heartRed, width: 2),
          ),
        ),
      ),
    );
  }
}

enum _MoreAction { readChapter, history }

class _MoreSheet extends StatelessWidget {
  const _MoreSheet();

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
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
                  separatorBuilder: (_, _) =>
                      Divider(height: 24, color: scheme.outline),
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
                          if (attributionForVersionLabel(entry.version)
                              case final notice?) ...[
                            const SizedBox(height: 4),
                            Text(
                              notice,
                              style: AppTheme.bodyMuted.copyWith(fontSize: 11),
                            ),
                          ],
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
