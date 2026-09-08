import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/catalog.dart';
import 'levensboom_celebration.dart';
import 'levensboom_providers.dart';
import 'tree_view.dart';

/// The gold of the Pro ring, shared by every avatar surface.
const Color kGoldRing = Color(0xFFD4A017);
const Color kGoldRingLight = Color(0xFFF6D77A);

/// The Levensboom *as* the profile picture, not as a card beside it.
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
class LevensboomAvatar extends ConsumerStatefulWidget {
  const LevensboomAvatar({
    super.key,
    required this.fallback,
    this.size = 84,
  });

  final Widget fallback;
  final double size;

  @override
  ConsumerState<LevensboomAvatar> createState() => _LevensboomAvatarState();
}

class _LevensboomAvatarState extends ConsumerState<LevensboomAvatar> {
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
        avatar: tree.avatar,
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
    if (tree == null || tree.disabled) return widget.fallback;

    _maybeCelebrate();

    final stroke = (widget.size * 0.045).clamp(3.0, 5.0);
    final badge = widget.size * 0.32;
    final gold = tree.avatar.ring == TreeRing.goud;
    final ringColor = gold ? kGoldRing : AppTheme.teal;

    return GestureDetector(
      onTap: () => context.push('/profile/boom'),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          children: [
            // The XP bar, bent around the picture.
            Positioned.fill(
              child: CircularProgressIndicator(
                value: tree.progress.clamp(0.0, 1.0),
                strokeWidth: stroke,
                strokeCap: StrokeCap.round,
                backgroundColor: gold ? kGoldRing.withValues(alpha: 0.18) : AppTheme.rule,
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
            // bottom-right corner.
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                constraints: BoxConstraints(minWidth: badge),
                height: badge,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ringColor,
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
                child: Text(
                  '${tree.level}',
                  style: AppTheme.metaLabel.copyWith(
                    color: Colors.white,
                    fontSize: badge * 0.5,
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
