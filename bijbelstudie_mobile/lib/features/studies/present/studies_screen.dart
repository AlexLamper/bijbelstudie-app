import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../bible/present/bible_providers.dart';
import '../data/studies_repository.dart';
import '../data/study_models.dart';
import 'studies_providers.dart';

/// `/studies` on www.bijbel-studie.com — the guided studies, with the site's
/// type filter, plus the leesplannen the dashboard links to.
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
    final plans = ref.watch(biblePlansProvider(null));
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
                subtitle: 'Begeleide studies en leesplannen door de Bijbel.',
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppTheme.teal,
                onRefresh: () async {
                  ref.invalidate(curatedStudiesProvider);
                  ref.invalidate(biblePlansProvider);
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
                            description: 'Er zijn geen studies in deze categorie.',
                          );
                        }
                        return Column(
                          children: [
                            for (final study in filtered) ...[
                              _StudyCard(study: study),
                              const SizedBox(height: 12),
                            ],
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 12),
                    Text('LEESPLANNEN', style: AppTheme.eyebrow),
                    const SizedBox(height: 10),
                    plans.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: AppLoader(size: 22),
                      ),
                      error: (_, __) => Text(
                        'Leesplannen konden niet worden geladen.',
                        style: AppTheme.bodyMuted,
                      ),
                      data: (list) => list.isEmpty
                          ? Text(
                              'Er zijn nog geen leesplannen beschikbaar.',
                              style: AppTheme.bodyMuted,
                            )
                          : Column(
                              children: [
                                for (final plan in list) ...[
                                  _PlanCard(plan: plan),
                                  const SizedBox(height: 12),
                                ],
                              ],
                            ),
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

/// `StudyCard` — image with a type badge, title, description, duration, a
/// Start button and a collapsible lesson list.
class _StudyCard extends ConsumerStatefulWidget {
  const _StudyCard({required this.study});

  final CuratedStudy study;

  @override
  ConsumerState<_StudyCard> createState() => _StudyCardState();
}

class _StudyCardState extends ConsumerState<_StudyCard> {
  bool _open = false;

  void _start(StudyLesson lesson) {
    ref
        .read(readerLocationProvider.notifier)
        .openChapter(
          versionId: widget.study.startVersion,
          book: lesson.book,
          chapter: lesson.chapter,
        );
    context.go('/study');
  }

  @override
  Widget build(BuildContext context) {
    final study = widget.study;
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      radius: AppTheme.radiusMd,
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (study.image.isNotEmpty)
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 6,
                  child: Image.network(
                    study.image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppTheme.teal.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.teal.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    ),
                    child: Text(
                      study.type,
                      style: AppTheme.overline.copyWith(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  study.title,
                  style: AppTheme.displayBase.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: 4),
                Text(study.description, style: AppTheme.caption),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 11, color: AppTheme.inkFaint),
                    const SizedBox(width: 4),
                    Text(study.durationLabel, style: AppTheme.overline.copyWith(letterSpacing: 0)),
                    const Spacer(),
                    SiteButton(
                      label: 'Start',
                      expand: false,
                      height: 32,
                      trailingIcon: Icons.arrow_forward,
                      onPressed: study.lessons.isEmpty
                          ? null
                          : () => _start(study.lessons.first),
                    ),
                  ],
                ),
                if (study.lessons.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => setState(() => _open = !_open),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Text(
                            _open ? 'Verberg lessen' : '${study.lessons.length} lessen',
                            style: AppTheme.caption.copyWith(
                              color: AppTheme.teal,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Icon(
                            _open ? Icons.expand_less : Icons.expand_more,
                            size: 15,
                            color: AppTheme.teal,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_open)
                    for (final lesson in study.lessons)
                      InkWell(
                        onTap: () => _start(lesson),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 22,
                                child: Text(
                                  '${lesson.day}',
                                  style: AppTheme.caption.copyWith(
                                    color: AppTheme.inkFaint,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      lesson.title,
                                      style: AppTheme.bodyStrong.copyWith(
                                        fontSize: 13,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                    Text(lesson.reference, style: AppTheme.caption),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: AppTheme.inkFaint,
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends ConsumerStatefulWidget {
  const _PlanCard({required this.plan});

  final BiblePlan plan;

  @override
  ConsumerState<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends ConsumerState<_PlanCard> {
  bool _busy = false;

  Future<void> _toggleEnrollment() async {
    setState(() => _busy = true);
    final repo = ref.read(studiesRepositoryProvider);

    String? failure;
    if (widget.plan.isEnrolled) {
      await repo.unenroll(widget.plan.id);
    } else {
      failure = await repo.enroll(widget.plan.id);
    }

    if (!mounted) return;
    setState(() => _busy = false);

    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure)));
      return;
    }
    ref.invalidate(biblePlansProvider);
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      radius: AppTheme.radiusMd,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconChip(icon: Icons.event_available_outlined, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.title,
                      style: AppTheme.displayBase.copyWith(color: scheme.onSurface),
                    ),
                    Text(
                      '${plan.duration} dagen'
                      '${plan.author == null ? '' : ' · ${plan.author}'}',
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(plan.description, style: AppTheme.bodyMuted),
          if (plan.isEnrolled) ...[
            const SizedBox(height: 12),
            SiteProgressBar(value: plan.progressPercentage / 100),
            const SizedBox(height: 6),
            Text(
              'Dag ${plan.completedDays.length} van ${plan.duration} · '
              '${plan.progressPercentage}%',
              style: AppTheme.caption,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (plan.isEnrolled)
                SiteOutlineButton(
                  label: 'Verlaten',
                  expand: false,
                  height: 36,
                  onPressed: _busy ? null : _toggleEnrollment,
                )
              else
                SiteButton(
                  label: 'Meedoen',
                  expand: false,
                  height: 36,
                  loading: _busy,
                  onPressed: _busy ? null : _toggleEnrollment,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
