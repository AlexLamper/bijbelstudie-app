import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/catalog.dart';
import '../domain/tree_state.dart';
import 'tree_view.dart';

/// The Levensboom at header size: the reader's own tree, small, with a count
/// badge tucked into the corner.
///
/// Deliberately a thin wrapper over [TreeView] rather than a second renderer.
/// The generator, palette, wilt handling and the studio choice all live there
/// already and are shared with the profile hero, the tab bar and the level-up
/// sequence - a badge that drew its own tree would be a second thing to keep
/// in parity with the website, for no gain.
///
/// It draws the *real* avatar - the account's level, species, scene and
/// animal - so the reader has one tree, not a header lookalike grown by a
/// different number. The badge is what carries the streak or the week goal.
class MiniTree extends StatelessWidget {
  const MiniTree({
    super.key,
    required this.tree,
    required this.badge,
    required this.semanticsLabel,
    this.dormant = false,
    this.hasFreeze = false,
    this.size = 48,
  });

  /// Null until the first fetch lands; a small default sapling stands in.
  final TreeState? tree;

  /// What the corner badge reads: a day count, or `done/target`.
  final String badge;

  final String semanticsLabel;

  /// Streak 0 / nothing done yet: the same muted treatment the ring had.
  final bool dormant;

  /// A banked freeze, shown as a small teal snowflake at the bottom-left - out
  /// of the badge's corner rather than floating over the canopy.
  final bool hasFreeze;

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badgeHeight = size * 0.42;
    final avatar = tree?.avatar ?? AvatarChoice.defaults;

    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: dormant ? 0.55 : 1,
                child: ClipOval(
                  child: TreeView(
                    seed: tree?.seed ?? 'levensboom',
                    level: tree?.level ?? 2,
                    frac: tree?.progress ?? 0.3,
                    health: tree?.health ?? 1,
                    species: avatar.species,
                    scene: avatar.scene,
                    animal: avatar.animal,
                    framing: TreeFraming.portrait,
                    // Always still at header size. [TreeView]'s sway runs on a
                    // repeating clock, and this sits in the dashboard header:
                    // animating it would repaint the header for the whole
                    // session (and never let `pumpAndSettle` settle in tests)
                    // to produce a wobble that is sub-pixel at 48px.
                    still: true,
                  ),
                ),
              ),
            ),
            if (hasFreeze)
              Positioned(
                left: 0,
                bottom: size * 0.06,
                child: _Chip(
                  height: size * 0.34,
                  background: AppTheme.tealTint,
                  border: AppTheme.teal.withValues(alpha: 0.5),
                  child: Icon(
                    Icons.ac_unit,
                    size: size * 0.20,
                    color: AppTheme.teal,
                  ),
                ),
              ),
            // Bottom-right, overlapping the disc. Fixed width + scaleDown so 1,
            // 2 and 3 digits all fit without the widget's footprint moving.
            Positioned(
              right: 0,
              bottom: 0,
              child: _Chip(
                height: badgeHeight,
                background: scheme.surface,
                border: scheme.outlineVariant,
                child: SizedBox(
                  width: size * 0.40,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      badge,
                      maxLines: 1,
                      style: AppTheme.bodyStrong.copyWith(
                        fontSize: badgeHeight * 0.62,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: dormant
                            ? scheme.onSurfaceVariant
                            : AppTheme.positive,
                      ),
                    ),
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

/// The filled pill both corner marks sit in - solid enough to stay legible over
/// whatever part of the canopy ends up behind it.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.height,
    required this.background,
    required this.border,
    required this.child,
  });

  final double height;
  final Color background;
  final Color border;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Container(
      height: height,
      constraints: BoxConstraints(minWidth: height),
      padding: EdgeInsets.symmetric(horizontal: height * 0.20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}
