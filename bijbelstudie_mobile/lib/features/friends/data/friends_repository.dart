import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/preview_config.dart';
import '../../auth/present/auth_controller.dart';
import 'friend_models.dart';

/// Whether a kring action landed, with the server's own Dutch line.
class FriendActionResult {
  const FriendActionResult(this.ok, this.message);

  final bool ok;
  final String message;
}

final friendsRepositoryProvider = Provider((ref) {
  return FriendsRepository(ref.watch(apiClientProvider));
});

/// `/api/v1/friends/*`.
///
/// The endpoints do not exist on the web platform yet (Next.js + Mongoose; see
/// `VRIENDENKRING_PLAN.md` for the schemas, the shared
/// `lib/friends/types.ts` contract and the phases).
///
/// Every call therefore treats a
/// failure - 404 included - as "no vriendenkring": the Start tab shows the
/// invitation card and nothing anywhere breaks. A preview build
/// (`--dart-define=PREVIEW=true`) answers with canned posts instead, so the
/// feed can be reviewed without a backend; that flag is hard-disabled in
/// release builds, so no sample post can ship.
class FriendsRepository {
  const FriendsRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<FriendsFeed> getFeed({int limit = 20}) async {
    if (PreviewConfig.enabled) return _sampleFeed();
    try {
      final response = await _apiClient.dio.get(
        '/friends/feed',
        queryParameters: {'limit': limit},
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return FriendsFeed.empty;
      return FriendsFeed.fromJson(data);
    } on DioException {
      return FriendsFeed.empty;
    } catch (_) {
      return FriendsFeed.empty;
    }
  }

  /// Hearts or unhearts a post. The caller ticks its own state optimistically,
  /// so a failure only has to be reported, not undone here.
  Future<bool> setLike(String postId, bool liked) async {
    if (PreviewConfig.enabled) return true;
    try {
      if (liked) {
        await _apiClient.dio.post('/friends/posts/$postId/like');
      } else {
        await _apiClient.dio.delete('/friends/posts/$postId/like');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A reaction under a post. False when the server refuses, so the caller can
  /// say so instead of pretending it landed.
  Future<bool> addComment(String postId, String body) async {
    if (PreviewConfig.enabled) return true;
    try {
      await _apiClient.dio.post(
        '/friends/posts/$postId/comments',
        data: {'body': body},
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Clears the "nieuw sinds je laatste bezoek" count, on opening Vriendenkring.
  Future<void> markSeen() async {
    if (PreviewConfig.enabled) return;
    try {
      await _apiClient.dio.post('/friends/feed/seen');
    } catch (_) {
      // The badge is a nicety; a failed clear only means it shows once more.
    }
  }

  /// `GET /friends` - the kring, each friend with their streak and plan day.
  Future<FriendsKring> getKring() async {
    if (PreviewConfig.enabled) return _sampleKring();
    try {
      final response = await _apiClient.dio.get('/friends');
      final data = response.data;
      if (data is! Map<String, dynamic>) return FriendsKring.empty;
      return FriendsKring.fromJson(data);
    } catch (_) {
      return FriendsKring.empty;
    }
  }

  /// `GET /friends/requests` - the inbox and the outbox, pending only.
  Future<FriendRequestsResponse> getRequests() async {
    if (PreviewConfig.enabled) return FriendRequestsResponse.empty;
    try {
      final response = await _apiClient.dio.get('/friends/requests');
      final data = response.data;
      if (data is! Map<String, dynamic>) return FriendRequestsResponse.empty;
      return FriendRequestsResponse.fromJson(data);
    } catch (_) {
      return FriendRequestsResponse.empty;
    }
  }

  /// Invite by the code a friend shared, or by user id after a contact match.
  ///
  /// Returns the server's own Dutch line ("Verzoek verstuurd.", "Jullie zijn
  /// nu vrienden.") so the screen can say what happened, or an error message
  /// when it did not land - this is the one call where silence would leave the
  /// reader wondering.
  Future<FriendActionResult> invite({String? code, String? userId, String source = 'code'}) async {
    if (PreviewConfig.enabled) return const FriendActionResult(true, 'Verzoek verstuurd.');
    try {
      final response = await _apiClient.dio.post(
        '/friends/requests',
        data: {
          if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
          if (userId != null && userId.isNotEmpty) 'userId': userId,
          'source': source,
        },
      );
      final data = response.data;
      final message = data is Map && data['message'] is String ? data['message'] as String : null;
      return FriendActionResult(true, message ?? 'Verzoek verstuurd.');
    } on DioException catch (e) {
      final data = e.response?.data;
      final message = data is Map && data['message'] is String ? data['message'] as String : null;
      return FriendActionResult(false, message ?? 'Dat lukte niet. Probeer het zo nog eens.');
    } catch (_) {
      return const FriendActionResult(false, 'Dat lukte niet. Probeer het zo nog eens.');
    }
  }

  Future<bool> respondToRequest(String requestId, String action) async {
    if (PreviewConfig.enabled) return true;
    try {
      await _apiClient.dio.post('/friends/requests/$requestId/$action');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeFriend(String userId) async {
    if (PreviewConfig.enabled) return true;
    try {
      await _apiClient.dio.delete('/friends/$userId');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> blockFriend(String userId) async {
    if (PreviewConfig.enabled) return true;
    try {
      await _apiClient.dio.post('/friends/$userId/block');
      return true;
    } catch (_) {
      return false;
    }
  }

  FriendsKring _sampleKring() => FriendsKring(
    pendingIncoming: 1,
    friends: const [
      FriendSummary(userId: 'u1', name: 'Marieke', streak: 12, planDay: 42, planTotalDays: 365),
      FriendSummary(userId: 'u2', name: 'Jonathan', streak: 3),
      FriendSummary(userId: 'u3', name: 'Hanna', streak: 0, planDay: 7, planTotalDays: 730),
    ],
  );

  FriendsFeed _sampleFeed() {
    final now = DateTime.now();
    return FriendsFeed(
      newActivityCount: 2,
      hasFriends: true,
      posts: [
        FriendPost(
          id: 'p1',
          authorName: 'Marieke',
          kind: FriendPostKind.verse,
          createdAt: now.subtract(const Duration(minutes: 35)),
          reference: 'Psalmen 23:1',
          body: 'De HEERE is mijn Herder, mij zal niets ontbreken.',
          likeCount: 4,
          commentCount: 1,
        ),
        FriendPost(
          id: 'p2',
          authorName: 'Jonathan',
          kind: FriendPostKind.milestone,
          createdAt: now.subtract(const Duration(hours: 5)),
          body: 'Dag 30 van Bijbel in een jaar gehaald.',
          likeCount: 7,
          likedByMe: true,
          commentCount: 2,
        ),
        FriendPost(
          id: 'p3',
          authorName: 'Hanna',
          kind: FriendPostKind.note,
          createdAt: now.subtract(const Duration(days: 1)),
          reference: 'Romeinen 8',
          body: 'Blijven stilstaan bij "niets kan ons scheiden". Dat hield mij '
              'vandaag op de been.',
          likeCount: 2,
          commentCount: 0,
        ),
      ],
    );
  }
}
