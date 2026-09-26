import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/server_image.dart';
import '../../studies/data/study_models.dart';
import '../../studies/present/studies_providers.dart';
import '../../studies/present/study_banner.dart';
import '../data/dashboard_models.dart';
import '../data/resume_models.dart';
import 'resume_providers.dart';

/// "Verder waar je gebleven was" (DAILY_HABIT_PLAN.md §3): the one card that
/// answers where the reader is, first on the Start tab.
///
/// Renders the server's `resume` answer - the same object the website's card
/// renders - so web and app never disagree. A server that predates `resume`
/// gets [buildLocalResume] instead: the most recently active unfinished study
/// (`continueStudyProvider`), else the last chapter read, else the start
/// prompt - what this card always chose, now in the shared layout.
class ContinueStudyCard extends ConsumerWidget {
  const ContinueStudyCard({
    super.key,
    this.resume,
    this.lastRead,
    this.readChapters = const {},
    this.onOpen,
  });

  /// The server's answer; null from an older server.
  final DashboardResume? resume;

  /// The reader's most recent chapter, for the fallback. Null for a new account.
  final LastRead? lastRead;

  /// For the fallback chapter's "12 van 50 hoofdstukken".
  final Map<String, List<int>> readChapters;

  /// Overrides navigation (tests). Defaults to [openResumeHref].
  final void Function(String href)? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = watchResume(
      ref,
      server: resume,
      lastRead: lastRead,
      readChapters: readChapters,
    );
    final catalogue = ref.watch(curatedStudiesProvider).value ?? const <CuratedStudy>[];

    Widget? coverFor(ResumeItem item) {
      if (item.kind != ResumeKind.study) return null;
      for (final study in catalogue) {
        if (study.id == item.studyId) return StudyBanner(study: study);
      }
      final url = item.imageUrl;
      if (url == null) return null;
      return ServerImage(imagePath: url, fallback: const _PaintedCover());
    }

    return ResumeCardView(
      resume: shown,
      cover: coverFor(shown.primary),
      onOpen: onOpen ?? (href) => openResumeHref(context, ref, href),
    );
  }
}

/// The card itself, free of providers so it can be tested on fixed data.
///
/// Laid out as `components/dashboard/ResumeCard.tsx` on the website: eyebrow
/// and schedule chip, title, subtitle, then either "Vandaag gedaan" or the
/// step bar, the lesson bar with its count, one full-width teal button, and
/// the other running studies under "Ook bezig met".
class ResumeCardView extends StatelessWidget {
  const ResumeCardView({
    super.key,
    required this.resume,
    required this.onOpen,
    this.cover,
  });

  final DashboardResume resume;
  final void Function(String href) onOpen;

  /// The study's banner, square-cropped. Null for chapters and starts.
  final Widget? cover;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final item = resume.primary;
    final step = item.step;
    final progress = item.kind == ResumeKind.start ? null : item.progress;
    final schedule = item.doneToday ? null : item.schedule;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cover != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  child: SizedBox.square(dimension: 56, child: cover),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.kind == ResumeKind.start
                                ? 'Begin waar je wilt'
                                : 'Verder waar je gebleven was',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.metaLabel.copyWith(color: AppTheme.teal),
                          ),
                        ),
                        if (schedule != null) ...[
                          const SizedBox(width: 8),
                          schedule.isBehind
                              ? SiteBadge.neutral(schedule.label)
                              : SiteBadge.teal(schedule.label),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.displayTitle.copyWith(
                        fontSize: 18,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (item.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.caption.copyWith(fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          if (item.doneToday) ...[
            const SizedBox(height: 14),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Vandaag gedaan',
                    style: TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w600),
                  ),
                  if (item.nextLabel != null) TextSpan(text: ' · ${item.nextLabel}'),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption.copyWith(fontSize: 13),
            ),
          ] else if (step != null) ...[
            const SizedBox(height: 14),
            _StepBar(count: step.count, index: step.index),
            const SizedBox(height: 7),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Stap ${step.index} van ${step.count} · '),
                  TextSpan(
                    text: step.label,
                    style: TextStyle(color: AppTheme.inkSoft, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption.copyWith(fontSize: 13),
            ),
          ],

          if (progress != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: SiteProgressBar(value: progress.fraction, height: 4)),
                const SizedBox(width: 12),
                Text(
                  item.kind == ResumeKind.study
                      ? '${progress.done} van ${progress.total} lessen'
                      : '${progress.done} van ${progress.total} gelezen',
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.inkFaint,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          SiteButton(label: item.cta, onPressed: () => onOpen(item.href)),

          if (item.kind == ResumeKind.start) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => onOpen('/lezen'),
                child: Text(
                  'Of begin met lezen',
                  style: AppTheme.bodyStrong.copyWith(fontSize: 13.5, color: AppTheme.inkSoft),
                ),
              ),
            ),
          ],

          if (resume.others.isNotEmpty) ...[
            const SizedBox(height: 16),
            const RuleLine(),
            const SizedBox(height: 12),
            Text('Ook bezig met', style: AppTheme.metaLabel),
            const SizedBox(height: 2),
            for (var i = 0; i < resume.others.length; i++) ...[
              if (i > 0) const RuleLine(),
              _OtherRow(
                item: resume.others[i],
                onTap: () => onOpen(resume.others[i].href),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// One segment per step of this lesson (six, or five without a context step):
/// finished steps teal, the current one a lighter teal, the rest the rule.
class _StepBar extends StatelessWidget {
  const _StepBar({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final segments = count.clamp(1, 12);
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 1; i <= segments; i++) ...[
            if (i > 1) const SizedBox(width: 4),
            Expanded(
              child: Container(
                key: ValueKey('resume-step-$i'),
                height: 6,
                decoration: BoxDecoration(
                  color: i < index
                      ? AppTheme.teal
                      : i == index
                      ? AppTheme.teal.withValues(alpha: 0.45)
                      : AppTheme.rule,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One other running study: title, subtitle, a short bar and a chevron.
class _OtherRow extends StatelessWidget {
  const _OtherRow({required this.item, required this.onTap});

  final ResumeItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyStrong.copyWith(color: scheme.onSurface),
                    ),
                    if (item.subtitle != null)
                      Text(
                        item.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.caption,
                      ),
                  ],
                ),
              ),
              if (item.progress != null) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 64,
                  child: SiteProgressBar(value: item.progress!.fraction, height: 4),
                ),
              ],
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 18, color: AppTheme.teal),
            ],
          ),
        ),
      ),
    );
  }
}

/// The banner ground without a picture, for a cover URL that fails to load.
class _PaintedCover extends StatelessWidget {
  const _PaintedCover();

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.tealStrong, AppTheme.bannerEnd],
        ),
      ),
    );
  }
}
