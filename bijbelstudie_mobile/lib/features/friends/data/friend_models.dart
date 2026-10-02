/// Vriendenkring: the people a reader follows and what they post.
///
/// The server does not answer `/friends` yet (see
/// `VRIENDENKRING_PLAN.md`), so the repository degrades to an empty feed
/// and every surface renders its "nog geen vrienden" state. The models are the
/// shape that plan commits to, so wiring the endpoint later changes the
/// repository only.
library;

/// What one post in the feed is about.
enum FriendPostKind {
  /// A tekst van de dag someone hearted or shared.
  verse,

  /// "Dag 30 van Bijbel in een jaar", a badge, a finished study.
  milestone,

  /// A note someone chose to share with their vriendenkring.
  note,

  /// A kind a newer server sends that this build does not know; rendered as a
  /// plain note rather than dropped.
  other,
}

FriendPostKind friendPostKindFrom(String? raw) => switch (raw) {
  'verse' => FriendPostKind.verse,
  'milestone' => FriendPostKind.milestone,
  'note' => FriendPostKind.note,
  _ => FriendPostKind.other,
};

/// One card in the feed.
class FriendPost {
  const FriendPost({
    required this.id,
    required this.authorName,
    required this.kind,
    required this.createdAt,
    this.authorId = '',
    this.authorImage,
    this.reference,
    this.body = '',
    this.likeCount = 0,
    this.likedByMe = false,
    this.commentCount = 0,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorImage;
  final FriendPostKind kind;
  final DateTime createdAt;

  /// "Johannes 3:16" for a verse, null otherwise.
  final String? reference;

  /// The verse text, the milestone line, or the shared note.
  final String body;

  final int likeCount;
  final bool likedByMe;
  final int commentCount;

  FriendPost copyWith({int? likeCount, bool? likedByMe, int? commentCount}) {
    return FriendPost(
      id: id,
      authorId: authorId,
      authorName: authorName,
      authorImage: authorImage,
      kind: kind,
      createdAt: createdAt,
      reference: reference,
      body: body,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
      commentCount: commentCount ?? this.commentCount,
    );
  }

  factory FriendPost.fromJson(Map<String, dynamic> json) {
    final created = json['createdAt'];
    return FriendPost(
      id: '${json['id'] ?? ''}',
      authorId: '${json['authorId'] ?? ''}',
      authorName: (json['authorName'] as String?)?.trim() ?? '',
      authorImage: (json['authorImage'] as String?)?.trim(),
      kind: friendPostKindFrom(json['kind'] as String?),
      createdAt: created is String
          ? (DateTime.tryParse(created)?.toLocal() ?? DateTime.now())
          : DateTime.now(),
      reference: (json['reference'] as String?)?.trim(),
      body: (json['body'] as String?)?.trim() ?? '',
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      likedByMe: json['likedByMe'] == true,
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// `GET /friends/feed`: the posts, how many are new since the reader last
/// opened Vriendenkring, and whether they have any friends at all.
///
/// [hasFriends] is its own field rather than `posts.isNotEmpty`: a reader with
/// friends who have posted nothing gets the quiet empty feed, not the
/// invitation.
class FriendsFeed {
  const FriendsFeed({
    this.posts = const [],
    this.newActivityCount = 0,
    this.hasFriends = false,
  });

  static const empty = FriendsFeed();

  final List<FriendPost> posts;
  final int newActivityCount;
  final bool hasFriends;

  FriendsFeed copyWith({List<FriendPost>? posts, int? newActivityCount}) {
    return FriendsFeed(
      posts: posts ?? this.posts,
      newActivityCount: newActivityCount ?? this.newActivityCount,
      hasFriends: hasFriends,
    );
  }

  factory FriendsFeed.fromJson(Map<String, dynamic> json) {
    final raw = json['posts'];
    final posts = raw is List
        ? [
            for (final item in raw)
              if (item is Map<String, dynamic>) FriendPost.fromJson(item),
          ]
        : const <FriendPost>[];
    return FriendsFeed(
      posts: posts,
      newActivityCount: (json['newActivityCount'] as num?)?.toInt() ?? 0,
      hasFriends: json['hasFriends'] == true || posts.isNotEmpty,
    );
  }
}

/// A person, as a kring list or a verzoek shows them. Never an e-mail: a kring
/// is not a directory (the server does not send one either).
class FriendSummary {
  const FriendSummary({
    required this.userId,
    required this.name,
    this.image,
    this.streak = 0,
    this.planDay,
    this.planTotalDays,
    this.friendsSince,
  });

  final String userId;
  final String name;
  final String? image;

  /// Days in a row, for the row's flame. 0 when they have none.
  final int streak;

  /// "Dag 42 van 365" is built from these two; both null without a plan.
  final int? planDay;
  final int? planTotalDays;

  final DateTime? friendsSince;

  /// "Dag 42 van 365", or null for someone who runs no reading plan.
  String? get planLabel =>
      planDay == null || planTotalDays == null ? null : 'Dag $planDay van $planTotalDays';

  factory FriendSummary.fromJson(Map<String, dynamic> json) {
    final since = json['friendsSince'];
    return FriendSummary(
      userId: '${json['userId'] ?? ''}',
      name: (json['name'] as String?)?.trim() ?? '',
      image: (json['image'] as String?)?.trim(),
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      planDay: (json['planDay'] as num?)?.toInt(),
      planTotalDays: (json['planTotalDays'] as num?)?.toInt(),
      friendsSince: since is String ? DateTime.tryParse(since)?.toLocal() : null,
    );
  }
}

/// `GET /friends`.
class FriendsKring {
  const FriendsKring({this.friends = const [], this.pendingIncoming = 0});

  static const empty = FriendsKring();

  final List<FriendSummary> friends;

  /// So the Verzoeken tab can show a count without a second request.
  final int pendingIncoming;

  factory FriendsKring.fromJson(Map<String, dynamic> json) {
    final raw = json['friends'];
    return FriendsKring(
      friends: raw is List
          ? [
              for (final item in raw)
                if (item is Map<String, dynamic>) FriendSummary.fromJson(item),
            ]
          : const [],
      pendingIncoming: (json['pendingIncoming'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One pending verzoek, in either direction.
class FriendRequestView {
  const FriendRequestView({
    required this.id,
    required this.user,
    this.status = 'pending',
    this.source = 'code',
    this.createdAt,
  });

  final String id;

  /// The other person: the sender for an incoming verzoek, the recipient for
  /// an outgoing one.
  final FriendSummary user;

  final String status;
  final String source;
  final DateTime? createdAt;

  factory FriendRequestView.fromJson(Map<String, dynamic> json) {
    final created = json['createdAt'];
    final user = json['user'];
    return FriendRequestView(
      id: '${json['id'] ?? ''}',
      user: user is Map<String, dynamic>
          ? FriendSummary.fromJson(user)
          : const FriendSummary(userId: '', name: ''),
      status: (json['status'] as String?) ?? 'pending',
      source: (json['source'] as String?) ?? 'code',
      createdAt: created is String ? DateTime.tryParse(created)?.toLocal() : null,
    );
  }
}

/// `GET /friends/requests`.
class FriendRequestsResponse {
  const FriendRequestsResponse({this.incoming = const [], this.outgoing = const []});

  static const empty = FriendRequestsResponse();

  final List<FriendRequestView> incoming;
  final List<FriendRequestView> outgoing;

  bool get isEmpty => incoming.isEmpty && outgoing.isEmpty;

  factory FriendRequestsResponse.fromJson(Map<String, dynamic> json) {
    List<FriendRequestView> read(Object? raw) => raw is List
        ? [
            for (final item in raw)
              if (item is Map<String, dynamic>) FriendRequestView.fromJson(item),
          ]
        : const [];
    return FriendRequestsResponse(
      incoming: read(json['incoming']),
      outgoing: read(json['outgoing']),
    );
  }
}

const _months = [
  'januari', 'februari', 'maart', 'april', 'mei', 'juni',
  'juli', 'augustus', 'september', 'oktober', 'november', 'december',
];

/// How long ago a post landed, as a feed writes it: "nu", "12 min", "3 u",
/// "gisteren", then the date. Written out rather than pulled from `intl` so
/// the app still ships no extra locale data.
String friendPostWhen(DateTime when, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final minutes = today.difference(when).inMinutes;
  if (minutes < 1) return 'nu';
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours u';
  final days = DateTime(today.year, today.month, today.day)
      .difference(DateTime(when.year, when.month, when.day))
      .inDays;
  if (days <= 1) return 'gisteren';
  if (days < 7) return '$days dagen';
  return '${when.day} ${_months[when.month - 1]}';
}
