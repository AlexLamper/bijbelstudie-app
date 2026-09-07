import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../domain/chime.dart';
import '../domain/palette.dart';
import '../domain/traits.dart';
import '../domain/tree_generator.dart';
import 'levensboom_providers.dart';
import 'tree_view.dart';

/// The level-up moment.
///
/// Kept for level-ups and fruit unlocks only - rare enough to stay worth
/// stopping for. There is nothing to collect and no "claim" button: one line
/// about what grew, and a way out. The mirror of the website's
/// `components/levensboom/LevelUpDialog.tsx`.
Future<void> showLevensboomCelebration(
  BuildContext context,
  WidgetRef ref, {
  required String seed,
  required int level,
  required bool reducedMotion,
}) async {
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
      reducedMotion: reducedMotion,
    ),
  );

  await ref.read(treeStateProvider.notifier).markSeen(level);
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

class _CelebrationDialog extends StatefulWidget {
  const _CelebrationDialog({
    required this.seed,
    required this.level,
    required this.reducedMotion,
  });

  final String seed;
  final int level;
  final bool reducedMotion;

  @override
  State<_CelebrationDialog> createState() => _CelebrationDialogState();
}

class _CelebrationDialogState extends State<_CelebrationDialog>
    with TickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  /// Slower than the growth, so the push is still settling when the new wood
  /// has finished arriving.
  late final AnimationController _push = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// Where the previous level's silhouette ended, so what the reader watches
  /// grow is the new wood rather than the whole tree replaying.
  late final double _from = () {
    final previous = maxDepthForLevel(widget.level - 1);
    final now = maxDepthForLevel(widget.level) + 1;
    final ratio = previous / now;
    return ratio > 0.92 ? 0.92 : ratio;
  }();

  @override
  void initState() {
    super.initState();
    if (!widget.reducedMotion) {
      _grow.forward();
      _push.forward();
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    _push.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still =
        widget.reducedMotion || MediaQuery.maybeDisableAnimationsOf(context) == true;
    final fruit = fruitAtLevel(widget.level);
    final trait = traitAtLevel(widget.level);

    // Night, always: the sequence dims to a night sky so the new growth reads
    // against something quiet.
    final palette = buildPalette(
      seasonForMonth(DateTime.now().month),
      DayPhase.night,
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
              child: AnimatedBuilder(
                animation: _push,
                builder: (context, child) => Transform.scale(
                  // The slow camera push: the tree eases in and scales up a
                  // hair, so the sequence reads as moving toward the tree
                  // rather than as a dialog appearing over it.
                  scale: still ? 1 : 1 + 0.08 * Curves.easeOutCubic.transform(_push.value),
                  child: child,
                ),
                child: AnimatedBuilder(
                  animation: _grow,
                  builder: (context, _) => TreeView(
                    seed: widget.seed,
                    level: widget.level,
                    frac: 0,
                    reveal: still
                        ? 1
                        : _from + (1 - _from) * Curves.easeOutCubic.transform(_grow.value),
                    reducedMotion: still,
                    palette: palette,
                    celebration: !still,
                    // The newest fruit is the last on the tree, and the scene
                    // lists them in unlock order.
                    bloomFruit: fruit == null ? null : fruitCount(widget.level) - 1,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            child: Column(
              children: [
                Text(
                  'JE BOOM IS GEGROEID',
                  style: AppTheme.caption.copyWith(
                    color: const Color(0xFF8FD694),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  fruit == null
                      ? 'Niveau ${widget.level}'
                      : 'Niveau ${widget.level} — ${fruit.name}',
                  textAlign: TextAlign.center,
                  style: AppTheme.displayMedium.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 10),
                Text(
                  fruit != null
                      ? 'De ${fruit.name.toLowerCase()} hangt nu aan je boom — '
                            'een vrucht van de Geest, ${fruit.reference}.'
                      : trait != null
                      ? kTraitLabels[trait]!
                      : _encouragement(widget.level),
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyMuted.copyWith(color: Colors.white70),
                ),
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

String _encouragement(int level) {
  const lines = [
    'Je boom staat er sterker bij dan gisteren.',
    'Elke keer dat je leest, groeit er iets.',
    'Rustig doorgaan is wat een boom groot maakt.',
    'Een nieuwe tak - gegroeid uit wat je gelezen hebt.',
  ];
  return lines[level % lines.length];
}
