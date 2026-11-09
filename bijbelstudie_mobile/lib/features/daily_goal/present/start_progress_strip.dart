import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../progress_tree/present/progress_tree_avatar.dart' show kGoldLevelBadge;
import '../../progress_tree/present/progress_tree_celebration.dart';
import '../../progress_tree/present/progress_tree_providers.dart';
import 'daily_goal_providers.dart';
import 'daily_goal_ring.dart';
import 'daily_goal_sheet.dart';

/// Start's progress row, at the top of the column: today's goal as a ring on the
/// left, the level with its XP bar on the right, and - only while the tree
/// droops - one line that says so.
///
/// Compact on purpose (the tekst van de dag below it must stay in view), and
/// the two places a reader's progress becomes visible every day:
///
/// - the ring fills as the reading clock counts (daily_goal_providers.dart),
///   and turns gold with a short burst the first time Start sees it reached;
/// - the level and XP were off screen until now; here they are, and an owed
///   level-up is celebrated from here too (the same dialog as Profiel's).
class StartProgressStrip extends ConsumerStatefulWidget {
  const StartProgressStrip({super.key});

  @override
  ConsumerState<StartProgressStrip> createState() => _StartProgressStripState();
}

class _StartProgressStripState extends ConsumerState<StartProgressStrip> {
  bool _burst = false;
  bool _showReached = false;
  Timer? _hideReached;
  bool _celebratingLevel = false;

  @override
  void dispose() {
    _hideReached?.cancel();
    super.dispose();
  }

  void _maybeCelebrateGoal(DailyGoalState state) {
    if (!state.owesCelebration || _burst) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _burst = true;
        _showReached = true;
      });
      unawaited(HapticFeedback.lightImpact().catchError((_) {}));
      unawaited(ref.read(dailyGoalProvider.notifier).markCelebrated());
      _hideReached = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _showReached = false);
      });
    });
  }

  void _maybeCelebrateLevel(int? pending) {
    if (pending == null || _celebratingLevel) return;
    final tree = ref.read(treeStateProvider).value;
    if (tree == null) return;
    _celebratingLevel = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showProgressTreeCelebration(
        context,
        ref,
        seed: tree.seed,
        level: pending,
        avatar: tree.avatar,
        reducedMotion: tree.reducedMotion,
        tree: tree,
      );
      _celebratingLevel = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final goalState = ref.watch(dailyGoalProvider);
    final tree = ref.watch(treeStateProvider).value;
    _maybeCelebrateGoal(goalState);
    ref.listen(pendingLevelUpProvider, (_, next) => _maybeCelebrateLevel(next));
    _maybeCelebrateLevel(ref.read(pendingLevelUpProvider));

    final p = goalState.progress;
    final thirsty = tree != null && !tree.disabled && tree.wilting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: scheme.outline),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // ── Today's goal ───────────────────────────────────────
                Expanded(
                  child: _Half(
                    semantics: p.reached
                        ? 'Dagdoel gehaald, ${p.minutes} minuten'
                        : 'Dagdoel: ${p.minutesRead} van ${p.minutes} minuten gelezen',
                    onTap: () => showDailyGoalSheet(context),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 40,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              DailyGoalRing(
                                progress: p.progress,
                                size: 40,
                                stroke: 4.5,
                                child: Text(
                                  '${p.minutesRead}',
                                  style: AppTheme.bodyStrong.copyWith(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    height: 1,
                                  ),
                                ),
                              ),
                              Positioned(
                                left: -20,
                                top: -20,
                                child: GoalBurst(size: 80, play: _burst),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                p.reached ? 'Gehaald' : '${p.minutesRead} / ${p.minutes} min',
                                style: AppTheme.bodyStrong.copyWith(fontWeight: FontWeight.w700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                goalState.goal.chosen || p.reached ? 'Dagdoel' : 'Kies je dagdoel',
                                style: AppTheme.caption,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                VerticalDivider(width: 1, thickness: 1, indent: 10, endIndent: 10, color: scheme.outline),
                // ── Level and XP ───────────────────────────────────────
                Expanded(
                  child: _Half(
                    semantics: tree == null
                        ? 'Niveau'
                        : 'Niveau ${tree.level}, ${tree.xpIntoLevel} van ${tree.xpForNextLevel} XP',
                    onTap: () => context.push('/profile/boom'),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: kGoldLevelBadge, shape: BoxShape.circle),
                          child: Text(
                            tree == null ? '' : '${tree.level}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2B1E02),
                              height: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                tree == null ? 'Niveau' : 'Niveau ${tree.level}',
                                style: AppTheme.bodyStrong.copyWith(fontWeight: FontWeight.w700),
                                maxLines: 1,
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(end: (tree?.progress ?? 0).clamp(0.0, 1.0)),
                                  duration: const Duration(milliseconds: 700),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, v, _) => LinearProgressIndicator(
                                    value: v,
                                    minHeight: 4,
                                    backgroundColor: scheme.outline,
                                    color: AppTheme.teal,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                tree == null ? ' ' : '${tree.xpIntoLevel} / ${tree.xpForNextLevel} XP',
                                style: AppTheme.caption.copyWith(fontSize: 11),
                                maxLines: 1,
                              ),
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
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _showReached
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _Notice(
                    icon: Icons.emoji_events_outlined,
                    color: kGoldLevelBadge,
                    text: 'Dagdoel gehaald. +10 XP voor je boom.',
                  ),
                )
              : thirsty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _Notice(
                        icon: Icons.water_drop_outlined,
                        color: AppTheme.teal,
                        text: 'Je boom heeft dorst. Lees even, dan knapt hij op.',
                        onTap: () => context.push('/profile/boom'),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _Half extends StatelessWidget {
  const _Half({required this.child, required this.onTap, required this.semantics});

  final Widget child;
  final VoidCallback onTap;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: child,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text, this.onTap});

  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: AppTheme.caption.copyWith(color: AppTheme.inkSoft)),
            ),
          ],
        ),
      ),
    );
  }
}
