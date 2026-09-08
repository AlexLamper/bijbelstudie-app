import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/notifications/retention_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../dashboard/present/widgets/streak_ring.dart';
import '../../../levensboom/domain/catalog.dart';
import '../../../levensboom/domain/tree_state.dart';
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
///
/// The sections settle in from the top down, the tree growing its newest tips
/// as they do, so the page reads as something that just happened rather than
/// a report of it. All of that is off when motion is reduced.
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
    AppTheme.dependOn(context);
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
    final total = lesson.lessonsTotal;
    final progressAfter = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final progressBefore = total == 0 || alreadyCounted
        ? progressAfter
        : ((done - 1) / total).clamp(0.0, 1.0);

    final next = summary.nextLessonDay ?? lesson.nextLessonDay;
    final nextEntry = next == null
        ? null
        : lesson.outline.where((entry) => entry.day == next).firstOrNull;
    final studyRoute = '/studies/${lesson.studyId}';
    final nextRoute = next == null ? null : '/studie/${lesson.studyId}/$next';

    final tree = ref.watch(treeStateProvider).value;
    final hasTree = tree != null && !tree.disabled && tree.seed.isNotEmpty;
    final still =
        tree?.reducedMotion == true ||
        MediaQuery.maybeDisableAnimationsOf(context) == true;

    // The streak as it stands after this lesson. The retention store mirrored
    // the completion before this card was built and adopts the server's count
    // once the bump comes back; the tree state carries the server's count as
    // fetched before the lesson. The higher of the two is the fresher, and
    // neither runs ahead of the truth by more than the lesson just finished.
    final streak = math.max(
      ref.watch(retentionStoreProvider).localStreak,
      tree?.streak ?? 0,
    );

    final eyebrow = studyDone
        ? 'Studie afgerond'
        : repeat
        ? 'Les ${lesson.day} van ${lesson.lessonsTotal} opnieuw gelezen'
        : 'Les ${lesson.day} van ${lesson.lessonsTotal} afgerond';
    final accent = studyDone ? AppTheme.flame : AppTheme.teal;
    final accentText = studyDone ? AppTheme.flame : AppTheme.tealStrong;

    final sections = <Widget>[
      // The reader's own tree, as it stands now that this lesson's XP has
      // reached it, and the growth that XP was.
      if (hasTree)
        _LevensboomHero(
          tree: tree,
          summary: summary,
          repeat: repeat,
          still: still,
        ),

      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Glow(
            accent: accent,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            studyDone
                                ? Icons.celebration
                                : Icons.check_circle,
                            size: 18,
                            color: accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              eyebrow,
                              style: AppTheme.eyebrow.copyWith(
                                color: accentText,
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
                        studyDone
                            ? '${lesson.title} · ${lesson.passage.reference}'
                            : '${lesson.studyTitle} · ${lesson.passage.reference}',
                        style: AppTheme.caption,
                      ),
                    ],
                  ),
                ),
                // The same mark the dashboard header carries the streak in,
                // so the number here is recognisably the one there.
                if (streak > 0) ...[
                  const SizedBox(width: 12),
                  _StreakMark(streak: streak, tree: tree),
                ],
              ],
            ),
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
        ],
      ),

      Padding(
        padding: const EdgeInsets.only(top: 20),
        child: StatStrip(
          // What was read is the line the figures are about. A passage
          // reference is too long to be a figure itself - "Handelingen der
          // Apostelen 28" shrunk into a third of the strip is unreadable - so
          // it heads the strip at heading size and wraps instead.
          header: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(Icons.menu_book_outlined, size: 20, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${lesson.passage.reference} gelezen',
                  style: AppTheme.displaySmall,
                  softWrap: true,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          items: [
            StatItem(
              value: !repeat && summary.xpAwarded > 0
                  ? '+${summary.xpAwarded}'
                  : '—',
              label: repeat ? 'Telde al mee' : 'XP verdiend',
              icon: Icons.bolt,
            ),
            if (quizScore != null && quizTotal != null)
              StatItem(
                value: '$quizScore/$quizTotal',
                label: quizScoreLabel(quizScore!, quizTotal!),
                icon: Icons.quiz_outlined,
              ),
            StatItem(
              value: formatStudyMinutes(lesson.estimatedMinutes),
              label: 'Leestijd',
              icon: Icons.schedule,
            ),
          ],
        ),
      ),

      Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Voortgang in deze studie',
                    style: AppTheme.metaLabel,
                  ),
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
            // This lesson's share of the study, filled in rather than found
            // full - the same growth the bar under the tree shows for the XP.
            TweenAnimationBuilder<double>(
              tween: Tween(
                begin: still ? progressAfter : progressBefore,
                end: progressAfter,
              ),
              duration: still
                  ? Duration.zero
                  : const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => SiteProgressBar(
                value: value,
                color: studyDone ? AppTheme.flame : null,
              ),
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
          ],
        ),
      ),

      if (summary.noteId != null)
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: AppCard(
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
        ),

      if (nextEntry != null && nextRoute != null)
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: AppCard(
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
        ),

      Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
        ),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        for (var i = 0; i < sections.length; i++)
          _Entrance(
            order: i,
            animate: !still,
            // The tree comes toward the reader; everything under it rises.
            scale: i == 0 && hasTree,
            child: sections[i],
          ),
      ],
    );
  }
}

/// The tree at the end of a lesson, and what the lesson did to it.
///
/// The XP grant has already reached the tree state through the animation bus by
/// the time this builds, so the tree drawn is the result; the bar underneath
/// shows how far the level stood before and how much this lesson added. When
/// the lesson grew the tree, its outermost tips grow in over the first second
/// - the same reveal the level-up sequence uses for the new wood - so the
/// change is seen happening rather than found done.
class _LevensboomHero extends StatelessWidget {
  const _LevensboomHero({
    required this.tree,
    required this.summary,
    required this.repeat,
    required this.still,
  });

  final TreeState tree;
  final CompletionSummary summary;
  final bool repeat;
  final bool still;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
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
      headline = 'Je voortgang';
      detail = 'Niveau ${tree.level} · ${tree.stage.name}';
    }

    final growIn = grew && !still;

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
                    'Je voortgang, niveau ${tree.level}, ${tree.stage.name}',
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: growIn ? 0.84 : 1.0, end: 1.0),
                        duration: growIn
                            ? const Duration(milliseconds: 1400)
                            : Duration.zero,
                        curve: Curves.easeOutCubic,
                        builder: (context, reveal, _) => TreeView(
                          seed: tree.seed,
                          level: tree.level,
                          frac: tree.progress,
                          health: tree.health,
                          species: tree.avatar.species,
                          scene: tree.avatar.scene,
                          animal: tree.avatar.animal,
                          reveal: reveal,
                          reducedMotion: still,
                        ),
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

/// The reader's streak, in the mark the dashboard header carries it in: the
/// tree at header size with the count in its corner badge, or the plain count
/// pill when the tree is switched off, with what the number counts underneath.
class _StreakMark extends StatelessWidget {
  const _StreakMark({required this.streak, required this.tree});

  final int streak;

  /// Null before the first fetch lands; [StreakRing] stands a sapling in.
  final TreeState? tree;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return SizedBox(
      width: 84,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreakRing(
            streak: streak,
            hasFreeze: (tree?.freezes ?? 0) > 0,
            tree: tree,
            size: 52,
          ),
          const SizedBox(height: 6),
          // The ring's own semantics already say "reeks van N dagen".
          ExcludeSemantics(
            child: Text(
              streak == 1 ? 'dag op rij' : 'dagen op rij',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption.copyWith(
                color: AppTheme.inkFaint,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft wash of the accent behind the headline - enough to lift it off the
/// page the way the level-up sequence lights its tree, not enough to read as
/// a box. Painted past the headline's own bounds so it has no visible edge.
class _Glow extends StatelessWidget {
  const _Glow({required this.accent, required this.child});

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -20,
          right: 48,
          top: -28,
          bottom: -20,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.7, -0.1),
                  radius: 0.95,
                  colors: [
                    accent.withValues(alpha: 0.18),
                    accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Fade-and-rise entrance, staggered by [order] so the page settles from the
/// tree down rather than appearing all at once - the level-up sequence's
/// ease-out push, at a fraction of the distance. With [scale] the child comes
/// forward a hair instead of rising. Off when motion is reduced: the child is
/// simply there.
class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.order,
    required this.animate,
    required this.child,
    this.scale = false,
  });

  final int order;
  final bool animate;
  final bool scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    final start = math.min(order * 0.1, 0.55);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1000),
      curve: Interval(
        start,
        math.min(start + 0.45, 1),
        curve: Curves.easeOutCubic,
      ),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: scale
            ? Transform.scale(scale: 0.96 + 0.04 * t, child: child)
            : Transform.translate(
                offset: Offset(0, 14 * (1 - t)),
                child: child,
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
