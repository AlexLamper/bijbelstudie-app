import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/friend_models.dart';
import '../data/friends_failure.dart';
import '../data/friends_repository.dart';

/// The vriendenkring feed, shared by the Start tab's "Bij je vrienden" block
/// and the Vriendenkring screen itself, so both agree on the posts and on the
/// badge count and one fetch serves both.
class FriendsFeedNotifier extends AsyncNotifier<FriendsFeed> {
  @override
  Future<FriendsFeed> build() {
    return ref.watch(friendsRepositoryProvider).getFeed();
  }

  /// Back to page one. A failure replaces the feed with the error rather than
  /// leaving yesterday's posts on screen as though they were current.
  Future<void> refresh() async {
    try {
      state = AsyncData(await ref.read(friendsRepositoryProvider).getFeed());
    } on FriendsException catch (e, stack) {
      state = AsyncError(e, stack);
    }
  }

  /// The next `before=` page, appended.
  ///
  /// The cursor is the `createdAt` of the oldest post on screen; the server
  /// compares `$lt`, so no post comes back twice - the id check is only there
  /// for posts that share a timestamp to the millisecond.
  ///
  /// A failure here does not throw away the page already read: it flips
  /// [FriendsFeed.loadMoreFailed] so the button can say it did not work.
  Future<void> loadMore() async {
    final feed = state.value;
    if (feed == null || feed.loadingMore || !feed.hasMore || feed.posts.isEmpty) return;
    state = AsyncData(feed.copyWith(loadingMore: true, loadMoreFailed: false));
    try {
      final next = await ref
          .read(friendsRepositoryProvider)
          .getFeed(before: feed.posts.last.createdAt);
      final seen = {for (final post in feed.posts) post.id};
      final added = [
        for (final post in next.posts)
          if (!seen.contains(post.id)) post,
      ];
      state = AsyncData(
        feed.copyWith(
          posts: [...feed.posts, ...added],
          hasMore: added.isNotEmpty && next.hasMore,
          loadingMore: false,
          loadMoreFailed: false,
        ),
      );
    } catch (_) {
      state = AsyncData(feed.copyWith(loadingMore: false, loadMoreFailed: true));
    }
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

  /// A reaction landed: the bubble's count catches up without refetching the
  /// feed, which would drop any `before=` pages already scrolled in.
  void bumpCommentCount(String postId, {int by = 1}) {
    final feed = state.value;
    if (feed == null) return;
    final index = feed.posts.indexWhere((post) => post.id == postId);
    if (index < 0) return;
    final posts = [...feed.posts];
    posts[index] = posts[index].copyWith(
      commentCount: (posts[index].commentCount + by).clamp(0, 1 << 30),
    );
    state = AsyncData(feed.copyWith(posts: posts));
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

/// The kring itself (the Vrienden tab, and the rows a friend row needs).
/// Separate from the feed so a heart does not refetch the people, and a
/// removal does not refetch the posts.
final friendsKringProvider = FutureProvider.autoDispose<FriendsKring>((ref) {
  return ref.watch(friendsRepositoryProvider).getKring();
});

/// Pending verzoeken, in both directions.
final friendsRequestsProvider =
    FutureProvider.autoDispose<FriendRequestsResponse>((ref) {
      return ref.watch(friendsRepositoryProvider).getRequests();
    });

/// The reader's own vriendenkring settings.
///
/// Read here for `blocked`: the blocked list rides along on the settings
/// response rather than having an endpoint of its own.
final friendsSettingsProvider = FutureProvider.autoDispose<FriendSettings>((ref) {
  return ref.watch(friendsRepositoryProvider).getSettings();
});

/// One person, as `/vriendenkring/<userId>` shows them.
///
/// Per id and auto-disposing: a profile is read when it is opened and is not
/// worth keeping once the screen is gone, and what it may show depends on the
/// vriendschap, which an action on the screen itself can change.
final friendProfileProvider =
    FutureProvider.autoDispose.family<FriendProfileView, String>((ref, userId) {
      return ref.watch(friendsRepositoryProvider).getProfile(userId);
    });

/// "Mensen die je misschien kent" - friends of the people in the kring.
///
/// Structurally empty for a reader with no friends, which is why the section
/// built on it hides itself rather than explaining itself.
final friendSuggestionsProvider =
    FutureProvider.autoDispose<FriendSuggestionsResponse>((ref) {
      return ref.watch(friendsRepositoryProvider).getSuggestions();
    });

/// The reactions under one post, oldest first.
///
/// Per post and auto-disposing, because a thread is only ever open one at a
/// time and the count on the card is what the feed carries. The whole thread
/// comes down in one call - the server paginates nothing here - so this is a
/// plain list, not a page.
final friendPostCommentsProvider =
    FutureProvider.autoDispose.family<List<FriendPostComment>, String>((ref, postId) {
      return ref.watch(friendsRepositoryProvider).listComments(postId);
    });
