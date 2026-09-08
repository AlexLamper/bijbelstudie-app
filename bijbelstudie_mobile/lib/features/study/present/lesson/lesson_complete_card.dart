import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../levensboom/domain/catalog.dart';
import '../../../levensboom/present/levensboom_avatar.dart';
import '../../../levensboom/present/levensboom_providers.dart';
import '../../../levensboom/present/tree_view.dart';
import '../../domain/lesson_models.dart';

/// What a finished lesson looks like: what it did to the reader's tree, what
/// it earned, and the way on.
///
/// Rendered in place of the step body rather than as a dialog - finishing is
/// part of the lesson, and a modal over it reads as an interruption of
/// something that is actually over. The level-up dialog is the one exception,
/// and the shell fires that, not this card: the card shows the tree as it now
/// stands and what this lesson added, and leaves the celebrating to it.
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

    // False when the ledger already held this lesson: read again, or finished
    // once before with the response lost. Nothing was earned this time either
    // way, and the card must not pretend otherwise.
    final repeat = !summary.recorded;

    // The ledger already held this lesson when `recorded` is false, so the
    // count must not be inflated by one for a lesson being redone.
    final alreadyCounted = lesson.outline
        .where((entry) => entry.completed)
        .any((entry) => entry.day == lesson.day);
    final done =
        lesson.outline.where((entry) => entry.completed).length +
        (alreadyCounted ? 0 : 1);
    final remaining = (lesson.lessonsTotal - done).clamp(
      0,
      lesson.lessonsTotal,
    );

    final next = summary.nextLessonDay ?? lesson.nextLessonDay;
    final nextEntry = next == null
        ? null
        : lesson.outline.where((entry) => entry.day == next).firstOrNull;
    final studyRoute = '/studies/${lesson.studyId}';
    final nextRoute = next == null ? null : '/studie/${lesson.studyId}/$next';

    final eyebrow = studyDone
        ? 'Studie afgerond'
        : repeat
        ? 'Les ${lesson.day} van ${lesson.lessonsTotal} opnieuw gelezen'
        : 'Les ${lesson.day} van ${lesson.lessonsTotal} afgerond';
    final accent = studyDone ? AppTheme.flame : AppTheme.teal;
    final accentText = studyDone ? AppTheme.flame : AppTheme.tealStrong;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        // The reader's own tree, as it stands now that this lesson's XP has
        // reached it, and the growth that XP was.
        _LevensboomHero(summary: summary, repeat: repeat),

        Row(
          children: [
            Icon(
              studyDone ? Icons.celebration : Icons.check_circle,
              size: 18,
              color: accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                eyebrow,
                style: AppTheme.eyebrow.copyWith(color: accentText),
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
          studyDone
              ? '${lesson.title} · ${lesson.passage.reference}'
              : '${lesson.studyTitle} · ${lesson.passage.reference}',
          style: AppTheme.caption,
        ),

        if (summary.levelledUp || summary.newBadges.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (summary.levelledUp) SiteBadge.vermilion('Nieuw niveau'),
              for (final badge in summary.newBadges) SiteBadge.teal(badge),
            ],
          ),
        ],

        const SizedBox(height: 20),
        StatStrip(
          items: [
            StatItem(
              value: !repeat && summary.xpAwarded > 0
                  ? '+${summary.xpAwarded}'
                  : '—',
              label: repeat ? 'Telde al mee' : 'XP verdiend',
              icon: Icons.bolt,
            ),
            // Without a quiz the honest second figure is what was read, not a
            // score of zero.
            if (quizScore != null && quizTotal != null)
              StatItem(
                value: '$quizScore/$quizTotal',
                label: quizScoreLabel(quizScore!, quizTotal!),
                icon: Icons.quiz_outlined,
              )
            else
              StatItem(
                value: lesson.passage.reference,
                label: 'Gelezen',
                icon: Icons.menu_book_outlined,
              ),
            StatItem(
              value: formatStudyMinutes(lesson.estimatedMinutes),
              label: 'Leestijd',
              icon: Icons.schedule,
            ),
          ],
        ),

        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text('Voortgang in deze studie', style: AppTheme.metaLabel),
            ),
            Text(
              '$done van ${lesson.lessonsTotal}',
              style: AppTheme.caption.copyWith(
                color: AppTheme.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SiteProgressBar(
          value: lesson.lessonsTotal == 0 ? 0 : done / lesson.lessonsTotal,
          color: studyDone ? AppTheme.flame : null,
        ),
        const SizedBox(height: 6),
        Text(
          remaining == 0
              ? 'Alle lessen afgerond'
              : remaining == 1
              ? 'Nog één les te gaan'
              : 'Nog $remaining lessen te gaan',
          style: AppTheme.caption,
        ),

        if (summary.noteId != null) ...[
          const SizedBox(height: 18),
          AppCard(
            color: AppTheme.tealTint,
            borderColor: AppTheme.teal,
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            onTap: () => context.go('/notes'),
            child: Row(
              children: [
                Icon(
                  Icons.edit_note_outlined,
                  size: 18,
                  color: AppTheme.tealStrong,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Je reflectie is bewaard als notitie',
                    style: AppTheme.bodyStrong.copyWith(
                      color: AppTheme.tealStrong,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: AppTheme.tealStrong),
              ],
            ),
          ),
        ],

        if (nextEntry != null && nextRoute != null) ...[
          const SizedBox(height: 18),
          AppCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            onTap: () => context.replace(nextRoute),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hierna · les $next', style: AppTheme.metaLabel),
                      const SizedBox(height: 4),
                      Text(nextEntry.title, style: AppTheme.bodyStrong),
                      Text(nextEntry.reference, style: AppTheme.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 20, color: AppTheme.inkFaint),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),
        if (nextRoute != null)
          SiteButton(
            label: 'Verder met les $next',
            trailingIcon: Icons.arrow_forward,
            onPressed: () => context.replace(nextRoute),
          )
        else
          SiteButton(
            label: 'Terug naar de studie',
            trailingIcon: Icons.arrow_forward,
            onPressed: () => context.go(studyRoute),
          ),
        const SizedBox(height: 8),
        SiteOutlineButton(
          label: 'Overzicht',
          onPressed: () => context.go(studyRoute),
        ),
      ],
    );
  }
}

/// The tree at the end of a lesson, and what the lesson did to it.
///
/// The XP grant has already reached the tree state through the animation bus by
/// the time this builds, so the tree drawn is the result; the bar underneath
/// shows how far the level stood before and how much this lesson added. Nothing
/// when the reader has no tree to show - state not loaded, or switched off.
class _LevensboomHero extends ConsumerWidget {
  const _LevensboomHero({required this.summary, required this.repeat});

  final CompletionSummary summary;
  final bool repeat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(treeStateProvider).value;
    if (tree == null || tree.disabled || tree.seed.isEmpty) {
      return const SizedBox.shrink();
    }

    final still =
        tree.reducedMotion ||
        MediaQuery.maybeDisableAnimationsOf(context) == true;
    final gold = tree.avatar.ring == TreeRing.goud;
    final accent = gold ? kGoldRing : AppTheme.teal;

    final gained = repeat ? 0 : summary.xpAwarded;
    final grew = gained > 0;
    final levelledUp = grew && summary.levelledUp;
    final unlocked = levelledUp
        ? itemsUnlockedAtLevel(tree.level)
        : const <CatalogItem>[];

    // Where the level's bar stood before this lesson's XP landed. Exact while
    // the level held; after a level-up the new level started from nothing, so
    // the bar is all growth.
    final span = tree.xpForNextLevel > 0 ? tree.xpForNextLevel : 1;
    final before = levelledUp
        ? 0.0
        : ((tree.xpIntoLevel - gained) / span).clamp(0.0, 1.0);
    final after = tree.progress.clamp(0.0, 1.0);

    final String headline;
    final String detail;
    final toNext =
        'nog ${tree.xpToNextLevel} XP tot niveau ${tree.level + 1}';
    if (repeat) {
      headline = 'Deze les telde al mee';
      detail = 'Je boom groeide er de eerste keer al van.';
    } else if (levelledUp) {
      headline = 'Je boom groeide naar niveau ${tree.level}';
      detail = '${tree.stage.name} · $toNext';
    } else if (grew) {
      headline = 'Je boom groeide';
      detail = 'Niveau ${tree.level} · $toNext';
    } else {
      headline = 'Je levensboom';
      detail = 'Niveau ${tree.level} · ${tree.stage.name}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Material(
        color: AppTheme.paperRaised,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          side: BorderSide(
            color: accent.withValues(alpha: gold ? 0.9 : 0.35),
            width: 1.5,
          ),
        ),
        child: InkWell(
          // The same place the profile avatar leads: the tree in full.
          onTap: () => context.push('/profile/boom'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                image: true,
                label:
                    'Je levensboom, niveau ${tree.level}, ${tree.stage.name}',
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TreeView(
                        seed: tree.seed,
                        level: tree.level,
                        frac: tree.progress,
                        health: tree.health,
                        species: tree.avatar.species,
                        scene: tree.avatar.scene,
                        animal: tree.avatar.animal,
                        reducedMotion: still,
                      ),
                      Positioned(
                        left: 12,
                        bottom: 10,
                        child: Row(
                          children: [
                            _Pill(
                              text: 'Niveau ${tree.level}',
                              background: accent,
                            ),
                            const SizedBox(width: 6),
                            _Pill(
                              text: tree.stage.name,
                              background: Colors.black.withValues(alpha: 0.45),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          levelledUp ? Icons.auto_awesome : Icons.eco,
                          size: 18,
                          color: accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(headline, style: AppTheme.bodyStrong),
                        ),
                        if (grew) ...[
                          const SizedBox(width: 8),
                          _XpChip(text: '+$gained XP'),
                        ],
                      ],
                    ),
                    if (grew) ...[
                      const SizedBox(height: 12),
                      _GrowthBar(
                        before: before,
                        after: after,
                        accent: accent,
                        animate: !still,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(detail, style: AppTheme.caption),
                    if (unlocked.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Nieuw ontgrendeld: ${unlocked.map((i) => i.name).join(', ')}',
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.tealStrong,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The level's XP bar with this lesson's share told apart: what stood before
/// in a muted accent, what was just added in the full one - grown in, unless
/// motion is reduced.
class _GrowthBar extends StatelessWidget {
  const _GrowthBar({
    required this.before,
    required this.after,
    required this.accent,
    required this.animate,
  });

  final double before;
  final double after;
  final Color accent;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final muted = Color.alphaBlend(
      accent.withValues(alpha: 0.45),
      AppTheme.paperRaised,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: animate ? before : after, end: after),
      duration: animate ? const Duration(milliseconds: 900) : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: SizedBox(
          height: 8,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: AppTheme.rule)),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: width * value,
                    child: ColoredBox(color: accent),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: width * before,
                    child: ColoredBox(color: muted),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _XpChip extends StatelessWidget {
  const _XpChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.tealTint,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        text,
        style: AppTheme.metaLabel.copyWith(color: AppTheme.tealStrong),
      ),
    );
  }
}

/// A label over the tree image. White on its own colour, never on a theme
/// surface, so it reads the same over the painted scene in both modes.
class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.background});

  final String text;
  final Color background;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      constraints: const BoxConstraints(maxWidth: 200),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
