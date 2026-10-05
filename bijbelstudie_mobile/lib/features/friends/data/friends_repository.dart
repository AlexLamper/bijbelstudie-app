import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/preview_config.dart';
import '../../auth/present/auth_controller.dart';
import 'friend_models.dart';
import 'friends_failure.dart';

/// Whether a kring action landed, with the server's own Dutch line.
class FriendActionResult {
  const FriendActionResult(this.ok, this.message);

  final bool ok;
  final String message;
}

/// `MAX_POST_BODY` in `lib/friends/service.ts`.
const int maxFriendPostBody = 2000;

/// `MAX_REPORT_NOTE` in `lib/friends/service.ts` - the free-text note on a
/// melding is trimmed to this, here and again there.
const int maxFriendReportNote = 1000;

/// What [FriendsRepository.updateSettings] answers: whether the PATCH landed,
/// a Dutch line, and the **whole** settings object the server replied with.
///
/// `PATCH /friends/settings` returns the full `FriendSettings` after writing,
/// so a screen never has to guess what the other switches are now - it adopts
/// [settings] instead of patching its own copy.
class FriendSettingsResult {
  const FriendSettingsResult({required this.ok, required this.message, this.settings});

  final bool ok;
  final String message;

  /// The settings as the server now holds them, or null when it did not
  /// answer - in which case the screen keeps what it had and says [message].
  final FriendSettings? settings;
}

/// What [FriendsRepository.sharePost] answers: whether it landed, a Dutch line
/// to show, and the post the server created (`{ "post": ... }`) when it did.
class FriendShareResult {
  const FriendShareResult({required this.ok, required this.message, this.post});

  final bool ok;
  final String message;
  final FriendPost? post;
}

final friendsRepositoryProvider = Provider((ref) {
  return FriendsRepository(ref.watch(apiClientProvider));
});

/// `/api/v1/friends/*` - live on the web platform (Next.js + Mongoose; the
/// wire contract is `lib/friends/types.ts` there, the implementation
/// `lib/friends/service.ts`, and `VRIENDENKRING_PLAN.md` §5 lists the routes).
///
/// Because the server now answers, the reads no longer flatten every failure
/// into "no vriendenkring" - a reader told "nodig vrienden uit" while the
/// server is down goes looking for a bug in their own account. They throw a
/// [FriendsException] with a named [FriendsFailure] instead, and the screens
/// print it with a retry.
///
/// What is still degraded on purpose:
///
/// * **404** on a read is a real empty result: no kring, no posts, no
///   verzoeken. That is the shipped-safe guarantee of §10 - the app never
///   crashes or shows a broken screen when the server says nothing.
/// * **404 / 503** from `/friends/discovery/*` is the "feature off" state
///   (`FRIENDS_CONTACT_PEPPER` is unset in every environment right now), so
///   those degrade to [FriendsFailure.unavailable], which the UI renders as
///   nothing at all rather than as an error.
/// * **Mutations** still answer `bool` or [FriendActionResult]: a heart that
///   did not land is reported where it was tapped, not as a screen state.
///
/// A preview build (`--dart-define=PREVIEW=true`) answers with canned posts
/// instead, so the feed can be reviewed without a backend; that flag is
/// hard-disabled in release builds, so no sample post can ship.
class FriendsRepository {
  const FriendsRepository(this._apiClient);

  final ApiClient _apiClient;

  /// `GET /friends/feed?limit=&before=`.
  ///
  /// [before] is the cursor: the `createdAt` of the oldest post already shown,
  /// sent as UTC ISO 8601 because that is what the server compares against.
  /// `FEED_PAGE_SIZE` is 20 server-side and 50 is its ceiling.
  ///
  /// Throws [FriendsException] on a network or server failure; a 404 is an
  /// empty feed, not a failure.
  Future<FriendsFeed> getFeed({int limit = 20, DateTime? before}) async {
    if (PreviewConfig.enabled) return before == null ? _sampleFeed() : FriendsFeed.empty;
    final page = limit.clamp(1, 50);
    try {
      final response = await _apiClient.dio.get(
        '/friends/feed',
        queryParameters: {
          'limit': page,
          if (before != null) 'before': before.toUtc().toIso8601String(),
        },
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return FriendsFeed.empty;
      final feed = FriendsFeed.fromJson(data);
      // The response carries no cursor, so a full page is the only honest
      // reason to think there is more.
      return feed.copyWith(hasMore: feed.posts.length >= page);
    } on DioException catch (e) {
      if (friendsStatusIsAbsent(e.response?.statusCode)) return FriendsFeed.empty;
      throw friendsFailureFrom(e);
    } catch (e) {
      throw friendsFailureFrom(e);
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
  ///
  /// Throws [FriendsException]; a 404 is an empty kring.
  Future<FriendsKring> getKring() async {
    if (PreviewConfig.enabled) return _sampleKring();
    try {
      final response = await _apiClient.dio.get('/friends');
      final data = response.data;
      if (data is! Map<String, dynamic>) return FriendsKring.empty;
      return FriendsKring.fromJson(data);
    } on DioException catch (e) {
      if (friendsStatusIsAbsent(e.response?.statusCode)) return FriendsKring.empty;
      throw friendsFailureFrom(e);
    } catch (e) {
      throw friendsFailureFrom(e);
    }
  }

  /// `GET /friends/requests` - the inbox and the outbox, pending only.
  ///
  /// Throws [FriendsException]; a 404 is an empty inbox.
  Future<FriendRequestsResponse> getRequests() async {
    if (PreviewConfig.enabled) return FriendRequestsResponse.empty;
    try {
      final response = await _apiClient.dio.get('/friends/requests');
      final data = response.data;
      if (data is! Map<String, dynamic>) return FriendRequestsResponse.empty;
      return FriendRequestsResponse.fromJson(data);
    } on DioException catch (e) {
      if (friendsStatusIsAbsent(e.response?.statusCode)) {
        return FriendRequestsResponse.empty;
      }
      throw friendsFailureFrom(e);
    } catch (e) {
      throw friendsFailureFrom(e);
    }
  }

  /// `GET /friends/posts/:id/comments` - the whole thread, oldest first.
  ///
  /// There is no pagination on this route: the server returns every comment
  /// (capped at 200) with no cursor and no total, so no page shape is assumed
  /// here. A 404 means the post itself is gone or no longer visible, which is
  /// worth saying, so that one throws [FriendsFailure.notFound] rather than
  /// quietly showing an empty thread.
  Future<List<FriendPostComment>> listComments(String postId) async {
    if (PreviewConfig.enabled) return _sampleComments(postId);
    try {
      final response = await _apiClient.dio.get('/friends/posts/$postId/comments');
      final data = response.data;
      if (data is! Map<String, dynamic>) return const [];
      return FriendPostComment.listFromJson(data);
    } catch (e) {
      throw friendsFailureFrom(e);
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

  /// `POST /friends/:userId/block`.
  ///
  /// The server unfriends first and then blocks, and enforces the block both
  /// ways: neither side appears in the other's feed, neither can send a
  /// verzoek, and neither turns up in contact matching.
  Future<bool> blockFriend(String userId) async {
    if (PreviewConfig.enabled) return true;
    try {
      await _apiClient.dio.post('/friends/$userId/block');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// `DELETE /friends/:userId/block`.
  ///
  /// Undoing a block does not put the vriendschap back: blocking deleted the
  /// pair document, so the two have to re-add each other. The server says so
  /// in its own message, which is passed through rather than reworded.
  Future<FriendActionResult> unblockFriend(String userId) async {
    if (PreviewConfig.enabled) {
      return const FriendActionResult(true, 'Blokkering opgeheven.');
    }
    try {
      final response = await _apiClient.dio.delete('/friends/$userId/block');
      return FriendActionResult(
        true,
        friendsServerMessage(response.data) ?? 'Blokkering opgeheven.',
      );
    } on DioException catch (e) {
      return FriendActionResult(
        false,
        friendsServerMessage(e.response?.data) ?? friendsFailureFrom(e).message,
      );
    } catch (e) {
      return FriendActionResult(false, friendsFailureFrom(e).message);
    }
  }

  /// `GET /friends/settings` - findability, the auto-share switches and the
  /// blocked list, which rides along rather than costing its own call.
  ///
  /// Throws [FriendsException]; a 404 is the default, all-off settings.
  Future<FriendSettings> getSettings() async {
    if (PreviewConfig.enabled) return FriendSettings.empty;
    try {
      final response = await _apiClient.dio.get('/friends/settings');
      final data = response.data;
      if (data is! Map<String, dynamic>) return FriendSettings.empty;
      return FriendSettings.fromJson(data);
    } on DioException catch (e) {
      if (friendsStatusIsAbsent(e.response?.statusCode)) return FriendSettings.empty;
      throw friendsFailureFrom(e);
    } catch (e) {
      throw friendsFailureFrom(e);
    }
  }

  /// `PATCH /friends/settings` - flip one switch, or a few, and adopt what the
  /// server answers.
  ///
  /// Only the fields [update] actually sets go on the wire, each on its own
  /// named path (`autoShare.verses`, never the whole `autoShare` object), so
  /// turning on "verzen" can never silently reset "mijlpalen". The reply is
  /// the complete [FriendSettings], which the caller should adopt wholesale
  /// instead of patching its own copy.
  ///
  /// A mutation, so it answers a result rather than throwing: a switch that
  /// did not land is reported where it was tapped.
  Future<FriendSettingsResult> updateSettings(FriendSettingsUpdate update) async {
    if (update.isEmpty) {
      // Nothing to write. Saying so without a round trip is the same outcome,
      // sooner, and keeps a no-op tap off the network.
      return const FriendSettingsResult(ok: true, message: 'Niets gewijzigd.');
    }
    if (PreviewConfig.enabled) {
      return const FriendSettingsResult(
        ok: true,
        message: 'Opgeslagen.',
        settings: FriendSettings.empty,
      );
    }
    try {
      final response = await _apiClient.dio.patch('/friends/settings', data: update.toJson());
      final data = response.data;
      return FriendSettingsResult(
        ok: true,
        message: friendsServerMessage(data) ?? 'Opgeslagen.',
        settings: data is Map<String, dynamic> ? FriendSettings.fromJson(data) : null,
      );
    } on DioException catch (e) {
      return FriendSettingsResult(
        ok: false,
        message: friendsServerMessage(e.response?.data) ?? friendsFailureFrom(e).message,
      );
    } catch (e) {
      return FriendSettingsResult(ok: false, message: friendsFailureFrom(e).message);
    }
  }

  /// `GET /friends/:userId` - one person's profile.
  ///
  /// Unlike the list reads, a 404 here is **not** folded into an empty result:
  /// there is no honest empty profile, and the server answers 404 both for a
  /// person who does not exist and for one the reader may not see at all
  /// (never 403 - being in the graph is itself private). So this throws
  /// [FriendsFailure.notFound] and the screen says "Deze persoon is niet
  /// gevonden" rather than drawing a blank card.
  ///
  /// Mind the grading on the way out: for a non-friend the server zeroes
  /// `streak`, `planDay`, `planTotalDays` and `friendsSince`, and
  /// [FriendProfileView.friends] is null, not `[]`. Check
  /// [FriendProfileView.isFriend] and [FriendProfileView.canSeeFriends].
  Future<FriendProfileView> getProfile(String userId) async {
    if (PreviewConfig.enabled) return _sampleProfile(userId);
    try {
      final response = await _apiClient.dio.get('/friends/$userId');
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FriendsException(FriendsFailure.unknown);
      }
      return FriendProfileView.fromJson(data);
    } catch (e) {
      throw friendsFailureFrom(e);
    }
  }

  /// `GET /friends/suggestions` - "Mensen die je misschien kent".
  ///
  /// Friends of friends, most shared friends first, capped at
  /// [maxFriendSuggestions] (20) server-side, with
  /// [FriendSummary.mutualCount] set on every row. A reader with no friends
  /// gets an empty list, which is the honest answer rather than an error:
  /// there are no friends-of-friends to suggest yet.
  ///
  /// Throws [FriendsException]; a 404 is an empty list.
  Future<FriendSuggestionsResponse> getSuggestions() async {
    if (PreviewConfig.enabled) return _sampleSuggestions();
    try {
      final response = await _apiClient.dio.get('/friends/suggestions');
      final data = response.data;
      if (data is! Map<String, dynamic>) return FriendSuggestionsResponse.empty;
      return FriendSuggestionsResponse.fromJson(data);
    } on DioException catch (e) {
      if (friendsStatusIsAbsent(e.response?.statusCode)) {
        return FriendSuggestionsResponse.empty;
      }
      throw friendsFailureFrom(e);
    } catch (e) {
      throw friendsFailureFrom(e);
    }
  }

  /// `POST /friends/posts/:id/report` - melden, the post itself or, with
  /// [commentId], one reaction under it.
  ///
  /// Reporting the same thing twice is an upsert server-side (a unique index
  /// on reporter + target), so a second tap updates the reason instead of
  /// filling the moderation queue - and is reported back as success, because
  /// to the reader it plainly worked.
  ///
  /// The route is throttled at 10 an hour per account and refuses a melding on
  /// the reader's own content with a 400; both come back as the server's own
  /// Dutch line in the result.
  Future<FriendActionResult> reportPost({
    required String postId,
    required FriendReportReason reason,
    String? note,
    String? commentId,
  }) async {
    final text = note?.trim() ?? '';
    final trimmed =
        text.length > maxFriendReportNote ? text.substring(0, maxFriendReportNote) : text;
    if (PreviewConfig.enabled) {
      return const FriendActionResult(true, 'Bedankt. We kijken ernaar.');
    }
    try {
      final response = await _apiClient.dio.post(
        '/friends/posts/$postId/report',
        data: {
          'reason': friendReportReasonWire(reason),
          if (trimmed.isNotEmpty) 'note': trimmed,
          if (commentId != null && commentId.isNotEmpty) 'commentId': commentId,
        },
      );
      return FriendActionResult(
        true,
        friendsServerMessage(response.data) ?? 'Bedankt. We kijken ernaar.',
      );
    } on DioException catch (e) {
      return FriendActionResult(
        false,
        friendsServerMessage(e.response?.data) ?? friendsFailureFrom(e).message,
      );
    } catch (e) {
      return FriendActionResult(false, friendsFailureFrom(e).message);
    }
  }

  // ---------------------------------------------------------- contact match

  /// `GET /friends/discovery/pepper` - the HMAC pepper to hash an address book
  /// with, or **null when contact matching is switched off**.
  ///
  /// Every `/friends/discovery/*` route answers 503 while
  /// `FRIENDS_CONTACT_PEPPER` is unset, which is where all environments stand
  /// right now, and that is the intended "feature off" state rather than a
  /// fault. So 404/503 comes back as null, not as a throw. A real network or
  /// server failure still throws [FriendsException], because "we konden het
  /// niet ophalen" and "dit kan niet" are different sentences.
  ///
  /// The pepper is fetched rather than shipped so no binary carries a secret
  /// and it can be rotated. Hold it in memory for the one matching run and
  /// never write it to disk.
  Future<String?> getContactPepper() async {
    if (PreviewConfig.enabled) return null;
    try {
      final response = await _apiClient.dio.get('/friends/discovery/pepper');
      final data = response.data;
      if (data is! Map<String, dynamic>) return null;
      final pepper = (data['pepper'] as String?)?.trim();
      return pepper == null || pepper.isEmpty ? null : pepper;
    } on DioException catch (e) {
      if (friendsStatusIsAbsent(e.response?.statusCode)) return null;
      throw friendsFailureFrom(e);
    } catch (e) {
      throw friendsFailureFrom(e);
    }
  }

  /// Whether contact matching is available at all - the cheap question a
  /// screen asks before offering "Vind je vrienden".
  ///
  /// Never throws and never reads as an error: a server that is down, a reader
  /// who is offline and a pepper that is unset all answer false, because in
  /// every one of those cases the honest thing is to show no contacts entry
  /// point at all rather than an error card for a feature nobody asked for
  /// yet. Use [getContactPepper] when the difference does matter.
  Future<bool> isContactDiscoveryAvailable() async {
    try {
      return await getContactPepper() != null;
    } catch (_) {
      return false;
    }
  }

  /// `POST /friends/discovery/hashes` - the reader's own number and e-mail, so
  /// others can find them. The second consent, separate from reading an
  /// address book.
  ///
  /// These go up in the clear and are hashed server-side; see
  /// [OwnContactIdentifiers]. False when it did not land, including the
  /// feature-off 503 - a switch that did not take is reported where it was
  /// tapped.
  Future<bool> saveOwnContactIdentifiers(OwnContactIdentifiers identifiers) async {
    if (PreviewConfig.enabled) return false;
    try {
      await _apiClient.dio.post('/friends/discovery/hashes', data: identifiers.toJson());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// `POST /friends/discovery/match` - hashed contacts in, accounts out.
  ///
  /// Nothing uploaded here is stored: the match runs and the hashes are
  /// dropped. Only accounts that chose to be findable come back, with name and
  /// picture alone, capped at [maxContactMatchResults] (200), and existing
  /// friends plus anyone blocked either way are already filtered out.
  ///
  /// This is the hardest-throttled route in the feature - 5 calls an hour per
  /// account, at most [maxContactMatchHashes] (2000) hashes a call - so the
  /// hashes are capped and de-duplicated before sending
  /// ([ContactDiscoveryHashes] does that in its constructor) and an empty set
  /// never spends a call.
  ///
  /// Answers [ContactMatchResult.unavailable] for the feature-off 503 rather
  /// than throwing, so the caller can hide the section instead of showing an
  /// error. The hashing itself is not this layer's job.
  Future<ContactMatchResult> matchContacts(ContactDiscoveryHashes hashes) async {
    if (hashes.isEmpty) return ContactMatchResult.none;
    if (PreviewConfig.enabled) return ContactMatchResult.unavailable;
    try {
      final response = await _apiClient.dio.post(
        '/friends/discovery/match',
        data: hashes.toJson(),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return ContactMatchResult.none;
      return ContactMatchResult.fromJson(data);
    } on DioException catch (e) {
      if (friendsStatusIsAbsent(e.response?.statusCode)) {
        return ContactMatchResult.unavailable;
      }
      // A 429 is worth saying out loud ("Je hebt je contacten net al
      // gecontroleerd."), so the server's own line is carried through.
      return ContactMatchResult(
        message: friendsServerMessage(e.response?.data) ?? friendsFailureFrom(e).message,
      );
    } catch (e) {
      return ContactMatchResult(message: friendsFailureFrom(e).message);
    }
  }

  /// `DELETE /friends/discovery` - forget my hashes and stop being findable.
  /// The counterpart to the consent, and it really deletes.
  Future<bool> forgetContactDiscovery() async {
    if (PreviewConfig.enabled) return false;
    try {
      await _apiClient.dio.delete('/friends/discovery');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// `POST /friends/posts` - share a verse, a note or a milestone by hand.
  ///
  /// A post is a copy of what it was made from, never a reference to it, so
  /// [body] and [reference] are the text as the kring will read it.
  /// [sourceId] is the server's idempotency handle (the verse date, the note
  /// id), capped at 200 characters there.
  ///
  /// The body is trimmed to `MAX_POST_BODY` (2000) here so a long note is
  /// shortened rather than refused, and the server does the same again.
  /// Nothing calls this yet; the verse card, the note row and the settings
  /// switches are wired separately.
  Future<FriendShareResult> sharePost({
    required FriendPostKind kind,
    String body = '',
    String? reference,
    String? sourceId,
  }) async {
    final text = body.trim();
    final trimmed = text.length > maxFriendPostBody ? text.substring(0, maxFriendPostBody) : text;
    final ref = reference?.trim() ?? '';
    if (trimmed.isEmpty && ref.isEmpty) {
      // The server answers 400 EMPTY_POST for this; saying so without a round
      // trip is the same sentence, sooner.
      return const FriendShareResult(
        ok: false,
        message: 'Een bericht heeft tekst of een verwijzing nodig.',
      );
    }
    if (PreviewConfig.enabled) {
      return const FriendShareResult(ok: true, message: 'Gedeeld met je vriendenkring.');
    }

    try {
      final response = await _apiClient.dio.post(
        '/friends/posts',
        data: {
          'kind': friendPostKindWire(kind),
          'body': trimmed,
          if (ref.isNotEmpty) 'reference': ref,
          if (sourceId != null && sourceId.isNotEmpty) 'sourceId': sourceId,
        },
      );
      final data = response.data;
      final post = data is Map<String, dynamic> && data['post'] is Map<String, dynamic>
          ? FriendPost.fromJson(data['post'] as Map<String, dynamic>)
          : null;
      return FriendShareResult(
        ok: true,
        message: friendsServerMessage(data) ?? 'Gedeeld met je vriendenkring.',
        post: post,
      );
    } on DioException catch (e) {
      return FriendShareResult(
        ok: false,
        message: friendsServerMessage(e.response?.data) ?? friendsFailureFrom(e).message,
      );
    } catch (e) {
      return FriendShareResult(ok: false, message: friendsFailureFrom(e).message);
    }
  }

  /// A preview profile of a friend: the numbers are filled, and `friends` is a
  /// list rather than null, because [FriendProfileView.isFriend] is true.
  FriendProfileView _sampleProfile(String userId) => FriendProfileView(
    user: FriendSummary(
      userId: userId,
      name: 'Marieke',
      streak: 12,
      planDay: 42,
      planTotalDays: 365,
      friendsSince: DateTime.now().subtract(const Duration(days: 96)),
      mutualCount: 2,
    ),
    isFriend: true,
    friendCount: 3,
    mutualCount: 2,
    mutuals: const [
      FriendSummary(userId: 'u2', name: 'Jonathan', streak: 3, mutualCount: 2),
      FriendSummary(userId: 'u3', name: 'Hanna', streak: 0, mutualCount: 1),
    ],
    friends: const [
      FriendSummary(userId: 'u2', name: 'Jonathan', streak: 3),
      FriendSummary(userId: 'u3', name: 'Hanna', streak: 0),
      FriendSummary(userId: 'u4', name: 'Bram', streak: 21),
    ],
  );

  FriendSuggestionsResponse _sampleSuggestions() => const FriendSuggestionsResponse(
    suggestions: [
      FriendSummary(userId: 's1', name: 'Bram', streak: 21, mutualCount: 3),
      FriendSummary(userId: 's2', name: 'Lydia', streak: 5, mutualCount: 1),
    ],
  );

  List<FriendPostComment> _sampleComments(String postId) {
    final now = DateTime.now();
    return [
      FriendPostComment(
        id: 'c1',
        postId: postId,
        authorName: 'Jonathan',
        body: 'Mooi, daar las ik vanmorgen ook in.',
        createdAt: now.subtract(const Duration(minutes: 20)),
      ),
      FriendPostComment(
        id: 'c2',
        postId: postId,
        authorName: 'Hanna',
        body: 'Dank voor het delen.',
        createdAt: now.subtract(const Duration(minutes: 4)),
      ),
    ];
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
