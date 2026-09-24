import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../domain/growth_copy.dart';
import 'levensboom_providers.dart';
import 'tree_analytics.dart';

/// The one-time "Je boom groeit nu in twintig stappen" card on the home screen
/// (LEVENSBOOM_GROWTH_PLAN.md §9.6), for accounts from before growth v2.
///
/// The server decides who may see it (`levensboom.announceGrowth`); whether it
/// was already dismissed is the `growth-v2` key in `seenItems`, written through
/// the same studio write as the "Nieuw" dots - on the account, so a card
/// closed on the website stays closed here. Both buttons dismiss it; "Bekijk
/// je groei" also opens the Groei ladder. Renders nothing otherwise.
class GrowthAnnouncementCard extends ConsumerWidget {
  const GrowthAnnouncementCard({super.key, this.bottomSpacing = 16});

  /// Space under the card, only when it is shown, so the home column keeps its
  /// rhythm with or without it.
  final double bottomSpacing;

  void _dismiss(WidgetRef ref, String action) {
    trackTree(ref, AnalyticsEvents.treeAnnouncementSeen, {'action': action});
    // Optimistic: the card is gone at once; a failed write shows it again on
    // the next fetch, which is the right outcome for a message not yet read.
    ref.read(treeStateProvider.notifier).markItemsSeen(const [growthAnnouncementKey]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final tree = ref.watch(treeStateProvider).value;
    if (tree == null ||
        !showsGrowthAnnouncement(
          announceGrowth: tree.announceGrowth,
          seenItems: tree.seenItems,
          disabled: tree.disabled,
        )) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: AppCard(
        color: AppTheme.tealTint,
        borderColor: AppTheme.teal,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              growthAnnouncementTitle,
              style: AppTheme.bodyStrong.copyWith(color: AppTheme.tealStrong, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(growthAnnouncementBody, style: AppTheme.bodyMuted.copyWith(height: 1.5)),
            const SizedBox(height: 14),
            // A Wrap, not a Row: on a narrow phone the second button drops to
            // its own line instead of squeezing the first one's label.
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                SiteButton(
                  label: growthAnnouncementOpen,
                  height: 42,
                  expand: false,
                  onPressed: () {
                    context.push('/profile/boom?tab=groei');
                    _dismiss(ref, 'open');
                  },
                ),
                SiteOutlineButton(
                  label: growthAnnouncementClose,
                  height: 42,
                  expand: false,
                  onPressed: () => _dismiss(ref, 'close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
