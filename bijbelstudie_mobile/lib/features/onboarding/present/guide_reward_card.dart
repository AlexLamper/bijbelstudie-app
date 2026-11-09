import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../progress_tree/domain/growth.dart';
import '../../progress_tree/present/progress_tree_providers.dart';
import '../../progress_tree/present/tree_view.dart';
import '../domain/guide_machine.dart';

/// The end of the guide: the reader's tree grows by what the guide earned.
///
/// The XP is the server's (`POST /onboarding/guide`, once per account), and it
/// reaches the tree through the usual animation bus, so the tree drawn here is
/// the result and grows into it from where it stood when the guide began -
/// the guide's own note XP included. The figure is only shown once the
/// server has confirmed it: a replay, an offline finish or an account that
/// already had it simply see their tree.
class GuideRewardCard extends ConsumerStatefulWidget {
  const GuideRewardCard({
    super.key,
    required this.guide,
    required this.onDone,
    this.reducedMotion = false,
  });

  final GuideState guide;
  final VoidCallback onDone;
  final bool reducedMotion;

  @override
  ConsumerState<GuideRewardCard> createState() => _GuideRewardCardState();
}

class _GuideRewardCardState extends ConsumerState<GuideRewardCard> {
  /// Where the tree stood before the guide, captured the first time both ends
  /// are known so a later grant does not replay the growth.
  TreeFrom? _from;
  int? _fromXp;

  void _captureFrom(int xpNow) {
    if (_from != null) return;
    final paid = widget.guide.rewardXp ?? 0;
    final before = widget.guide.startXp ?? (xpNow - paid);
    if (before >= xpNow) return;
    final safe = math.max(0, before);
    final level = levelForXp(safe);
    _fromXp = safe;
    _from = TreeFrom(level: level, frac: positionForXp(safe) - level);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final tree = ref.watch(treeStateProvider).value;
    final guide = widget.guide;
    if (tree != null && !guide.rewardLoading) _captureFrom(tree.xp);
    final gained = _fromXp != null && tree != null ? tree.xp - _fromXp! : null;
    final shownXp = guide.rewardXp != null ? math.max(guide.rewardXp!, gained ?? 0) : null;

    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 210,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: AppTheme.tealSoft),
                if (tree != null && !tree.disabled)
                  Semantics(
                    image: true,
                    label: 'Je boom, niveau ${tree.level}',
                    child: TreeView(
                      // Keyed on the start point, so the growth plays once the
                      // grant has landed rather than before it.
                      key: ValueKey('guide-tree-${_from?.level}-${_from?.frac}'),
                      seed: tree.seed,
                      level: tree.level,
                      frac: tree.progress,
                      floor: tree.floor,
                      from: _from,
                      health: tree.health,
                      species: tree.avatar.species,
                      scene: tree.avatar.scene,
                      animal: tree.avatar.animal,
                      reducedMotion: widget.reducedMotion || tree.reducedMotion,
                    ),
                  )
                else
                  Center(
                    child: Icon(Icons.park_outlined, size: 56, color: AppTheme.teal),
                  ),
                if (shownXp != null && shownXp > 0)
                  Positioned(
                    left: 14,
                    bottom: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.teal,
                        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      ),
                      child: Text(
                        '+$shownXp XP',
                        style: AppTheme.pillLabel.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Klaar! Je boom groeit mee', style: AppTheme.displaySmall),
                const SizedBox(height: 8),
                Text(
                  'Alles wat je leest, markeert en vraagt laat je boom groeien. '
                  'Onder Profiel zie je hoe hij erbij staat.',
                  style: AppTheme.bodyMuted.copyWith(height: 1.5),
                ),
                const SizedBox(height: 16),
                SiteButton(
                  label: 'Verder lezen',
                  trailingIcon: Icons.arrow_forward,
                  onPressed: widget.onDone,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
