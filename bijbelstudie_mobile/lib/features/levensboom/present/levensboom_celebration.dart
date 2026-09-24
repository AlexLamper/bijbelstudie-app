import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../domain/catalog.dart';
import '../domain/chime.dart';
import '../domain/growth.dart';
import '../domain/growth_copy.dart';
import '../domain/palette.dart';
import '../domain/stages.dart';
import '../domain/traits.dart';
import '../domain/tree_state.dart';
import 'levensboom_providers.dart';
import 'tree_analytics.dart';
import 'tree_view.dart';

/// The level-up moment.
///
/// Kept for level-ups and fruit unlocks only - rare enough to stay worth
/// stopping for. There is nothing to collect and no "claim" button: what grew
/// (the growth-v2 copy rules, `growth_copy.dart`), the items the level just
/// unlocked, and a way out. The mirror of the website's
/// `components/levensboom/LevelUpDialog.tsx`.
///
/// [tree] carries the growth floor and the last level the reader was shown, so
/// a jump over several levels is one card from there to here. Without it the
/// card works from [level] alone, as an account without a floor.
Future<void> showLevensboomCelebration(
  BuildContext context,
  WidgetRef ref, {
  required String seed,
  required int level,
  required bool reducedMotion,
  AvatarChoice avatar = AvatarChoice.defaults,
  TreeState? tree,
}) async {
  final floor = tree?.floor;
  final copy = levelUpCopy(level: level, fromLevel: tree?.lastSeenLevel, floor: floor);

  trackTree(ref, AnalyticsEvents.treeLevelupSeen, {
    'level': '$level',
    'step': '${copy.step}',
    'phase': phaseForStep(copy.step).id,
    'floored': floor != null ? 'true' : 'false',
  });

  if (!reducedMotion) {
    // Gentle, once. `mediumImpact` is the heaviest thing this app does, and it
    // is reserved for exactly this.
    await HapticFeedback.mediumImpact();
    await _playChime();
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierColor: const Color(0xB8080B1A),
    builder: (_) => _CelebrationDialog(
      seed: seed,
      level: level,
      fromLevel: _fromLevel(level, tree?.lastSeenLevel),
      floor: floor,
      copy: copy,
      avatar: avatar,
      reducedMotion: reducedMotion,
    ),
  );

  await ref.read(treeStateProvider.notifier).markSeen(level);
}

/// The level the growth tween starts from: the last one the reader was shown,
/// or the one before this, never below 1. The website's `LevelUpDialog`.
int _fromLevel(int level, int? lastSeenLevel) {
  final previous = lastSeenLevel ?? level - 1;
  return math.max(1, math.min(level - 1, previous));
}

/// Plays the chime, respecting the silent switch.
///
/// `AudioContextConfig(respectSilence: true)` is the point of doing this by
/// hand: the default session category keeps playing with the ringer off, which
/// is right for a podcast and wrong for a decorative chime on a Bible app.
/// Everything here fails silently - audio is decoration, and a device with no
/// audio route must not break the celebration that triggered it.
Future<void> _playChime() async {
  try {
    final player = AudioPlayer();
    await player.setAudioContext(
      AudioContextConfig(respectSilence: true, focus: AudioContextConfigFocus.mixWithOthers)
          .build(),
    );
    await player.play(BytesSource(levelUpChimeWav()), volume: 0.9);
    // Nothing else holds a reference, so release the platform player when the
    // sound ends rather than leaking one per level-up.
    player.onPlayerComplete.first.then((_) => player.dispose()).catchError((_) {});
  } catch (_) {
    /* decoration only */
  }
}

class _CelebrationDialog extends StatelessWidget {
  const _CelebrationDialog({
    required this.seed,
    required this.level,
    required this.fromLevel,
    required this.floor,
    required this.copy,
    required this.avatar,
    required this.reducedMotion,
  });

  final String seed;
  final int level;

  /// Where the growth starts: the previous level, or the last level the reader
  /// saw celebrated when this is a jump over several.
  final int fromLevel;
  final GrowthFloor? floor;
  final LevelUpCopy copy;
  final AvatarChoice avatar;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final still = reducedMotion || MediaQuery.maybeDisableAnimationsOf(context) == true;
    final fruit = fruitAtLevel(level);
    // Everything the levels since the last card unlocked, not only the last one.
    final unlocked = [
      for (var at = fromLevel + 1; at <= level; at++) ...itemsUnlockedAtLevel(at),
    ];

    // Night, always: the sequence dims to a night sky so the new growth reads
    // against something quiet. The reader's own scene keeps its backdrop.
    final palette = buildPalette(
      seasonForMonth(DateTime.now().month),
      DayPhase.night,
      scene: avatar.scene,
      species: avatar.species,
    );

    return Dialog(
      backgroundColor: const Color(0xFF0B1027),
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg + 8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 240,
            width: double.infinity,
            child: ClipRect(
              // The reader's own tree growing from where it stood to where it
              // stands now: branches that were there lengthen, new wood grows
              // out of their tips and the camera eases out with it (the growth
              // tween, spec §12). That replaces the depth reveal and the camera
              // push, which replayed a newly generated tree. One level: from
              // the very end of the previous one, so what grows is this
              // level's new wood. A jump: from where the reader last saw it.
              child: TreeView(
                seed: seed,
                level: level,
                frac: 0,
                floor: floor,
                from: TreeFrom(
                  level: fromLevel,
                  frac: fromLevel == level - 1 ? 0.999 : 0,
                ),
                species: avatar.species,
                scene: avatar.scene,
                animal: avatar.animal,
                reducedMotion: still,
                palette: palette,
                celebration: !still,
                // The newest fruit is the last on the tree, and the scene
                // lists them in unlock order.
                bloomFruit: fruit == null ? null : fruitCount(level) - 1,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            child: Column(
              children: [
                Text(
                  copy.title,
                  textAlign: TextAlign.center,
                  style: AppTheme.displayMedium.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  copy.subtitle,
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyStrong.copyWith(
                    color: const Color(0xFF8FD694),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (copy.line != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    copy.line!,
                    textAlign: TextAlign.center,
                    style: AppTheme.bodyMuted.copyWith(color: Colors.white70),
                  ),
                ],
                if (unlocked.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NIEUW VOOR JE BOOM',
                          style: AppTheme.caption.copyWith(
                            color: Colors.white54,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            fontSize: 10.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final item in unlocked)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  item.name,
                                  style: AppTheme.bodyStrong.copyWith(color: Colors.white),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    item.blurb,
                                    textAlign: TextAlign.end,
                                    style: AppTheme.caption.copyWith(color: Colors.white60),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            foregroundColor: const Color(0xFF8FD694),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            context.push('/profile/boom');
                          },
                          child: const Text('Bekijk je voortgang →'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                SiteButton(
                  label: 'Verder',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
