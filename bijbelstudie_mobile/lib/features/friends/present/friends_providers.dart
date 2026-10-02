import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/friend_models.dart';
import '../data/friends_repository.dart';

/// The vriendenkring feed, shared by the Start tab's "Bij je vrienden" block
/// and the Vriendenkring screen itself, so both agree on the posts and on the
/// badge count and one fetch serves both.
class FriendsFeedNotifier extends AsyncNotifier<FriendsFeed> {
  @override
  Future<FriendsFeed> build() {
    return ref.watch(friendsRepositoryProvider).getFeed();
  }

  Future<void> refresh() async {
    state = AsyncData(await ref.read(friendsRepositoryProvider).getFeed());
  }

  /// Hearts or unhearts a post: ticked locally first, put back if the server
  /// refuses, so the heart answers the tap at once.
  Future<void> toggleLike(String postId) async {
    final feed = state.value;
    if (feed == null) return;
    final index = feed.posts.indexWhere((p) => p.id == postId);
    if (index < 0) return;
    final post = feed.posts[index];
    final liked = !post.likedByMe;

    List<FriendPost> withLike(bool value) {
      final posts = [...feed.posts];
      posts[index] = post.copyWith(
        likedByMe: value,
        likeCount: value
            ? post.likeCount + (post.likedByMe ? 0 : 1)
            : (post.likeCount - (post.likedByMe ? 1 : 0)).clamp(0, 1 << 30),
      );
      return posts;
    }

    state = AsyncData(feed.copyWith(posts: withLike(liked)));
    final ok = await ref.read(friendsRepositoryProvider).setLike(postId, liked);
    if (!ok) state = AsyncData(feed.copyWith(posts: withLike(!liked)));
  }

  /// Vriendenkring was opened: the badge on Start goes out.
  Future<void> markSeen() async {
    final feed = state.value;
    if (feed == null || feed.newActivityCount == 0) return;
    state = AsyncData(feed.copyWith(newActivityCount: 0));
    await ref.read(friendsRepositoryProvider).markSeen();
  }
}

final friendsFeedProvider =
    AsyncNotifierProvider<FriendsFeedNotifier, FriendsFeed>(
      FriendsFeedNotifier.new,
    );

/// The teal badge on the header's vriendenkring button. 0 means no badge.
final friendsBadgeProvider = Provider<int>((ref) {
  return ref.watch(friendsFeedProvider).value?.newActivityCount ?? 0;
});
