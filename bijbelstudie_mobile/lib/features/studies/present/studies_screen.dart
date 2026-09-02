import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../data/study_models.dart';
import 'studies_providers.dart';
import 'study_banner.dart';

/// The study catalogue: a discovery page over every study there is.
///
/// Laid out as one scroll rather than a grid of everything, because the
/// catalogue is seventy-seven studies deep and a flat list of that buries the
/// authored ones. The order answers narrowing questions: what is worth starting
/// (the carousel), which part of the Bible (the topic grid), what kind of study
/// (the pills), and only then the list itself.
///
/// Everything filters over the loaded catalogue - the search field included - so
/// no interaction here costs a request.
class StudiesScreen extends ConsumerStatefulWidget {
  const StudiesScreen({super.key});

  @override
  ConsumerState<StudiesScreen> createState() => _StudiesScreenState();
}

class _StudiesScreenState extends ConsumerState<StudiesScreen> {
  final _searchController = TextEditingController();
  bool _searchOpen = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (!_searchOpen) {
      _searchController.clear();
      ref.read(studiesQueryProvider.notifier).set('');
    }
  }

  @override
  Widget build(BuildContext context) {
    final studies = ref.watch(curatedStudiesProvider);

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppTheme.teal,
          onRefresh: () async {
            ref.invalidate(curatedStudiesProvider);
            ref.invalidate(serverStudyLessonsProvider);
            ref.invalidate(studyEnrollmentsProvider);
            await ref.read(curatedStudiesProvider.future);
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header(
                searchOpen: _searchOpen,
                controller: _searchController,
                onToggleSearch: _toggleSearch,
              )),
              ...studies.when(
                loading: () => const [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 40),
                    sliver: SliverToBoxAdapter(child: SkeletonCardColumn(count: 4)),
                  ),
                ],
                error: (error, _) => [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                    sliver: SliverToBoxAdapter(
                      child: AppEmptyState(
                        icon: Icons.wifi_off_outlined,
                        title: 'Studies niet geladen',
                        description:
                            'Controleer je verbinding en probeer het opnieuw.',
                        action: SiteButton(
                          label: 'Opnieuw proberen',
                          expand: false,
                          onPressed: () => ref.invalidate(curatedStudiesProvider),
                        ),
                      ),
                    ),
                  ),
                ],
                data: (all) => _slivers(all),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The body, once the catalogue is in hand.
  ///
  /// Searching collapses the whole page to results: the carousel and the topic
  /// grid are ways of browsing, and browsing aids are noise once the reader has
  /// told you what they want.
  List<Widget> _slivers(List<CuratedStudy> all) {
    final query = ref.watch(studiesQueryProvider).trim().toLowerCase();
    final tab = ref.watch(studiesTabProvider);
    final category = ref.watch(studiesCategoryProvider);
    final kind = ref.watch(studiesKindProvider);

    if (query.isNotEmpty) {
      final hits = all.where((study) => _matches(study, query)).toList(growable: false);
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          sliver: hits.isEmpty
              ? const SliverToBoxAdapter(
                  child: AppEmptyState(
                    icon: Icons.search_off,
                    title: 'Niets gevonden',
                    description:
                        'Probeer de naam van een bijbelboek, een persoon of een thema.',
                  ),
                )
              : SliverList.separated(
                  itemCount: hits.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _StudyRow(study: hits[index]),
                ),
        ),
      ];
    }

    final inTab = all.where((study) => _inTab(study, tab)).toList(growable: false);

    // "Mijn studies" and "Voltooid" are answers about this reader, not about
    // the catalogue, so they skip the discovery furniture entirely.
    if (tab != StudiesTab.discover) {
      return [
        SliverToBoxAdapter(child: _TabRow(active: tab)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
          sliver: inTab.isEmpty
              ? SliverToBoxAdapter(child: _emptyTab(tab))
              : SliverList.separated(
                  itemCount: inTab.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _StudyRow(study: inTab[index]),
                ),
        ),
      ];
    }

    final featured = _featured(all);
    final filtered = inTab
        .where((study) => category == null || study.category == category)
        .where((study) => kind == null || study.type == kind)
        .toList(growable: false);

    return [
      SliverToBoxAdapter(child: _TabRow(active: tab)),
      if (featured.isNotEmpty)
        SliverToBoxAdapter(child: _FeaturedCarousel(studies: featured)),
      SliverToBoxAdapter(child: _TopicGrid(all: all, active: category)),
      SliverToBoxAdapter(child: _KindRow(active: kind)),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: SectionHeader(
            eyebrow: _sectionEyebrow(category, kind),
            title: _sectionTitle(category),
            actionLabel: category == null && kind == null ? null : 'Alles bekijken',
            onAction: category == null && kind == null
                ? null
                : () {
                    ref.read(studiesCategoryProvider.notifier).clear();
                    ref.read(studiesKindProvider.notifier).select(null);
                  },
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
        sliver: filtered.isEmpty
            ? const SliverToBoxAdapter(
                child: AppEmptyState(
                  icon: Icons.search_off,
                  title: 'Geen studies',
                  description: 'Geen studie past bij deze combinatie van filters.',
                ),
              )
            : SliverList.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _StudyRow(study: filtered[index]),
              ),
      ),
    ];
  }

  Widget _emptyTab(StudiesTab tab) {
    return switch (tab) {
      StudiesTab.mine => AppEmptyState(
        icon: Icons.school_outlined,
        title: 'Nog geen studie begonnen',
        description:
            'Kies een studie bij Ontdek en begin. Je voortgang komt hier te staan.',
        action: SiteButton(
          label: 'Studies ontdekken',
          expand: false,
          onPressed: () =>
              ref.read(studiesTabProvider.notifier).select(StudiesTab.discover),
        ),
      ),
      StudiesTab.completed => const AppEmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'Nog niets afgerond',
        description: 'Zodra je alle lessen van een studie afrondt, staat die hier.',
      ),
      StudiesTab.discover => const AppEmptyState(
        icon: Icons.search_off,
        title: 'Geen studies',
      ),
    };
  }

  bool _inTab(CuratedStudy study, StudiesTab tab) {
    if (tab == StudiesTab.discover) return true;
    final status = ref.watch(studyStatusProvider(study));
    return switch (tab) {
      StudiesTab.mine => status.started && !status.completed,
      StudiesTab.completed => status.completed,
      StudiesTab.discover => true,
    };
  }

  /// The carousel shows the authored studies: they are the only ones with real
  /// artwork and a written introduction, so they are what a large card can
  /// actually fill.
  List<CuratedStudy> _featured(List<CuratedStudy> all) {
    final authored = all
        .where((study) => study.type != 'Boek' || study.about.isNotEmpty)
        .take(8)
        .toList(growable: false);
    return authored.isEmpty ? all.take(5).toList(growable: false) : authored;
  }

  static bool _matches(CuratedStudy study, String needle) {
    final haystack = [
      study.title,
      study.description,
      study.kind ?? '',
      study.type,
      ...study.books,
    ].join(' ').toLowerCase();
    return haystack.contains(needle);
  }

  static String _sectionEyebrow(String? category, String? kind) {
    if (category == null && kind == null) return 'De hele Bijbel';
    return 'Gefilterd';
  }

  static String _sectionTitle(String? category) => switch (category) {
    'ot' => 'Oude Testament',
    'nt' => 'Nieuwe Testament',
    'personen' => 'Personen',
    'themas' => "Thema's",
    _ => 'Alle studies',
  };
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.searchOpen,
    required this.controller,
    required this.onToggleSearch,
  });

  final bool searchOpen;
  final TextEditingController controller;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Studies', style: AppTheme.displayLarge),
              ),
              IconButton(
                onPressed: onToggleSearch,
                tooltip: searchOpen ? 'Zoeken sluiten' : 'Studies zoeken',
                icon: Icon(searchOpen ? Icons.close : Icons.search),
                color: AppTheme.ink,
              ),
            ],
          ),
          if (searchOpen) ...[
            const SizedBox(height: 4),
            TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Zoek een bijbelboek, persoon of thema',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onChanged: (value) => ref.read(studiesQueryProvider.notifier).set(value),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _TabRow extends ConsumerWidget {
  const _TabRow({required this.active});

  final StudiesTab active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: StudiesTab.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = StudiesTab.values[index];
          final selected = tab == active;
          return Material(
            color: selected ? AppTheme.teal : AppTheme.paperRaised,
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              onTap: () => ref.read(studiesTabProvider.notifier).select(tab),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  border: Border.all(
                    color: selected ? AppTheme.teal : AppTheme.rule,
                  ),
                ),
                child: Text(
                  tab.label,
                  style: AppTheme.bodyStrong.copyWith(
                    color: selected ? Colors.white : AppTheme.inkSoft,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The featured strip: a large landscape banner with the title and one line of
/// description underneath, swiped horizontally.
class _FeaturedCarousel extends StatelessWidget {
  const _FeaturedCarousel({required this.studies});

  final List<CuratedStudy> studies;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SizedBox(
        height: 232,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: studies.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final study = studies[index];
            return SizedBox(
              width: 280,
              child: AppCard(
                radius: AppTheme.radiusMd,
                padding: EdgeInsets.zero,
                clip: true,
                onTap: () => context.push('/studies/${study.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: StudyBanner(study: study),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              study.title,
                              style: AppTheme.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              child: Text(
                                study.description,
                                style: AppTheme.caption,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${study.lessonCount} lessen · ±${study.minutesPerLesson} min',
                              style: AppTheme.metaLabel,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The four coarse buckets, as big tappable rectangles. Two columns, because a
/// four-wide row of these is unreadable on a phone.
class _TopicGrid extends ConsumerWidget {
  const _TopicGrid({required this.all, required this.active});

  final List<CuratedStudy> all;
  final String? active;

  static const _topics = <String, ({String label, IconData icon})>{
    'ot': (label: 'Oude Testament', icon: Icons.history_edu_outlined),
    'nt': (label: 'Nieuwe Testament', icon: Icons.auto_stories_outlined),
    'personen': (label: 'Personen', icon: Icons.person_outline),
    'themas': (label: "Thema's", icon: Icons.lightbulb_outline),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = <String, int>{};
    for (final study in all) {
      final category = study.category;
      if (category != null) counts[category] = (counts[category] ?? 0) + 1;
    }

    final entries = _topics.entries
        .where((entry) => (counts[entry.key] ?? 0) > 0)
        .toList(growable: false);
    if (entries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Waar wil je lezen?'),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.1,
            children: [
              for (final entry in entries)
                _TopicTile(
                  label: entry.value.label,
                  icon: entry.value.icon,
                  count: counts[entry.key] ?? 0,
                  selected: active == entry.key,
                  onTap: () =>
                      ref.read(studiesCategoryProvider.notifier).toggle(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? AppTheme.teal : AppTheme.rule;
    return Material(
      color: selected ? AppTheme.tealTint : AppTheme.paperRaised,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: accent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 18, color: AppTheme.teal),
              Text(
                label,
                style: AppTheme.bodyStrong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text('$count studies', style: AppTheme.metaLabel),
            ],
          ),
        ),
      ),
    );
  }
}

/// The secondary filter: what kind of study, as outlined pills.
class _KindRow extends ConsumerWidget {
  const _KindRow({required this.active});

  final String? active;

  /// `null` is "Alle". The labels are the study `type` values the API sends.
  static const _kinds = <String?>[null, 'Boek', 'Persoon', 'Gedeelte', 'Onderwerp'];

  static String _label(String? kind) => switch (kind) {
    null => 'Alle',
    'Boek' => 'Bijbelboeken',
    'Persoon' => 'Personen',
    'Gedeelte' => 'Gedeelten',
    _ => "Thema's",
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _kinds.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final kind = _kinds[index];
            final selected = kind == active;
            return InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              onTap: () => ref.read(studiesKindProvider.notifier).select(kind),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppTheme.tealTint : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  border: Border.all(
                    color: selected ? AppTheme.teal : AppTheme.rule,
                  ),
                ),
                child: Text(
                  _label(kind),
                  style: AppTheme.caption.copyWith(
                    color: selected ? AppTheme.tealStrong : AppTheme.inkSoft,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One study, as a row: thumbnail, duration and title, then the action.
///
/// The meta line under the title is where YouVersion puts a star rating. There
/// is no rating in this data - and inventing one would be a lie about other
/// readers - so it carries the two facts that actually help a reader choose:
/// how many lessons, and how long each one takes.
class _StudyRow extends ConsumerWidget {
  const _StudyRow({required this.study});

  final CuratedStudy study;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(studyStatusProvider(study));

    return AppCard(
      radius: AppTheme.radiusMd,
      padding: const EdgeInsets.all(12),
      onTap: () => context.push('/studies/${study.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            child: SizedBox(
              width: 56,
              height: 56,
              child: StudyBanner(study: study),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  study.title,
                  style: AppTheme.displayBase,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${study.lessonCount} lessen · ±${study.minutesPerLesson} min',
                  style: AppTheme.metaLabel,
                ),
                const SizedBox(height: 3),
                if (status.completed)
                  Row(
                    children: [
                      Icon(Icons.check_circle, size: 13, color: AppTheme.positive),
                      const SizedBox(width: 4),
                      Text(
                        'Voltooid',
                        style: AppTheme.caption.copyWith(color: AppTheme.positive),
                      ),
                    ],
                  )
                else if (status.started)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SiteProgressBar(value: status.progress, height: 4),
                      const SizedBox(height: 4),
                      Text(
                        'les ${status.done + 1} van ${status.total}',
                        style: AppTheme.caption,
                      ),
                    ],
                  )
                else
                  Text(
                    study.kind ?? study.type,
                    style: AppTheme.caption.copyWith(color: AppTheme.teal),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SiteButton(
              label: status.completed
                  ? 'Opnieuw'
                  : status.started
                  ? 'Verder'
                  : 'Start',
              height: 36,
              expand: false,
              onPressed: () {
                // An unstarted study has settings to choose first, so it goes to
                // the detail screen; a started one resumes straight into the
                // lesson the server left the cursor on.
                if (!status.started) {
                  context.push('/studies/${study.id}');
                  return;
                }
                context.push('/studie/${study.id}/${status.resumeDay(study)}');
              },
            ),
          ),
        ],
      ),
    );
  }
}
