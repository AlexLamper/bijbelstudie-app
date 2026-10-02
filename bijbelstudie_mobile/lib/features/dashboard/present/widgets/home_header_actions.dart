import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../friends/present/friends_providers.dart';

/// The two round buttons on the right of the Start tab's header.
///
/// The header used to carry the account's tree with a number in it, which read
/// as an avatar rather than as a streak. It is now a vriendenkring button and
/// a flame pill; the avatar lives in the tab bar, where it belongs.
///
/// Both are 44x44 at least, so either is a full tap target.
class HomeHeaderActions extends StatelessWidget {
  const HomeHeaderActions({super.key, required this.streak});

  /// The streak pill, built by `HomeStreakIndicator` (which knows whether this
  /// reader is on a daily streak or a week goal). Empty for a reader with
  /// neither.
  final Widget streak;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const FriendsCircleButton(),
        const SizedBox(width: 8),
        streak,
      ],
    );
  }
}

/// The vriendenkring button: a circle with a "two people" icon and a small
/// teal badge for new activity. No badge at 0.
class FriendsCircleButton extends ConsumerWidget {
  const FriendsCircleButton({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final badge = ref.watch(friendsBadgeProvider);

    return Tooltip(
      message: 'Vriendenkring',
      child: Semantics(
        button: true,
        label: badge == 0
            ? 'Vriendenkring'
            : 'Vriendenkring, $badge nieuw${badge == 1 ? '' : 'e'} '
                  '${badge == 1 ? 'bericht' : 'berichten'}',
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: scheme.surface,
                shape: CircleBorder(side: BorderSide(color: scheme.outline)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => context.push('/vriendenkring'),
                  child: SizedBox.square(
                    dimension: size,
                    child: Icon(
                      Icons.people_outline,
                      size: size * 0.46,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
              ),
              if (badge > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.teal,
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      border: Border.all(color: scheme.surface, width: 2),
                    ),
                    child: Text(
                      badge > 9 ? '9+' : '$badge',
                      style: const TextStyle(
                        fontSize: 10,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
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

/// The streak button: a pill with an orange flame and the number of days in a
/// row beside it. Orange is the flame's alone on this screen; nothing else
/// warns in colour here.
class StreakFlamePill extends StatelessWidget {
  const StreakFlamePill({
    super.key,
    required this.label,
    required this.semanticsLabel,
    this.icon = Icons.local_fire_department,
    this.dormant = false,
    this.height = 44,
  });

  /// "1", or "3/5" for a reader on a week goal.
  final String label;
  final String semanticsLabel;

  /// Replaced by a check for a week-goal reader: a flame would be a lie there.
  final IconData icon;

  /// Nothing going yet: the mark stays, muted, so the explainer is still a tap
  /// away and the header does not change shape.
  final bool dormant;

  final double height;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final tint = dormant ? AppTheme.inkMuted : AppTheme.flame;

    return Semantics(
      label: semanticsLabel,
      child: Container(
        height: height,
        constraints: const BoxConstraints(minWidth: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: tint),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTheme.bodyStrong.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1,
                color: dormant ? AppTheme.inkMuted : AppTheme.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
