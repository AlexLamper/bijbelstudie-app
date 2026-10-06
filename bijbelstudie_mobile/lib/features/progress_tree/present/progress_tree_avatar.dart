import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/catalog.dart';
import 'progress_tree_celebration.dart';
import 'progress_tree_providers.dart';
import 'tree_view.dart';

/// The gold of the Pro ring, shared by every avatar surface.
const Color kGoldRing = Color(0xFFD4A017);
const Color kGoldRingLight = Color(0xFFF6D77A);

/// The unfilled part of the gold ring - a warm track rather than a tinted
/// gold, so the filled arc still reads as the thing that moved.
const Color kGoldRingTrack = Color(0xFFF1E7C8);

/// The level disc under a gold ring: a shade down from the ring itself, so the
/// number sits on it without the two melting together.
const Color kGoldLevelBadge = Color(0xFFC9A23A);

/// The progress tree *as* the profile picture, not as a card beside it.
///
/// The tree fills the round frame the picture used to occupy, with the XP bar
/// bent around it as a ring and the level in the corner badge - so the one thing
/// that says "this is you" is also the thing that grows when you study. The
/// ring is the reader's pick: teal, or the Pro gold.
///
/// [fallback] stands in while the state is still loading, or when the reader has
/// switched the tree off: the plain initials/photo avatar. XP, levels and badges
/// keep accruing either way, so the toggle stays purely visual.
///
/// This is also the surface the level-up celebration fires from - it took that
/// over from the hero card it replaced, so a level-up earned on the website
/// since the last open is still celebrated once here.
class ProgressTreeAvatar extends ConsumerStatefulWidget {
  const ProgressTreeAvatar({
    super.key,
    required this.fallback,
    this.size = 84,
  });

  final Widget fallback;
  final double size;

  @override
  ConsumerState<ProgressTreeAvatar> createState() => _ProgressTreeAvatarState();
}

class _ProgressTreeAvatarState extends ConsumerState<ProgressTreeAvatar> {
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
      await showProgressTreeCelebration(
        context,
        ref,
        seed: tree.seed,
        level: pending,
        avatar: tree.avatar,
        reducedMotion: tree.reducedMotion,
        tree: tree,
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
    if (tree == null || tree.disabled) return widget.fallback;

    _maybeCelebrate();

    // 4 at the Profiel size of 96, which is where the proportions were drawn.
    final stroke = (widget.size * 0.042).clamp(3.0, 5.0);
    final badge = widget.size * 0.29;
    final gold = tree.avatar.ring == TreeRing.goud;
    final ringColor = gold ? kGoldRing : AppTheme.teal;
    final badgeColor = gold ? kGoldLevelBadge : AppTheme.tealStrong;
    final level = '${tree.level}';

    return GestureDetector(
      onTap: () => context.push('/profile/boom'),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          // The level disc hangs a little outside the ring; without this the
          // parent clips the two pixels it sticks out by.
          clipBehavior: Clip.none,
          children: [
            // The XP bar, bent around the picture.
            Positioned.fill(
              child: CircularProgressIndicator(
                value: tree.progress.clamp(0.0, 1.0),
                strokeWidth: stroke,
                strokeCap: StrokeCap.round,
                backgroundColor: gold ? kGoldRingTrack : AppTheme.rule,
                color: ringColor,
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(stroke + 2),
                child: ClipOval(
                  child: TreeView(
                    seed: tree.seed,
                    level: tree.level,
                    frac: tree.progress,
                    floor: tree.floor,
                    health: tree.health,
                    species: tree.avatar.species,
                    scene: tree.avatar.scene,
                    animal: tree.avatar.animal,
                    framing: TreeFraming.portrait,
                    reducedMotion: tree.reducedMotion,
                  ),
                ),
              ),
            ),
            // Bottom-left, because the edit control on Profiel owns the
            // bottom-right corner. It sits 2 outside the ring on both axes, so
            // the disc reads as laid on the avatar rather than cut into it.
            Positioned(
              left: -2,
              bottom: 2,
              child: Container(
                constraints: BoxConstraints(minWidth: badge),
                height: badge,
                // A circle for the one and two digits every real level has;
                // three would need a pill, and the padding gives it one.
                padding: EdgeInsets.symmetric(
                  horizontal: level.length > 2 ? 5 : 0,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2.5,
                  ),
                ),
                child: Text(
                  level,
                  style: AppTheme.bodyStrong.copyWith(
                    color: Colors.white,
                    fontSize: badge * 0.46,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
