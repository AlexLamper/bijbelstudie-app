import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/study_models.dart';
import '../data/study_plan_store.dart';
import 'studies_providers.dart';
import 'study_banner.dart';

/// `/studies` on www.bijbel-studie.com - the guided studies, with the site's
/// type filter.
class StudiesScreen extends ConsumerStatefulWidget {
  const StudiesScreen({super.key});

  @override
  ConsumerState<StudiesScreen> createState() => _StudiesScreenState();
}

class _StudiesScreenState extends ConsumerState<StudiesScreen> {
  /// `FILTERS` in `app/studies/page.tsx`.
  static const _filters = ['Alle', 'Persoon', 'Gedeelte', 'Onderwerp', 'Boek'];
  String _filter = 'Alle';

  @override
  Widget build(BuildContext context) {
    final studies = ref.watch(curatedStudiesProvider);
    final plans = ref.watch(studyPlansProvider);
    final serverLessons =
        ref.watch(serverStudyLessonsProvider).value ??
        const <String, Set<int>>{};
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(bottom: BorderSide(color: scheme.outline)),
              ),
              child: const GradientHeader(
                title: 'Studies',
                subtitle:
                    'Begeleide studies door de Bijbel. Kies er een, stel je '
                    'ritme in en werk hem les voor les af.',
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppTheme.teal,
                onRefresh: () async {
                  ref.invalidate(curatedStudiesProvider);
                  ref.invalidate(serverStudyLessonsProvider);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  children: [
                    SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _filters.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final label = _filters[index];
                          final active = _filter == label;
                          return _FilterChip(
                            label: label,
                            active: active,
                            onTap: () => setState(() => _filter = label),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    studies.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: AppLoader(),
                      ),
                      error: (error, _) => AppEmptyState(
                        icon: Icons.wifi_off_outlined,
                        title: 'Studies niet geladen',
                        description: '$error',
                      ),
                      data: (list) {
                        final filtered = _filter == 'Alle'
                            ? list
                            : list.where((s) => s.type == _filter).toList();
                        if (filtered.isEmpty) {
                          return const AppEmptyState(
                            icon: Icons.search_off,
                            title: 'Geen studies',
                            description:
                                'Er zijn geen studies in deze categorie.',
                          );
                        }
                        return Column(
                          children: [
                            for (final study in filtered) ...[
                              _StudyCard(
                                study: study,
                                plan: plans[study.id],
                                completedDays: mergedCompletedDays(
                                  studyId: study.id,
                                  plans: plans,
                                  serverLessons: serverLessons,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppTheme.teal : scheme.surface,
          border: Border.all(color: active ? AppTheme.teal : scheme.outline),
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        ),
        child: Text(
          label,
          style: AppTheme.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// `StudyCard` in `app/studies/page.tsx`, rewritten to answer the question the
/// website's card leaves open: what is this study actually about, and what will
/// I be reading?
///
/// The site card shows a banner, a title, a one-line description and an
/// expander full of lessons. On a phone that reads as a picture with a Start
/// button, so the three facts that decide whether a study is worth beginning -
/// what kind of study it is, which part of the Bible it walks through, and how
/// much of it there is - are on the face of the card now. Start no longer drops
/// the reader straight into a chapter either: the card opens `/studies/:id`,
/// where the study is configured first.
class _StudyCard extends ConsumerWidget {
  const _StudyCard({
    required this.study,
    required this.plan,
    required this.completedDays,
  });

  final CuratedStudy study;
  final StudyPlan? plan;
  final Set<int> completedDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final total = study.lessonCount;
    final done = completedDays.length;
    final finished = total > 0 && done >= total;
    final started = plan?.started ?? done > 0;
    final next = _nextLesson();

    return Opacity(
      opacity: finished ? 0.55 : 1,
      child: _buildCard(
        context,
        scheme: scheme,
        total: total,
        done: done,
        finished: finished,
        started: started,
        next: next,
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required ColorScheme scheme,
    required int total,
    required int done,
    required bool finished,
    required bool started,
    required StudyLesson? next,
  }) {
    return AppCard(
      radius: AppTheme.radiusMd,
      padding: EdgeInsets.zero,
      clip: true,
      // The ripple needs its own Material above the card's fill, or it paints
      // on the Scaffold underneath and never shows.
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/studies/${study.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 6,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    StudyBanner(study: study),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _BannerPill(label: study.type),
                    ),
                    if (finished)
                      const Positioned(
                        top: 8,
                        right: 8,
                        child: _BannerPill(
                          label: 'Voltooid',
                          icon: Icons.check_circle,
                        ),
                      )
                    else if (started)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _BannerPill(label: '$done van $total'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      study.title,
                      style: AppTheme.displayBase.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      study.typeSummary,
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.teal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      study.description,
                      style: AppTheme.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MetaChip(
                          icon: Icons.list_alt_outlined,
                          label: total == 1 ? '1 les' : '$total lessen',
                        ),
                        _MetaChip(
                          icon: Icons.menu_book_outlined,
                          label: study.scopeLabel,
                        ),
                        _MetaChip(
                          icon: Icons.schedule,
                          label: 'ca. ${study.estimatedMinutes} min',
                        ),
                      ],
                    ),
                    if (next != null) ...[
                      const SizedBox(height: 12),
                      Eyebrow(started ? 'Volgende les' : 'Je begint bij'),
                      const SizedBox(height: 4),
                      Text(
                        '${next.title} - ${next.reference}',
                        style: AppTheme.bodyStrong.copyWith(
                          fontSize: 13,
                          color: scheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        next.focus,
                        style: AppTheme.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (started && total > 0) ...[
                      const SizedBox(height: 12),
                      SiteProgressBar(value: done / total),
                    ],
                    const SizedBox(height: 14),
                    SiteButton(
                      label: finished
                          ? 'Studie bekijken'
                          : started
                          ? 'Verder met de studie'
                          : 'Bekijk en start studie',
                      height: 40,
                      trailingIcon: Icons.arrow_forward,
                      onPressed: () => context.push('/studies/${study.id}'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The lowest-numbered lesson still to do, or the first lesson for a study
  /// that has not been started. Null only when the study has no lessons.
  StudyLesson? _nextLesson() {
    for (final lesson in study.lessons) {
      if (!completedDays.contains(lesson.day)) return lesson;
    }
    return study.firstLesson;
  }
}

/// The translucent pill that sits on the banner, matching the site's badge.
class _BannerPill extends StatelessWidget {
  const _BannerPill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.teal.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 9, color: Colors.white),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: AppTheme.overline.copyWith(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppTheme.inkMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTheme.caption.copyWith(
              fontSize: 11,
              color: AppTheme.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
