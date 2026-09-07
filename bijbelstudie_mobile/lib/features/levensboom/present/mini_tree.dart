import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'tree_view.dart';

/// The Levensboom at header size: the reader's own tree, small, with a count
/// badge tucked into the corner.
///
/// Deliberately a thin wrapper over [TreeView] rather than a second renderer.
/// The generator, palette, wilt handling, sway clock and `disableAnimations`
/// contract all live there already and are shared with the profile hero and the
/// level-up sequence - a badge that drew its own tree would be a second thing to
/// keep in parity with the website, for no gain.
///
/// The one thing this adds is a *badge-specific growth curve*. The header tree
/// is not the account's real Levensboom (that is level/XP driven, and lives on
/// Profiel); it visualises whatever streak-shaped number the header is showing.
/// So the caller hands in a plain 0..1 [growth] and this maps it onto the level
/// range the shared generator understands.
class MiniTree extends StatelessWidget {
  const MiniTree({
    super.key,
    required this.seed,
    required this.growth,
    required this.badge,
    required this.semanticsLabel,
    this.health = 1,
    this.dormant = false,
    this.hasFreeze = false,
    this.size = 48,
  });

  /// Stable per user, so the reader's header tree is the same tree as their
  /// profile one. Empty is safe - the generator seeds from the string as given.
  final String seed;

  /// 0..1 overall maturity. See [growthForStreak] / [growthForGoal].
  final double growth;

  /// What the corner badge reads: a day count, or `done/target`.
  final String badge;

  final String semanticsLabel;

  /// 0.3..1, as the server defines it. Below 1 the shared generator droops the
  /// branches and sheds leaves, and the palette desaturates.
  final double health;

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

    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // TreeView paints its own sky disc and ground arc, so clipping it
            // round is the whole backdrop treatment needed here.
            Positioned.fill(
              child: Opacity(
                opacity: dormant ? 0.55 : 1,
                child: ClipOval(
                  child: TreeView(
                    seed: seed,
                    level: miniTreeLevel(growth),
                    frac: miniTreeFrac(growth),
                    health: health,
                    // Always still at header size. [TreeView]'s sway runs on a
                    // repeating clock, and this sits in the dashboard header:
                    // animating it would repaint the header for the whole
                    // session (and never let `pumpAndSettle` settle in tests)
                    // to produce a wobble that is sub-pixel at 48px. The
                    // account's motion pref still matters on the profile hero,
                    // where the tree is big enough for the sway to read.
                    reducedMotion: true,
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

/// How many of the shared generator's levels the header tree spans.
///
/// Capped low on purpose. The generator's branch count is exponential in level
/// and this thing repaints inside the dashboard header; level 6 is ~50 branches,
/// which is cheap, still gains a real canopy (the `canopy` trait lands at 3) and
/// keeps every step of the curve visible at 48px. The profile hero is where the
/// account's actual, uncapped level is rendered.
const int kMiniTreeMaxLevel = 6;

/// Streak in days -> 0..1 maturity.
///
/// `1 - e^(-streak/21)`: day 1 already shows a visible sprout, ~day 21 reads as
/// a proper tree, and it keeps inching up forever without ever saturating - so
/// there is no day on which the tree stops responding to the streak.
double growthForStreak(int streak) {
  if (streak <= 0) return 0;
  return 1 - math.exp(-streak / 21.0);
}

/// Week-goal readers get the same family of tree, grown by this week's fraction.
double growthForGoal(int done, int target) {
  if (target <= 0 || done <= 0) return 0;
  return (done / target).clamp(0.0, 1.0);
}

double _position(double growth) =>
    growth.clamp(0.0, 1.0) * (kMiniTreeMaxLevel - 1);

/// The whole part of [growth] across the badge's level range.
int miniTreeLevel(double growth) =>
    (1 + _position(growth).floor()).clamp(1, kMiniTreeMaxLevel);

/// The remainder, handed to the generator as in-level progress - it is what
/// unfurls the buds, so growth keeps reading as movement between whole levels.
double miniTreeFrac(double growth) {
  final position = _position(growth);
  return (position - position.floor()).clamp(0.0, 1.0);
}
