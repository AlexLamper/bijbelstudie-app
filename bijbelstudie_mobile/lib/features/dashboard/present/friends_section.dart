import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/app_widgets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/skeleton.dart';
import '../../friends/data/friend_models.dart';
import '../../friends/present/friends_error_card.dart';
import '../../friends/present/friends_providers.dart';
import '../../friends/present/friends_screen.dart';

/// "Bij je vrienden" on the Start tab, under the tekst van de dag: the two
/// newest posts in the reader's vriendenkring, in the same card style the
/// Vriendenkring screen uses, or the invitation when there is no kring yet.
///
/// Deliberately below the fold: the verse card has to be fully in view, so
/// this is what the reader scrolls to.
class FriendsSection extends ConsumerWidget {
  const FriendsSection({super.key, this.maxPosts = 2});

  final int maxPosts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(friendsFeedProvider);
    final feed = async.value;
    final posts = feed == null
        ? const <FriendPost>[]
        : feed.posts.take(maxPosts).toList(growable: false);
    final failed = feed == null && async.hasError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Bij je vrienden',
          actionLabel: 'Alles bekijken',
          onAction: () => context.push('/vriendenkring'),
        ),
        const SizedBox(height: 12),
        // The invitation only once the feed has actually answered: a reader
        // with friends should not see "nodig vrienden uit" flash by first,
        // and a reader whose request failed should not see it at all - that
        // card says "you have nobody", which a failed call does not know.
        //
        // The error is checked before the loading flag because an `AsyncError`
        // still reports `isLoading`; a skeleton that never resolves is the
        // broken screen §10 rules out. A "feature off" answer stays quiet and
        // falls through to the invitation: nothing there is the reader's to fix.
        if (failed && !FriendsErrorCard.isQuiet(async.error))
          FriendsErrorCard(
            failure: async.error!,
            compact: true,
            onRetry: () => ref.read(friendsFeedProvider.notifier).refresh(),
          )
        else if (feed == null && !failed && async.isLoading)
          const Skeleton(height: 120, radius: AppTheme.radiusLg)
        else if (posts.isEmpty)
          const InviteFriendsCard()
        else
          FriendPostList(posts: posts),
      ],
    );
  }
}
