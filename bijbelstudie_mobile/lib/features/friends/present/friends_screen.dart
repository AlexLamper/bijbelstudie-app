import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../feedback/present/feedback_sheet.dart';
import '../../referral/data/referral_repository.dart';
import '../data/friend_models.dart';
import '../data/friends_repository.dart';
import 'friend_post_card.dart';
import 'friends_providers.dart';

/// `/vriendenkring` - the people the reader reads along with, newest post
/// first. Reached from the Start tab's header button and from "Alles bekijken"
/// under "Bij je vrienden"; it has no tab of its own.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the screen is what "gezien" means, so the badge on Start clears
    // here rather than on any tap that happens to land in the feed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(friendsFeedProvider.notifier).markSeen();
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(friendsFeedProvider);
    final feed = async.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Vriendenkring')),
      body: RefreshIndicator(
        color: AppTheme.teal,
        onRefresh: () => ref.read(friendsFeedProvider.notifier).refresh(),
        child: feed == null && async.isLoading
            ? const Center(child: AppLoader())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  if (feed == null || feed.posts.isEmpty)
                    const InviteFriendsCard()
                  else
                    FriendPostList(posts: feed.posts),
                ],
              ),
      ),
    );
  }
}

/// The feed itself: [FriendPostCard]s wired to [friendsFeedProvider], so the
/// Start tab's two newest posts and the whole Vriendenkring list behave the
/// same under a heart or a reaction.
class FriendPostList extends ConsumerWidget {
  const FriendPostList({super.key, required this.posts, this.spacing = 12});

  final List<FriendPost> posts;
  final double spacing;

  Future<void> _comment(BuildContext context, WidgetRef ref, FriendPost post) async {
    final text = await showFriendCommentSheet(context);
    if (text == null || !context.mounted) return;
    final ok = await ref.read(friendsRepositoryProvider).addComment(post.id, text);
    if (!context.mounted) return;
    if (ok) {
      await ref.read(friendsFeedProvider.notifier).refresh();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reactie kon niet worden geplaatst')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < posts.length; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          FriendPostCard(
            post: posts[i],
            onLike: () => ref.read(friendsFeedProvider.notifier).toggleLike(posts[i].id),
            onComment: () => _comment(context, ref, posts[i]),
            onMore: () => showFriendPostMoreSheet(
              context,
              post: posts[i],
              onReport: () => showFeedbackSheet(context, ref),
            ),
          ),
        ],
      ],
    );
  }
}

/// "Lees samen met vrienden" - the one card a reader without a vriendenkring
/// sees, on Start and on Vriendenkring both. Sharing the invite link is the
/// only action; it unlocks nothing the reader did not already have.
class InviteFriendsCard extends ConsumerWidget {
  const InviteFriendsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final overview = ref.watch(referralOverviewProvider).value;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconChip(icon: Icons.people_outline, size: 40, iconSize: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lees samen met vrienden',
                      style: AppTheme.bodyStrong.copyWith(
                        fontSize: 15,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Zie waar zij lezen en moedig elkaar aan.',
                      style: AppTheme.caption.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SiteButton(
            label: 'Vrienden uitnodigen',
            onPressed: overview == null
                ? null
                : () => Share.share(overview.shareText),
          ),
        ],
      ),
    );
  }
}
