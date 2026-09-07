import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
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
    if (!widget.reducedMotion) _grow.forward();
  }

  @override
  void dispose() {
    _grow.dispose();
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
            child: AnimatedBuilder(
              animation: _grow,
              builder: (context, _) => TreeView(
                seed: widget.seed,
                level: widget.level,
                frac: 0,
                reveal: still ? 1 : _from + (1 - _from) * Curves.easeOutCubic.transform(_grow.value),
                reducedMotion: still,
                palette: palette,
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
