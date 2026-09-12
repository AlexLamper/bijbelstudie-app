import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../ai/present/ai_assistant_pane.dart';
import '../../bible/present/read_screen.dart';
import '../../bible/present/reader_header.dart';
import '../../bible/present/bible_providers.dart';
import '../../commentary/present/commentary_pane.dart';
import '../../notes/present/notes_providers.dart';
import '../../notes/present/verse_action_sheet.dart';
import '../../onboarding/present/tour_controller.dart';
import '../../profile/present/profile_provider.dart';
import '../../settings/data/reading_settings.dart';
import '../data/context_repository.dart';
import 'geo_image_view.dart';
import '../domain/summary_format.dart';
import 'study_pane_controller.dart';

/// `/studie` on www.bijbelstudie.io.
///
/// The website shows the chapter and the study materials side by side on a
/// wide screen and a two-button pane switcher below `lg`. A phone is always
/// below `lg`, so this is the switcher variant: **Bijbel** and **Studie**,
/// with the materials pane carrying the site's five tabs.
class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({super.key});

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> {
  @override
  Widget build(BuildContext context) {
    // Held in a provider rather than local state so the guided tour can walk
    // from the bible text to the study materials - see StudyPaneController.
    final showMaterials = ref.watch(
      studyPaneProvider.select((pane) => pane.showMaterials),
    );
    // An IndexedStack builds every child, so the materials pane used to mount
    // during the brief window before the reader knows where it is - firing its
    // fetches at the Genesis 1 placeholder and then again at the real chapter.
    // `restored` always flips, even when hydration times out, so this defers
    // the pane rather than risking a tab that never appears.
    final restored = ref.watch(
      readerLocationProvider.select((location) => location.restored),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // The chapter title and the Bijbel/Studie switch are the same row on
      // both sides, so this screen owns them and the panes draw only what is
      // theirs - the reading tools on one side, the materials tabs on the
      // other. Drawn by each pane instead, an IndexedStack would hold two live
      // copies of the same switch.
      body: Container(
        color: AppTheme.surface,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: TourAnchor(
                  id: TourAnchorIds.studyPaneSwitcher,
                  child: ReaderTitleBar(showMaterials: showMaterials),
                ),
              ),
              Expanded(
                // The header above has already cleared the status bar, so the
                // panes below it must not clear it a second time. [ReadScreen]
                // is also a screen in its own right at `/read`, where its own
                // SafeArea is exactly right.
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  // IndexedStack so switching panes does not lose the reader's
                  // scroll offset or an in-flight AI answer.
                  child: IndexedStack(
                    index: showMaterials ? 1 : 0,
                    children: [
                      const ReadScreen(embedded: true),
                      if (restored)
                        const StudyMaterialsPane()
                      else
                        const AppLoader(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudyMaterialsPane extends ConsumerStatefulWidget {
  const StudyMaterialsPane({super.key});

  @override
  ConsumerState<StudyMaterialsPane> createState() => _StudyMaterialsPaneState();
}

class _StudyMaterialsPaneState extends ConsumerState<StudyMaterialsPane>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 5,
    vsync: this,
    initialIndex: ref.read(studyPaneProvider).materialsTab,
  );

  @override
  void initState() {
    super.initState();
    // Two-way: a swipe or a tap on the tab bar writes back, so the provider is
    // never stale when the tour reads it, and the tour writing to the provider
    // moves the tabs (see the listen in build).
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      ref
          .read(studyPaneProvider.notifier)
          .setMaterialsTab(_tabController.index);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(studyPaneProvider.select((pane) => pane.materialsTab), (_, tab) {
      if (tab != _tabController.index) _tabController.animateTo(tab);
    });

    final location = ref.watch(readerLocationProvider);
    final settings = ref.watch(readingSettingsProvider);
    final isPro = ref.watch(profileProvider).value?.isPro ?? false;

    return Column(
      children: [
        Container(
          // No horizontal padding of its own: the tab row runs to both screen
          // edges so its rule does, and the row insets its own first label to
          // the page margin instead. Padding here as well put the first tab
          // 32px in while the chapter title above it sat at 16.
          color: AppTheme.surface,
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.zero,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppTheme.rule)),
                  ),
                  child: TourAnchor(
                    id: TourAnchorIds.studyMaterialsTabs,
                    child: AnimatedBuilder(
                      animation: _tabController,
                      builder: (context, _) => AppUnderlineTabs(
                        // "AI-assistent" spelled out does not fit beside the
                        // other four at 390px; the purple glyph is what marks
                        // it as the tab that is not a source of its own.
                        labels: const [
                          'Commentaar',
                          'Grondtekst',
                          'Info',
                          'Notities',
                          'Assistent',
                        ],
                        // 14 rather than 20, purely so all five fit. The row
                        // stays scrollable for larger text settings.
                        gap: 14,
                        leadingIcons: {
                          // Kept from the old inline Tab: without it the only
                          // sign Grondtekst is Pro-gated is the paywall you
                          // hit after tapping.
                          if (!isPro) 1: Icons.lock_outline,
                          4: Icons.auto_awesome,
                        },
                        // The assistant's sparkle keeps its green whether the
                        // tab is selected or not: it is the one tab that is
                        // metered and Pro-upsold, and the mark is what says
                        // so before you tap it. The Pro lock on Grondtekst
                        // has no entry, so it follows its label as before.
                        leadingIconColors: {4: AppTheme.assistant},
                        // The row runs to both screen edges, so it is inset
                        // back out of the 16px page margin.
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        selectedIndex: _tabController.index,
                        onChanged: _tabController.animateTo,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              CommentaryPane(location: location, settings: settings),
              // The server already truncates this to the free preview and
              // reports `locked` when it did, so the pane itself decides what
              // to show - see the doc comment on OriginalTextPane.
              OriginalTextPane(location: location),
              _GeneralInfoPane(book: location.book, chapter: location.chapter),
              _ChapterNotesPane(
                book: location.book,
                chapter: location.chapter,
                versionId: location.versionId,
              ),
              const AiAssistantPane(),
            ],
          ),
        ),
      ],
    );
  }
}

/// The book introduction plus the place photographs, matching
/// `components/study/HistoricalContext.tsx`.
class _GeneralInfoPane extends ConsumerWidget {
  const _GeneralInfoPane({required this.book, required this.chapter});

  final String book;
  final int chapter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(bookSummaryProvider(book));
    final images = ref.watch(geoImagesProvider(GeoRef(book, chapter)));
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Row(
          children: [
            Icon(Icons.menu_book_outlined, size: 15, color: AppTheme.teal),
            const SizedBox(width: 8),
            Text(
              book,
              style: AppTheme.bodyStrong.copyWith(color: scheme.onSurface),
            ),
          ],
        ),
        const SizedBox(height: 16),

        images.maybeWhen(
          data: (list) => list.isEmpty
              ? const SizedBox.shrink()
              : SizedBox(
                  height: 138,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final image = list[index];
                      return SizedBox(
                        width: 160,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusSm,
                              ),
                              child: SizedBox(
                                width: 160,
                                height: 100,
                                child: GeoImageView(image: image, width: 320),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              image.placeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.caption.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                            ),
                            // The CC licence requires the credit line to be
                            // visible next to the image, not buried.
                            Text(
                              '${image.credit} · ${image.license}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.caption.copyWith(
                                fontSize: 10,
                                color: AppTheme.inkFaint,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
          orElse: () => const SizedBox.shrink(),
        ),

        summary.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: AppLoader(size: 22),
          ),
          error: (_, __) => Text(
            'Informatie kon niet worden geladen.',
            style: AppTheme.bodyMuted,
          ),
          data: (text) {
            final paragraphs = formatSummary(text);
            if (paragraphs.isEmpty) {
              return const AppEmptyState(
                icon: Icons.info_outline,
                title: 'Geen achtergrondinformatie',
                description: 'Voor dit boek is nog geen inleiding beschikbaar.',
              );
            }
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _SummaryBody(paragraphs: paragraphs),
            );
          },
        ),
      ],
    );
  }
}

/// The book introduction, set as paragraphs.
///
/// This used to be one `SelectableText` holding the API's raw string. The
/// separators in that string are bare carriage returns, which buy no vertical
/// space in a Flutter paragraph, so several thousand words arrived as a single
/// unbroken block — readable in the sense that the glyphs were on screen, and
/// in no other sense. Paragraphs are laid out individually here so the gap
/// between them is a real gap, matching what the website does with the same
/// text.
class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.paragraphs});

  final List<SummaryParagraph> paragraphs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bodyStyle = TextStyle(
      fontFamily: AppTheme.sansFontName,
      fontSize: 15,
      height: 1.75,
      color: scheme.onSurface.withValues(alpha: 0.88),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < paragraphs.length; i++)
          Padding(
            padding: EdgeInsets.only(
              // A heading needs room above it to read as a break in the text,
              // but not when it opens the section.
              top: i == 0
                  ? 0
                  : (paragraphs[i].kind == SummaryParagraphKind.heading
                        ? 26
                        : 16),
              bottom: paragraphs[i].kind == SummaryParagraphKind.heading
                  ? 2
                  : 0,
            ),
            child: _SummaryParagraphText(
              paragraph: paragraphs[i],
              bodyStyle: bodyStyle,
            ),
          ),
      ],
    );
  }
}

class _SummaryParagraphText extends StatelessWidget {
  const _SummaryParagraphText({
    required this.paragraph,
    required this.bodyStyle,
  });

  final SummaryParagraph paragraph;
  final TextStyle bodyStyle;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    switch (paragraph.kind) {
      case SummaryParagraphKind.heading:
        // A teal rule down the left, as on the website, so a section title is
        // structure rather than a shouted sentence.
        return Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: AppTheme.teal, width: 3)),
          ),
          child: SelectableText(
            paragraph.text,
            style: bodyStyle.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        );
      case SummaryParagraphKind.numbered:
        return Padding(
          padding: const EdgeInsets.only(left: 18),
          child: _referenceRichText(paragraph.text, bodyStyle),
        );
      case SummaryParagraphKind.body:
        return _referenceRichText(paragraph.text, bodyStyle);
    }
  }

  /// Scripture references are tinted and kept on one line, so `(Gen 1:1)`
  /// cannot wrap across a line break mid-citation.
  Widget _referenceRichText(String text, TextStyle style) {
    final spans = <TextSpan>[];
    var index = 0;
    for (final match in summaryReferencePattern.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w600),
        ),
      );
      index = match.end;
    }
    if (index < text.length) spans.add(TextSpan(text: text.substring(index)));

    return SelectableText.rich(TextSpan(style: style, children: spans));
  }
}

/// Every note the reader has on the open chapter - `ChapterNotes.tsx`.
///
/// The empty state's `+ Nieuwe notitie` button matches the create-note
/// affordance `ChapterNotes.tsx` shows in the same spot, so an empty tab is
/// not a dead end on mobile either.
class _ChapterNotesPane extends ConsumerWidget {
  const _ChapterNotesPane({
    required this.book,
    required this.chapter,
    required this.versionId,
  });

  final String book;
  final int chapter;

  /// The open Bible version, used as the note's `translation` when the
  /// reader creates one here rather than off a specific verse.
  final String versionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesListProvider);
    final scheme = Theme.of(context).colorScheme;

    return notes.when(
      loading: () => const AppLoader(),
      error: (_, __) => const AppEmptyState(
        icon: Icons.wifi_off_outlined,
        title: 'Notities niet geladen',
        description: 'Controleer je verbinding en probeer het opnieuw.',
      ),
      data: (all) {
        final mine =
            all.where((n) => n.book == book && n.chapter == chapter).toList()
              ..sort((a, b) => (a.verse ?? 0).compareTo(b.verse ?? 0));

        if (mine.isEmpty) {
          return AppEmptyState(
            icon: Icons.sticky_note_2_outlined,
            title: 'Nog geen notities',
            description:
                'Houd een vers lang ingedrukt in de Bijbel-pane om een notitie '
                'of markering te maken.',
            action: SiteButton(
              label: '+ Nieuwe notitie',
              expand: false,
              onPressed: () => showAddNoteDialog(
                context: context,
                ref: ref,
                book: book,
                chapter: chapter,
                translation: versionId,
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          itemCount: mine.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final note = mine[index];
            return AppCard(
              radius: AppTheme.radiusMd,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.verse == null
                        ? '$book $chapter'
                        : '$book $chapter:${note.verse}',
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (note.noteText.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      note.noteText,
                      style: AppTheme.bodyMuted.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
