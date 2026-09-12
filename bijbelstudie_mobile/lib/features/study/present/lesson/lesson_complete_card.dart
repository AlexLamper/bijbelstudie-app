import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/notifications/retention_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../levensboom/domain/catalog.dart';
import '../../../levensboom/domain/tree_state.dart';
import '../../../levensboom/present/levensboom_avatar.dart';
import '../../../levensboom/present/levensboom_providers.dart';
import '../../../levensboom/present/tree_view.dart';
import '../../../profile/domain/profile_stats.dart' show BadgeCatalog;
import '../../domain/lesson_models.dart';

/// The Dutch label for a raw badge id straight from `xp.newBadges` /
/// `xp.badges` (`CompletionSummary.fromJson`).
///
/// The server hands back ids (`lib/gamification.ts`), not display text - the
/// same ids [BadgeCatalog] already knows how to name for the badges screen.
/// An id this build does not recognise still gets a plain Dutch line rather
/// than the id itself: a coded string on a celebration screen would only add
/// to a reader's doubt about whether the achievement is real.
String _newBadgeLabel(String id) =>
    BadgeCatalog.serverBadges[id]?.label ?? 'Nieuwe badge';

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
    this.onClose,
    this.onOpenAssistant,
  });

  final LessonPayload lesson;
  final CompletionSummary summary;
  final int? quizScore;
  final int? quizTotal;

  /// Leaves the lesson. The finished state has no top bar of its own - the
  /// hero runs to the top of the screen - so the close sits on the hero.
  final VoidCallback? onClose;

  /// Opens the AI assistant, kept reachable from the finished state because
  /// the top bar that used to carry it is gone.
  final VoidCallback? onOpenAssistant;

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
    final accentText = studyDone ? AppTheme.flame : AppTheme.tealStrong;

    // Where the tree's level bar stands now, and where it stood before this
    // lesson's XP landed. Exact while the level held; after a level-up the new
    // level started from nothing, so the bar is all growth.
    final gained = repeat ? 0 : summary.xpAwarded;
    final grew = gained > 0;
    final levelledUp = grew && summary.levelledUp;
    final unlocked = levelledUp && tree != null
        ? itemsUnlockedAtLevel(tree.level)
        : const <CatalogItem>[];

    final headline = _headline(
      tree: tree,
      hasTree: hasTree,
      studyDone: studyDone,
      repeat: repeat,
      levelledUp: levelledUp,
      grew: grew,
      studyTitle: lesson.studyTitle,
      lessonTitle: lesson.title,
    );

    final detail = StringBuffer(
      '${lesson.passage.reference} gelezen in '
      '${formatStudyMinutes(lesson.estimatedMinutes)}.',
    );
    if (hasTree && !repeat) {
      detail.write(
        ' Nog ${tree.xpToNextLevel} XP tot niveau ${tree.level + 1}.',
      );
    }
    if (unlocked.isNotEmpty) {
      detail.write(
        ' Nieuw ontgrendeld: ${unlocked.map((i) => i.name).join(', ')}.',
      );
    }

    final sections = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(
          children: [
            Text(
              eyebrow.toUpperCase(),
              textAlign: TextAlign.center,
              style: AppTheme.groupLabel.copyWith(
                fontSize: 11.5,
                color: accentText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: AppTheme.screenTitle.copyWith(fontSize: 27, height: 1.2),
            ),
            const SizedBox(height: 8),
            Text(
              detail.toString(),
              textAlign: TextAlign.center,
              style: AppTheme.bodyMuted.copyWith(height: 1.55),
            ),
          ],
        ),
      ),

      // Three (or four) figures between two rules: what this lesson earned,
      // the streak it kept alive, and where it leaves the study.
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: AppTheme.rule),
              bottom: BorderSide(color: AppTheme.rule),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Figure(
                  value: grew ? '+$gained' : '—',
                  label: repeat ? 'telde al mee' : 'XP',
                  color: accentText,
                ),
                if (quizScore != null && quizTotal != null)
                  _Figure(
                    value: '$quizScore/$quizTotal',
                    label: quizScoreLabel(quizScore!, quizTotal!),
                    divided: true,
                  ),
                if (streak > 0)
                  _Figure(
                    value: '$streak',
                    label: streak == 1 ? 'dag op rij' : 'dagen op rij',
                    divided: true,
                  ),
                _Figure(
                  value: '${(progressAfter * 100).round()}%',
                  label: 'van ${lesson.studyTitle}',
                  divided: true,
                ),
              ],
            ),
          ),
        ),
      ),

      // Everything below is state the mock does not show but the screen still
      // has to be able to say: badges earned, the reflection that was saved,
      // and what the next lesson actually is.
      if (summary.levelledUp || summary.newBadges.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (summary.levelledUp) SiteBadge.vermilion('Nieuw niveau'),
              for (final badge in summary.newBadges)
                SiteBadge.teal(_newBadgeLabel(badge)),
            ],
          ),
        ),

      if (remaining > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Text(
            remaining == 1
                ? 'Nog één les te gaan'
                : 'Nog $remaining lessen te gaan',
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
          ),
        ),

      if (summary.noteId != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
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
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
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
    ];

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (hasTree)
                _Entrance(
                  order: 0,
                  animate: !still,
                  // The tree comes toward the reader; everything under it rises.
                  scale: true,
                  child: _LevensboomHero(
                    tree: tree,
                    summary: summary,
                    repeat: repeat,
                    still: still,
                    onClose: onClose,
                    onOpenAssistant: onOpenAssistant,
                  ),
                ),
              for (var i = 0; i < sections.length; i++)
                _Entrance(
                  order: hasTree ? i + 1 : i,
                  animate: !still,
                  child: sections[i],
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (nextRoute != null)
                  SiteButton(
                    label: 'Verder met les $next',
                    height: 50,
                    onPressed: () => context.replace(nextRoute),
                  )
                else
                  SiteButton(
                    label: 'Terug naar de studie',
                    height: 50,
                    onPressed: () => context.go(studyRoute),
                  ),
                const SizedBox(height: 10),
                Semantics(
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.go(studyRoute),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Voor nu genoeg',
                        textAlign: TextAlign.center,
                        style: AppTheme.bodyStrong.copyWith(
                          color: AppTheme.inkMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The one line that says what just happened. The tree is the subject
  /// whenever there is one and it grew; otherwise the lesson is.
  static String _headline({
    required TreeState? tree,
    required bool hasTree,
    required bool studyDone,
    required bool repeat,
    required bool levelledUp,
    required bool grew,
    required String studyTitle,
    required String lessonTitle,
  }) {
    // The eyebrow above already says "Studie afgerond", so the headline is
    // the thing that was finished.
    if (studyDone) return studyTitle;
    if (!hasTree) return lessonTitle;
    if (repeat) return 'Deze les telde al mee';
    if (levelledUp) return 'Je boom groeide naar niveau ${tree!.level}';
    if (grew) return 'Je boom groeide';
    return 'Je voortgang';
  }
}

/// One column of the figure strip.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.label,
    this.color,
    this.divided = false,
  });

  final String value;
  final String label;
  final Color? color;

  /// Every column but the first carries the rule that separates it.
  final bool divided;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        decoration: divided
            ? BoxDecoration(
                border: Border(left: BorderSide(color: AppTheme.rule)),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: AppTheme.statNumber.copyWith(
                fontSize: 21,
                color: color ?? AppTheme.ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tree at the end of a lesson, full width and 300 tall.
///
/// The XP grant has already reached the tree state through the animation bus
/// by the time this builds, so the tree drawn is the result. When the lesson
/// grew the tree, its outermost tips grow in over the first second - the same
/// reveal the level-up sequence uses for the new wood - so the change is seen
/// happening rather than found done.
///
/// It used to be a bordered card inset in the page with a headline and an XP
/// bar under it. Run to the edges instead, the tree is the screen, and the
/// numbers it was captioned with read better as the figure strip below.
class _LevensboomHero extends StatelessWidget {
  const _LevensboomHero({
    required this.tree,
    required this.summary,
    required this.repeat,
    required this.still,
    this.onClose,
    this.onOpenAssistant,
  });

  final TreeState tree;
  final CompletionSummary summary;
  final bool repeat;
  final bool still;
  final VoidCallback? onClose;
  final VoidCallback? onOpenAssistant;

  static const double _height = 300;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    // kGoldRing rather than the design's #CA9A16: the same gold already rings
    // the avatar on Profiel and Mijn voortgang, and two golds a tab apart is
    // worse than one that is a shade off.
    final gold = tree.avatar.ring == TreeRing.goud;
    final accent = gold ? kGoldRing : AppTheme.teal;

    final gained = repeat ? 0 : summary.xpAwarded;
    final growIn = gained > 0 && !still;

    return SizedBox(
      height: _height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: AppTheme.tealSoft),
          Semantics(
            image: true,
            label: 'Je voortgang, niveau ${tree.level}, ${tree.stage.name}',
            child: GestureDetector(
              // The same place the profile avatar leads: the tree in full.
              onTap: () => context.push('/profile/boom'),
              child: TweenAnimationBuilder<double>(
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
            ),
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: Row(
              children: [
                _Pill(text: 'Niveau ${tree.level}', background: accent),
                const SizedBox(width: 8),
                _Pill(
                  text: tree.stage.name,
                  background: const Color(0x8C111827),
                ),
              ],
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  if (onClose != null)
                    _HeroButton(
                      icon: Icons.close,
                      label: 'Les sluiten',
                      onTap: onClose!,
                    ),
                  const Spacer(),
                  if (onOpenAssistant != null)
                    _HeroButton(
                      icon: Icons.auto_awesome,
                      label: 'AI-assistent',
                      onTap: onOpenAssistant!,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A control floating over the tree: a translucent white disc, so it reads on
/// a painted scene without a border of its own.
class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: AppTheme.lightInkSoft),
        ),
      ),
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
