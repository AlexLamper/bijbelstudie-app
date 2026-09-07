import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/skeleton.dart';
import 'levensboom_celebration.dart';
import 'levensboom_providers.dart';
import 'tree_view.dart';

/// The tree at the top of Profiel, and the way in to `/profile/boom`.
///
/// Also the surface that owes the celebration: it fires here when the account's
/// level has outrun `lastSeenLevel`, which covers both a level-up earned in
/// this session and one earned on the website since the last open.
///
/// Renders nothing at all when the reader has switched the tree off — XP,
/// levels and badges keep accruing either way, so the toggle is purely visual.
class LevensboomHero extends ConsumerStatefulWidget {
  const LevensboomHero({super.key});

  @override
  ConsumerState<LevensboomHero> createState() => _LevensboomHeroState();
}

class _LevensboomHeroState extends ConsumerState<LevensboomHero> {
  /// Guards against a rebuild pushing a second dialog while the first is up.
  bool _celebrating = false;

  void _maybeCelebrate() {
    if (_celebrating) return;
    final tree = ref.read(treeStateProvider).value;
    final pending = ref.read(pendingLevelUpProvider);
    if (tree == null || pending == null) return;

    _celebrating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showLevensboomCelebration(
        context,
        ref,
        seed: tree.seed,
        level: pending,
        reducedMotion: tree.reducedMotion,
      );
      _celebrating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(treeStateProvider);
    ref.listen(pendingLevelUpProvider, (_, next) {
      if (next != null) _maybeCelebrate();
    });

    final tree = treeAsync.value;
    if (treeAsync.isLoading && tree == null) {
      return const Skeleton(height: 190, radius: 16);
    }
    if (tree == null || tree.disabled) return const SizedBox.shrink();

    _maybeCelebrate();

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      onTap: () => context.push('/profile/boom'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: SizedBox(
          height: 190,
          child: Stack(
            fit: StackFit.expand,
            children: [
              TreeView(
                seed: tree.seed,
                level: tree.level,
                frac: tree.progress,
                health: tree.health,
                reducedMotion: tree.reducedMotion,
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 26, 14, 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x8C000000)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'MIJN BOOM',
                                  style: AppTheme.caption.copyWith(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                    fontSize: 10,
                                  ),
                                ),
                                Text(
                                  'Niveau ${tree.level}',
                                  style: AppTheme.metaLabel.copyWith(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            tree.wilting
                                ? '${tree.daysSinceActive} dagen niet gelezen'
                                : 'nog ${tree.xpToNextLevel} XP',
                            style: AppTheme.caption.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                        child: LinearProgressIndicator(
                          value: tree.progress.clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: Colors.white24,
                          color: AppTheme.teal,
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
    );
  }
}
