import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../domain/profile_stats.dart';

/// One badge as a medallion: a tinted disc inside a ring, the way the
/// Levensboom avatar wears its XP ring.
///
/// Three states share one shape, so a row of them reads as a collection rather
/// than as three kinds of tile:
/// - earned: a gradient sheen fills the disc, the ring is solid in the tone
///   and a soft tone-coloured glow lifts it off the page - the same reward
///   language as the lesson-complete card's level-up glow;
/// - underway: a faintly tone-tinted disc, the ring drawn as far as the
///   progress goes over a tone-tinted track;
/// - untouched: a flat grey disc, the ring a neutral hairline, and a small
///   lock - no hint of the tone until progress starts.
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
    final underway = !earned && badge.value > 0;
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
              // A soft glow behind an earned badge - the same lift the
              // lesson-complete card gives a levelled-up tree, scaled to a
              // medallion and inset so the blur stays inside this box rather
              // than spilling onto whatever it overlaps in a cluster or grid.
              if (earned)
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.all(size * 0.03),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: tone.color.withValues(alpha: 0.32),
                            blurRadius: size * 0.16,
                            offset: Offset(0, size * 0.035),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // The ring: the whole circle once earned, otherwise the progress
              // arc over a track - a neutral hairline while untouched, a
              // tone-tinted one once progress starts - the avatar's XP ring,
              // at badge size.
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(cut),
                  child: CircularProgressIndicator(
                    value: badge.fraction,
                    strokeWidth: stroke,
                    strokeCap: StrokeCap.round,
                    backgroundColor: earned
                        ? Colors.transparent
                        : underway
                        ? tone.color.withValues(alpha: 0.16)
                        : AppTheme.rule,
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
                      // A subtle sheen once earned - a lighter highlight
                      // easing into the tone's tint - instead of a flat fill,
                      // for a touch of depth. Flat and muted until then.
                      gradient: earned
                          ? RadialGradient(
                              center: const Alignment(-0.4, -0.4),
                              radius: 1.15,
                              colors: [
                                Color.lerp(tone.tint, scheme.surface, 0.55)!,
                                tone.tint,
                              ],
                            )
                          : null,
                      color: earned
                          ? null
                          : underway
                          ? Color.alphaBlend(
                              tone.color.withValues(alpha: 0.07),
                              scheme.surfaceContainerHighest,
                            )
                          : scheme.surfaceContainerHighest,
                      border: Border.all(
                        color: earned
                            ? tone.color.withValues(alpha: 0.5)
                            : underway
                            ? tone.color.withValues(alpha: 0.24)
                            : AppTheme.rule,
                        width: earned ? 1.5 : 1,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        definition.icon,
                        size: size * 0.4,
                        color: earned
                            ? tone.color
                            : underway
                            ? Color.lerp(AppTheme.inkFaint, tone.color, 0.55)!
                            : AppTheme.inkFaint,
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

/// The count that unlocks the badge, as a small pill under the medallion:
/// "7" once earned, "3 / 7" while it is underway, or a check for a server
/// award that has no count.
class BadgeTargetPill extends StatelessWidget {
  const BadgeTargetPill({super.key, required this.badge});

  final BadgeProgress badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = badge.definition.tone;
    final earned = badge.unlocked;
    final underway = !earned && badge.value > 0;
    final target = badge.definition.target;
    final color = earned
        ? tone.color
        : underway
        ? Color.lerp(AppTheme.inkMuted, tone.color, 0.6)!
        : AppTheme.inkMuted;

    final Widget content;
    if (target <= 0) {
      content = Icon(Icons.check, size: 13, color: color);
    } else if (underway) {
      // [BadgeProgress.progressLabel] is exactly "value / target" while a
      // badge is not yet earned - reused as-is so the pill and the detail
      // sheet never disagree on the numbers.
      content = Text(
        badge.progressLabel,
        style: AppTheme.bodyStrong.copyWith(
          fontSize: 12,
          height: 1,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    } else {
      content = Text(
        '$target',
        style: AppTheme.bodyStrong.copyWith(
          fontSize: 12,
          height: 1,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }

    return Container(
      height: 22,
      constraints: const BoxConstraints(minWidth: 34),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: earned
            ? tone.tint
            : underway
            ? Color.alphaBlend(
                tone.color.withValues(alpha: 0.10),
                scheme.surfaceContainerHighest,
              )
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(
          color: earned
              ? tone.color.withValues(alpha: 0.35)
              : underway
              ? tone.color.withValues(alpha: 0.28)
              : AppTheme.rule,
        ),
      ),
      child: content,
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
    final tone = definition.tone;
    final earned = badge.unlocked;
    final remaining = badge.remainingLabel;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 132,
              height: 132,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // A wash of the badge's own tone behind it - brighter once
                  // earned, a quiet hint of what is coming while it isn't -
                  // the same reward language [BadgeMedallion]'s glow uses.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            tone.color.withValues(alpha: earned ? 0.22 : 0.08),
                            tone.color.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  BadgeMedallion(badge: badge, size: 96),
                ],
              ),
            ),
            const SizedBox(height: 14),
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
            if (earned)
              SiteBadge.positive('Behaald', icon: Icons.check)
            else ...[
              // The count, big enough to feel like a stat rather than a
              // caption - the motivating read [BadgeTargetPill] gives in
              // miniature, reusing the same [BadgeProgress] fields.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${badge.value}',
                    style: AppTheme.statNumber.copyWith(
                      fontSize: 26,
                      color: tone.color,
                    ),
                  ),
                  Text(
                    ' / ${definition.target}',
                    style: AppTheme.statNumber.copyWith(
                      fontSize: 16,
                      color: AppTheme.inkFaint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SiteProgressBar(
                value: badge.fraction,
                height: 7,
                color: tone.color,
              ),
              if (remaining != null) ...[
                const SizedBox(height: 8),
                Text(
                  remaining,
                  style: AppTheme.caption,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
