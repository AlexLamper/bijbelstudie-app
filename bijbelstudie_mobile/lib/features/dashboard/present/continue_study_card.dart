import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../studies/data/study_models.dart';
import '../../studies/present/studies_providers.dart';
import '../../studies/present/study_banner.dart';
import '../data/dashboard_models.dart';
import 'dashboard_providers.dart';

/// "Waar je gebleven was" (`RETENTION_PLAN.md` §3.2). The most recently active,
/// unfinished study: cover, title, "les X van Y", a progress bar, and a CTA
/// straight into the resume lesson.
///
/// When no study is under way, this falls back to the plain Bible reading
/// position instead of rendering nothing - the dashboard used to carry a
/// separate hero card for that, which duplicated this one; the capability
/// moved here rather than being dropped.
class ContinueStudyCard extends ConsumerWidget {
  const ContinueStudyCard({super.key, this.lastRead, required this.onContinueReading});

  /// The reader's most recent Bible chapter, or null for a brand-new account.
  final LastRead? lastRead;

  /// Opens [lastRead] (or Genesis 1 when there is none yet) in the reader.
  /// Only used while no study is under way.
  final VoidCallback onContinueReading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pick = ref.watch(continueStudyProvider);
    final scheme = Theme.of(context).colorScheme;

    if (pick == null) {
      final hasProgress = lastRead != null;
      return AppCard(
        padding: const EdgeInsets.all(14),
        onTap: onContinueReading,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconChip(
              icon: hasProgress ? Icons.menu_book_outlined : Icons.auto_stories,
              size: 56,
              iconSize: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasProgress ? 'Waar je gebleven was' : 'Begin met lezen',
                    style: AppTheme.metaLabel.copyWith(color: AppTheme.teal),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hasProgress ? lastRead!.book : 'Start je bijbelstudie',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyStrong.copyWith(
                      fontSize: 14,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasProgress
                        ? 'Hoofdstuk ${lastRead!.chapter} · ${lastRead!.version}'
                        : 'Lees dag voor dag door de Bijbel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyMuted.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: AppTheme.inkMuted),
          ],
        ),
      );
    }

    final study = pick.study;
    final total = study.lessonCount;
    final done = pick.completed.clamp(0, total);

    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => context.push('/studie/${study.id}/${pick.resumeDay}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      'Waar je gebleven was',
                      style: AppTheme.metaLabel.copyWith(color: AppTheme.teal),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      study.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyStrong.copyWith(
                        fontSize: 14,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      total > 0 ? 'Les ${pick.resumeDay} van $total' : 'Verdergaan',
                      style: AppTheme.bodyMuted.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (done / total).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: scheme.outline,
                valueColor: AlwaysStoppedAnimation(AppTheme.teal),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Verder met de les',
                style: AppTheme.caption.copyWith(
                  color: AppTheme.teal,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 3),
              Icon(Icons.arrow_forward, size: 13, color: AppTheme.teal),
            ],
          ),
        ],
      ),
    );
  }
}

/// The quiet "vandaag nog niet gedaan" chip (§3.3). One line of encouraging
/// copy, no urgency styling; taps through to the resume target; vanishes the
/// instant a completion is recorded.
class NotDoneTodayChip extends ConsumerWidget {
  const NotDoneTodayChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nudge = ref.watch(homeNudgeProvider);
    if (nudge == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => context.push(nudge.route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wb_twilight_outlined, size: 15, color: AppTheme.inkMuted),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    nudge.message,
                    style: AppTheme.caption.copyWith(color: scheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The study [ContinueStudyCard] renders, or null. Derived from cached
/// providers only (§3): no new repository code.
final continueStudyProvider = Provider.autoDispose<ContinuePick?>((ref) {
  final studies = ref.watch(curatedStudiesProvider).value ?? const <CuratedStudy>[];
  if (studies.isEmpty) return null;

  ContinuePick? best;
  DateTime bestActivity = DateTime.fromMillisecondsSinceEpoch(0);

  for (final study in studies) {
    final status = ref.watch(studyStatusProvider(study));
    if (status.completed) continue;
    if (!status.started) continue;
    final activity = status.enrollment?.lastActivityAt ??
        status.enrollment?.startedAt ??
        DateTime.fromMillisecondsSinceEpoch(1);
    if (best == null || activity.isAfter(bestActivity)) {
      best = ContinuePick(
        study: study,
        resumeDay: status.resumeDay(study),
        completed: status.done,
      );
      bestActivity = activity;
    }
  }
  return best;
});

class ContinuePick {
  const ContinuePick({
    required this.study,
    required this.resumeDay,
    required this.completed,
  });

  final CuratedStudy study;
  final int resumeDay;
  final int completed;
}
