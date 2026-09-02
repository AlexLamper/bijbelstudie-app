import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../domain/lesson_models.dart';

/// What a finished lesson looks like: what it earned, and the way on.
///
/// Rendered in place of the step body rather than as a dialog - finishing is
/// part of the lesson, and a modal over it reads as an interruption of
/// something that is actually over.
class LessonCompleteCard extends ConsumerWidget {
  const LessonCompleteCard({
    super.key,
    required this.lesson,
    required this.summary,
    this.quizScore,
    this.quizTotal,
  });

  final LessonPayload lesson;
  final CompletionSummary summary;
  final int? quizScore;
  final int? quizTotal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studyDone = summary.studyCompleted;

    // The ledger already held this lesson when `recorded` is false, so the
    // count must not be inflated by one for a lesson being redone.
    final alreadyCounted = lesson.outline
        .where((entry) => entry.completed)
        .any((entry) => entry.day == lesson.day);
    final done = lesson.outline.where((entry) => entry.completed).length +
        (alreadyCounted ? 0 : 1);
    final remaining = (lesson.lessonsTotal - done).clamp(0, lesson.lessonsTotal);

    final next = summary.nextLessonDay ?? lesson.nextLessonDay;
    final nextEntry = next == null
        ? null
        : lesson.outline.where((entry) => entry.day == next).firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Row(
          children: [
            Icon(
              studyDone ? Icons.celebration : Icons.check_circle,
              size: 20,
              color: studyDone ? AppTheme.flame : AppTheme.teal,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                studyDone
                    ? 'Studie afgerond'
                    : 'Les ${lesson.day} van ${lesson.lessonsTotal} afgerond',
                style: AppTheme.eyebrow.copyWith(
                  color: studyDone ? AppTheme.flame : AppTheme.tealStrong,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          studyDone ? lesson.studyTitle : lesson.title,
          style: AppTheme.displayMedium,
        ),
        const SizedBox(height: 4),
        Text(
          '${lesson.studyTitle} · ${lesson.passage.reference}',
          style: AppTheme.caption,
        ),

        if (summary.levelledUp || summary.newBadges.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (summary.levelledUp) SiteBadge.vermilion('Nieuw level'),
              for (final badge in summary.newBadges) SiteBadge.teal(badge),
            ],
          ),
        ],

        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _Stat(
                value: summary.xpAwarded > 0 ? '+${summary.xpAwarded}' : '—',
                label: 'XP verdiend',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              // Without a quiz the honest second figure is what was read, not
              // a score of zero.
              child: quizScore != null && quizTotal != null
                  ? _Stat(
                      value: '$quizScore/$quizTotal',
                      label: quizScoreLabel(quizScore!, quizTotal!),
                    )
                  : _Stat(
                      value: lesson.passage.reference,
                      label: 'Gelezen',
                    ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Stat(
                value: '${lesson.estimatedMinutes} min',
                label: 'Leestijd',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Stat(
                value: '$done/${lesson.lessonsTotal}',
                label: remaining == 0 ? 'Alle lessen af' : 'Nog $remaining te gaan',
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),
        Text('Voortgang in deze studie', style: AppTheme.metaLabel),
        const SizedBox(height: 8),
        SiteProgressBar(
          value: lesson.lessonsTotal == 0 ? 0 : done / lesson.lessonsTotal,
        ),

        if (summary.noteId != null) ...[
          const SizedBox(height: 18),
          AppCard(
            color: AppTheme.tealTint,
            borderColor: AppTheme.teal,
            onTap: () => context.go('/notes'),
            child: Row(
              children: [
                Icon(Icons.edit_note_outlined, size: 16, color: AppTheme.tealStrong),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Je reflectie is bewaard als notitie',
                    style: AppTheme.bodyStrong.copyWith(color: AppTheme.tealStrong),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: AppTheme.tealStrong),
              ],
            ),
          ),
        ],

        if (nextEntry != null) ...[
          const SizedBox(height: 18),
          const SectionHeader(eyebrow: 'Hierna', title: 'De volgende les'),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nextEntry.title, style: AppTheme.bodyStrong),
                Text(nextEntry.reference, style: AppTheme.caption),
              ],
            ),
          ),
        ],

        const SizedBox(height: 22),
        if (next != null)
          SiteButton(
            label: 'Verder met les $next',
            trailingIcon: Icons.arrow_forward,
            onPressed: () => context.replace('/studie/${lesson.studyId}/$next'),
          )
        else
          SiteButton(
            label: 'Terug naar de studie',
            trailingIcon: Icons.arrow_forward,
            onPressed: () => context.go('/studies/${lesson.studyId}'),
          ),
        const SizedBox(height: 8),
        SiteOutlineButton(
          label: 'Overzicht',
          onPressed: () => context.go('/studies/${lesson.studyId}'),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: AppTheme.radiusMd,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTheme.statNumber,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTheme.metaLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
