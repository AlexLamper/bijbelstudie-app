import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../domain/profile_stats.dart';

/// One badge as a medallion: a tinted disc inside a ring, the way the
/// Levensboom avatar wears its XP ring.
///
/// Three states share one shape, so a row of them reads as a collection rather
/// than as three kinds of tile:
/// - earned: the tone's tint fills the disc and the ring is solid in the tone;
/// - underway: a grey disc, the ring drawn as far as the progress goes;
/// - untouched: the same grey disc, the ring a hairline, and a small lock.
///
/// Everything is an [AppTheme] token or a scheme colour, so the medallion needs
/// no second palette for dark mode.
class BadgeMedallion extends StatelessWidget {
  const BadgeMedallion({
    super.key,
    required this.badge,
    this.size = 56,
    this.outline,
    this.lock = true,
  });

  final BadgeProgress badge;
  final double size;

  /// A 2px cut-out ring in this colour, for medallions that overlap: the disc
  /// in front separates cleanly from the one behind it.
  final Color? outline;

  /// Whether an unearned badge carries the lock chip. Off in the profile's
  /// overlapping row, where the chip would sit under the next medallion.
  final bool lock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final definition = badge.definition;
    final tone = definition.tone;
    final earned = badge.unlocked;
    final cut = outline == null ? 0.0 : 2.0;
    final stroke = (size * 0.055).clamp(2.0, 4.0).toDouble();
    final inset = cut + stroke + size * 0.055;
    final chip = size * 0.34;

    return Semantics(
      label: '${definition.label}, ${earned ? 'behaald' : badge.progressLabel}',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              if (outline != null)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: outline,
                    ),
                  ),
                ),
              // The ring: the whole circle once earned, otherwise the progress
              // arc over a hairline track - the avatar's XP ring, at badge size.
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(cut),
                  child: CircularProgressIndicator(
                    value: badge.fraction,
                    strokeWidth: stroke,
                    strokeCap: StrokeCap.round,
                    backgroundColor: earned ? Colors.transparent : AppTheme.rule,
                    color: tone.color,
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(inset),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: earned
                          ? tone.tint
                          : scheme.surfaceContainerHighest,
                      border: Border.all(
                        color: earned
                            ? tone.color.withValues(alpha: 0.35)
                            : AppTheme.rule,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        definition.icon,
                        size: size * 0.4,
                        color: earned ? tone.color : AppTheme.inkFaint,
                      ),
                    ),
                  ),
                ),
              ),
              if (!earned && lock)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: chip,
                    height: chip,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.surface,
                      border: Border.all(color: scheme.outlineVariant),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.lock_outline,
                      size: chip * 0.55,
                      color: AppTheme.inkFaint,
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

/// The count that unlocks the badge, as a small pill under the medallion: "7",
/// "50", or a check for a server award that has no count.
class BadgeTargetPill extends StatelessWidget {
  const BadgeTargetPill({super.key, required this.badge});

  final BadgeProgress badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = badge.definition.tone;
    final earned = badge.unlocked;
    final target = badge.definition.target;
    final color = earned ? tone.color : AppTheme.inkMuted;

    return Container(
      height: 22,
      constraints: const BoxConstraints(minWidth: 34),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: earned ? tone.tint : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(
          color: earned ? tone.color.withValues(alpha: 0.35) : AppTheme.rule,
        ),
      ),
      child: target > 0
          ? Text(
              '$target',
              style: AppTheme.bodyStrong.copyWith(
                fontSize: 12,
                height: 1,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          : Icon(Icons.check, size: 13, color: color),
    );
  }
}

/// The badge's own page in miniature: what it stands for and where the reader
/// is on it. A sheet rather than a route - there is one paragraph to read.
Future<void> showBadgeDetailSheet(BuildContext context, BadgeProgress badge) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _BadgeDetailSheet(badge: badge),
  );
}

class _BadgeDetailSheet extends StatelessWidget {
  const _BadgeDetailSheet({required this.badge});

  final BadgeProgress badge;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final definition = badge.definition;
    final remaining = badge.remainingLabel;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BadgeMedallion(badge: badge, size: 96),
            const SizedBox(height: 18),
            Text(
              definition.label,
              style: AppTheme.displayTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              definition.description,
              style: AppTheme.bodyMuted,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (badge.unlocked)
              SiteBadge.positive('Behaald', icon: Icons.check)
            else ...[
              SiteProgressBar(
                value: badge.fraction,
                height: 6,
                color: definition.tone.color,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    badge.progressLabel,
                    style: AppTheme.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.ink,
                    ),
                  ),
                  const Spacer(),
                  if (remaining != null)
                    Text(remaining, style: AppTheme.caption),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
