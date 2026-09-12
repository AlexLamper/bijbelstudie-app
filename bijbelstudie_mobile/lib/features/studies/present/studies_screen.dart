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
/// One primary action, then browsing. The page opens on the study already
/// under way - "verder waar je was" - and only below that offers what is new
/// and what else exists. The old page led with three competing filter controls
/// and buried the resume affordance in a list of seventy-seven rows.
///
/// Everything filters over the loaded catalogue - the search field included -
/// so no interaction here costs a request.
class StudiesScreen extends ConsumerStatefulWidget {
  const StudiesScreen({super.key});

  @override
  ConsumerState<StudiesScreen> createState() => _StudiesScreenState();
}

class _StudiesScreenState extends ConsumerState<StudiesScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final studies = ref.watch(curatedStudiesProvider);

    return Scaffold(
      backgroundColor: AppTheme.surface,
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
              SliverToBoxAdapter(child: _Header(controller: _searchController)),
              ...studies.when(
                loading: () => const [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 40),
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
  /// Searching collapses the whole page to results: the resume row, the
  /// carousel and the sections are ways of browsing, and browsing aids are
  /// noise once the reader has told you what they want.
  List<Widget> _slivers(List<CuratedStudy> all) {
    final query = ref.watch(studiesQueryProvider).trim().toLowerCase();
    final filter = ref.watch(studiesFilterProvider);

    if (query.isNotEmpty) {
      final hits = all.where((study) => _matches(study, query)).toList(growable: false);
      return [
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 40),
          sliver: hits.isEmpty
              ? const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                    child: AppEmptyState(
                      icon: Icons.search_off,
                      title: 'Niets gevonden',
                      description:
                          'Probeer de naam van een bijbelboek, een persoon of een thema.',
                    ),
                  ),
                )
              : SliverList.builder(
                  itemCount: hits.length,
                  itemBuilder: (context, index) => _StudyRow(study: hits[index]),
                ),
        ),
      ];
    }

    final continueStudy = ref.watch(continueStudyProvider);
    final filtered = all.where((study) => _inFilter(study, filter)).toList(growable: false);
    final featured = _featured(all);

    return [
      const SliverToBoxAdapter(child: _FilterRow()),
      if (continueStudy != null)
        SliverToBoxAdapter(child: _ContinueRow(study: continueStudy)),
      if (featured.isNotEmpty)
        SliverToBoxAdapter(child: _NewThisMonth(studies: featured)),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(_sectionTitle(filter), style: AppTheme.displayTitle),
              ),
              Semantics(
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.push('/studies/boeken'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Per bijbelboek',
                        style: AppTheme.pillLabel.copyWith(color: AppTheme.teal),
                      ),
                      const SizedBox(width: 5),
                      Icon(Icons.chevron_right, size: 14, color: AppTheme.teal),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.only(bottom: 40),
        sliver: filtered.isEmpty
            ? SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _emptyFilter(filter),
                ),
              )
            : SliverList.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) => _StudyRow(study: filtered[index]),
              ),
      ),
    ];
  }

  Widget _emptyFilter(StudiesFilter filter) {
    return switch (filter) {
      StudiesFilter.mine => AppEmptyState(
        icon: Icons.school_outlined,
        title: 'Nog geen studie begonnen',
        description:
            'Kies een studie bij Voor jou en begin. Je voortgang komt hier te staan.',
        action: SiteButton(
          label: 'Studies ontdekken',
          expand: false,
          onPressed: () =>
              ref.read(studiesFilterProvider.notifier).select(StudiesFilter.forYou),
        ),
      ),
      StudiesFilter.completed => const AppEmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'Nog niets afgerond',
        description: 'Zodra je alle lessen van een studie afrondt, staat die hier.',
      ),
      _ => const AppEmptyState(
        icon: Icons.search_off,
        title: 'Geen studies',
        description: 'Geen studie past bij dit filter.',
      ),
    };
  }

  /// Whether [study] survives the chip row. The two reader chips ask the same
  /// questions the old Mijn studies / Voltooid tabs did.
  bool _inFilter(CuratedStudy study, StudiesFilter filter) {
    switch (filter) {
      case StudiesFilter.forYou:
        return true;
      case StudiesFilter.books:
        return _category(study) == 'boeken';
      case StudiesFilter.people:
        return _category(study) == 'personen';
      case StudiesFilter.themes:
        return _category(study) == 'themas';
      case StudiesFilter.mine:
        final status = ref.watch(studyStatusProvider(study));
        return status.started && !status.completed;
      case StudiesFilter.completed:
        return ref.watch(studyStatusProvider(study)).completed;
    }
  }

  /// The chip a study belongs under. The API's `category` splits the bible
  /// books across `ot` and `nt`, which the one filter row does not - both land
  /// on the same chip. A study without a category falls back to its `type`, so
  /// the older catalogue rows still sort somewhere.
  static String _category(CuratedStudy study) => switch (study.category) {
    'ot' || 'nt' => 'boeken',
    'personen' => 'personen',
    'themas' => 'themas',
    _ => switch (study.type) {
      'Boek' => 'boeken',
      'Persoon' => 'personen',
      _ => 'themas',
    },
  };

  /// The authored studies: the only ones with real artwork and a written
  /// introduction, so they are what a large card can actually fill.
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

  static String _sectionTitle(StudiesFilter filter) => switch (filter) {
    StudiesFilter.forYou => 'Alle studies',
    StudiesFilter.mine => 'Mijn studies',
    StudiesFilter.completed => 'Afgerond',
    _ => filter.label,
  };
}

/// Title, catalogue size and the search field, on white over a hairline.
class _Header extends ConsumerWidget {
  const _Header({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final total = ref.watch(curatedStudiesProvider).value?.length ?? 0;
    final started = ref.watch(startedStudyCountProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text('Studies', style: AppTheme.screenTitle),
          ),
          const SizedBox(height: 2),
          Text(
            '$total studies · $started begonnen',
            style: AppTheme.caption.copyWith(fontSize: 12.5, color: AppTheme.inkFaint),
          ),
          const SizedBox(height: 14),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppTheme.paperSunken,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 17, color: AppTheme.inkMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.search,
                    style: AppTheme.bodyMuted.copyWith(color: AppTheme.ink),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      filled: false,
                      hintText: 'Bijbelboek, persoon of thema',
                      hintStyle: AppTheme.bodyMuted,
                    ),
                    onChanged: (value) =>
                        ref.read(studiesQueryProvider.notifier).set(value),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The single chip row. One filter at a time; the list below refreshes in
/// place rather than scrolling back to the top.
class _FilterRow extends ConsumerWidget {
  const _FilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final active = ref.watch(studiesFilterProvider);

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.rule)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            for (final filter in StudiesFilter.values) ...[
              if (filter != StudiesFilter.values.first) const SizedBox(width: 8),
              AppFilterPill(
                label: filter.label,
                selected: filter == active,
                onTap: () => ref.read(studiesFilterProvider.notifier).select(filter),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Verder waar je was": the one primary action on the page.
///
/// The ring is the study's progress drawn around its own banner, so the row
/// answers "how far am I" without a second line of text.
class _ContinueRow extends ConsumerWidget {
  const _ContinueRow({required this.study});

  final CuratedStudy study;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final status = ref.watch(studyStatusProvider(study));
    final day = status.resumeDay(study);

    void open() => context.push('/studie/${study.id}/$day');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.rule)),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 46,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.square(
                  dimension: 46,
                  child: CircularProgressIndicator(
                    value: status.progress,
                    strokeWidth: 5,
                    backgroundColor: AppTheme.rule,
                    valueColor: AlwaysStoppedAnimation(AppTheme.teal),
                  ),
                ),
                ClipOval(
                  child: SizedBox.square(
                    dimension: 36,
                    child: StudyBanner(study: study),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('VERDER WAAR JE WAS', style: AppTheme.metaLabel),
                const SizedBox(height: 3),
                Text(
                  '${study.title} · les $day',
                  style: AppTheme.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: open,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                decoration: BoxDecoration(
                  color: AppTheme.teal,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Text(
                  'Lezen',
                  style: AppTheme.pillLabel.copyWith(
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The featured strip: banner, title and one meta line, swiped horizontally.
class _NewThisMonth extends StatelessWidget {
  const _NewThisMonth({required this.studies});

  final List<CuratedStudy> studies;

  static const double _cardWidth = 196;
  static const double _bannerHeight = 112;

  /// The card is a fixed height shared by the banner and two lines of text, so
  /// a large device text-size setting is capped here; the full description is
  /// still on the detail screen.
  static const double _cardHeight = 112 + 9 + 22 + 2 + 18;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15);

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text('Nieuw deze maand', style: AppTheme.displayTitle),
                ),
                Text(
                  'Alle ${studies.length}',
                  style: AppTheme.pillLabel.copyWith(color: AppTheme.teal),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SizedBox(
              height: _cardHeight,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: scaler),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: studies.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final study = studies[index];
                    return SizedBox(
                      width: _cardWidth,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => context.push('/studies/${study.id}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: SizedBox(
                                height: _bannerHeight,
                                width: double.infinity,
                                child: StudyBanner(study: study),
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              study.title,
                              style: AppTheme.displayBase.copyWith(fontSize: 14.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${study.lessonCount} lessen · ±${study.minutesPerLesson} min',
                              style: AppTheme.caption.copyWith(
                                color: AppTheme.inkFaint,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One study as an edge-to-edge row under a hairline: thumbnail, title, one
/// meta line, and the action as a teal text link rather than a filled button.
///
/// The meta line is where YouVersion puts a star rating. There is no rating in
/// this data - and inventing one would be a lie about other readers - so it
/// carries the facts that actually help a reader choose.
class _StudyRow extends ConsumerWidget {
  const _StudyRow({required this.study});

  final CuratedStudy study;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final status = ref.watch(studyStatusProvider(study));

    final meta = [
      study.kind ?? study.type,
      '${study.lessonCount} lessen',
      if (!status.started) '±${study.minutesPerLesson} min',
    ].join(' · ');

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // An unstarted study has settings to choose first, so it goes to the
          // detail screen; a started one resumes straight into the lesson the
          // server left the cursor on.
          if (!status.started) {
            context.push('/studies/${study.id}');
            return;
          }
          context.push('/studie/${study.id}/${status.resumeDay(study)}');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.paperSunken)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox.square(
                  dimension: 44,
                  child: StudyBanner(study: study),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      study.title,
                      style: AppTheme.bodyStrong.copyWith(fontSize: 14.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (status.started && !status.completed) ...[
                      const SizedBox(height: 7),
                      FractionallySizedBox(
                        widthFactor: 0.78,
                        alignment: Alignment.centerLeft,
                        child: SiteProgressBar(value: status.progress, height: 4),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                status.completed
                    ? 'Opnieuw'
                    : status.started
                    ? 'Verder'
                    : 'Start',
                style: AppTheme.pillLabel.copyWith(color: AppTheme.teal),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
