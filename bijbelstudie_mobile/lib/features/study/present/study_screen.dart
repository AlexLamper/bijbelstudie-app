import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../ai/present/ai_assistant_pane.dart';
import '../../bible/present/read_screen.dart';
import '../../bible/present/bible_providers.dart';
import '../../commentary/present/commentary_pane.dart';
import '../../notes/present/notes_providers.dart';
import '../../profile/present/profile_provider.dart';
import '../../settings/data/reading_settings.dart';
import '../data/context_repository.dart';

/// `/studie` on www.bijbel-studie.com.
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
  bool _showMaterials = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _PaneSwitcher(
              showMaterials: _showMaterials,
              onChanged: (value) => setState(() => _showMaterials = value),
            ),
            Expanded(
              // IndexedStack so switching panes does not lose the reader's
              // scroll offset or an in-flight AI answer.
              child: IndexedStack(
                index: _showMaterials ? 1 : 0,
                children: const [ReadScreen(), StudyMaterialsPane()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `flex items-stretch border-b bg-gray-50` with two `h-12` buttons; the
/// active one is teal on a 7% teal wash with a 2px rounded underline.
class _PaneSwitcher extends StatelessWidget {
  const _PaneSwitcher({required this.showMaterials, required this.onChanged});

  final bool showMaterials;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget button({
      required String label,
      required IconData icon,
      required bool active,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 48,
              color: active
                  ? AppTheme.teal.withValues(alpha: 0.07)
                  : Colors.transparent,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 16,
                        color: active ? AppTheme.teal : AppTheme.inkMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: AppTheme.bodyStrong.copyWith(
                          color: active ? AppTheme.teal : AppTheme.inkMuted,
                        ),
                      ),
                    ],
                  ),
                  if (active)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 0,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: AppTheme.teal,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outline)),
      ),
      child: Row(
        children: [
          button(
            label: 'Bijbel',
            icon: Icons.menu_book_outlined,
            active: !showMaterials,
            onTap: () => onChanged(false),
          ),
          button(
            label: 'Studie',
            icon: Icons.chat_bubble_outline,
            active: showMaterials,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

/// `components/study/StudyMaterialsSection.tsx` — Commentaar, Grondtekst
/// (Pro), Algemene info, Notities, AI-assistent.
class StudyMaterialsPane extends ConsumerStatefulWidget {
  const StudyMaterialsPane({super.key});

  @override
  ConsumerState<StudyMaterialsPane> createState() => _StudyMaterialsPaneState();
}

class _StudyMaterialsPaneState extends ConsumerState<StudyMaterialsPane>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 5, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(readerLocationProvider);
    final settings = ref.watch(readingSettingsProvider);
    final isPro = ref.watch(profileProvider).value?.isPro ?? false;

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
            tabs: [
              const Tab(height: 42, text: 'Commentaar'),
              Tab(
                height: 42,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Grondtekst'),
                    if (!isPro) ...[
                      const SizedBox(width: 5),
                      const Icon(Icons.lock_outline, size: 12),
                    ],
                  ],
                ),
              ),
              const Tab(height: 42, text: 'Algemene info'),
              const Tab(height: 42, text: 'Notities'),
              const Tab(height: 42, text: 'AI-assistent'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              CommentaryPane(location: location, settings: settings),
              // The site marks Grondtekst `isPro: true`; the server enforces
              // it too, so this is a nicer wall, not the wall.
              isPro
                  ? OriginalTextPane(location: location)
                  : const _ProWall(
                      title: 'Grondtekst is onderdeel van Pro',
                      description:
                          'Bekijk het Hebreeuws en Grieks woord voor woord, '
                          'met transliteratie en Strong-nummers.',
                    ),
              _GeneralInfoPane(book: location.book, chapter: location.chapter),
              _ChapterNotesPane(book: location.book, chapter: location.chapter),
              const AiAssistantPane(),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProWall extends StatelessWidget {
  const _ProWall({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.workspace_premium_outlined,
      title: title,
      description: description,
      action: SiteButton(
        label: 'Bekijk Pro',
        expand: false,
        onPressed: () => context.push('/premium'),
      ),
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
            const Icon(Icons.menu_book_outlined, size: 15, color: AppTheme.teal),
            const SizedBox(width: 8),
            Text(book, style: AppTheme.bodyStrong.copyWith(color: scheme.onSurface)),
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
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusSm),
                              child: Image.network(
                                image.url,
                                width: 160,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 160,
                                  height: 100,
                                  color: AppTheme.teal.withValues(alpha: 0.08),
                                ),
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
          data: (text) => text == null || text.isEmpty
              ? const AppEmptyState(
                  icon: Icons.info_outline,
                  title: 'Geen achtergrondinformatie',
                  description: 'Voor dit boek is nog geen inleiding beschikbaar.',
                )
              : Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: SelectableText(
                    text,
                    style: TextStyle(
                      fontFamily: AppTheme.sansFontName,
                      fontSize: 15,
                      height: 1.75,
                      color: scheme.onSurface.withValues(alpha: 0.88),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Every note the reader has on the open chapter — `ChapterNotes.tsx`.
class _ChapterNotesPane extends ConsumerWidget {
  const _ChapterNotesPane({required this.book, required this.chapter});

  final String book;
  final int chapter;

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
        final mine = all
            .where((n) => n.book == book && n.chapter == chapter)
            .toList()
          ..sort((a, b) => (a.verse ?? 0).compareTo(b.verse ?? 0));

        if (mine.isEmpty) {
          return const AppEmptyState(
            icon: Icons.sticky_note_2_outlined,
            title: 'Nog geen notities',
            description:
                'Houd een vers lang ingedrukt in de Bijbel-pane om een notitie '
                'of markering te maken.',
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
                      style: AppTheme.bodyMuted.copyWith(color: scheme.onSurface),
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
