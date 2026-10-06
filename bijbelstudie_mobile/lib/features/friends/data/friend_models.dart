/// Vriendenkring: the people a reader follows and what they post.
///
/// These are the live wire shapes, mirroring `lib/friends/types.ts` in the
/// website repo line for line; the server answers all of `/friends/*`
/// (feed, posts, likes, comments, kring, requests, settings - see
/// `VRIENDENKRING_PLAN.md` §5). Change this file in the same pass as that one.
///
/// Contact matching (`/friends/discovery/*`) is the one part that is off: it
/// answers 503 while `FRIENDS_CONTACT_PEPPER` is unset, which the repository
/// degrades quietly (`FriendsFailure.unavailable`).
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

/// What `POST /friends/posts` wants in `kind`. The server coerces anything it
/// does not know to `note`, so [FriendPostKind.other] is sent as `note` rather
/// than relying on that.
String friendPostKindWire(FriendPostKind kind) => switch (kind) {
  FriendPostKind.verse => 'verse',
  FriendPostKind.milestone => 'milestone',
  FriendPostKind.note || FriendPostKind.other => 'note',
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
    this.hasMore = false,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  static const empty = FriendsFeed();

  final List<FriendPost> posts;
  final int newActivityCount;
  final bool hasFriends;

  /// Client-side only, never on the wire: whether another page may exist.
  ///
  /// `GET /friends/feed` sends no cursor or total, so the only honest signal is
  /// that the page came back full; the repository sets this, and an empty next
  /// page is what finally clears it.
  final bool hasMore;

  /// Client-side only: a `before=` page is in flight.
  final bool loadingMore;

  /// Client-side only: the last "Meer laden" did not land, so the button says
  /// so instead of silently doing nothing.
  final bool loadMoreFailed;

  FriendsFeed copyWith({
    List<FriendPost>? posts,
    int? newActivityCount,
    bool? hasMore,
    bool? loadingMore,
    bool? loadMoreFailed,
  }) {
    return FriendsFeed(
      posts: posts ?? this.posts,
      newActivityCount: newActivityCount ?? this.newActivityCount,
      hasFriends: hasFriends,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
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
    this.mutualCount,
    this.publicProfile,
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

  /// Friends this person and the reader have in common - **null means unknown,
  /// not zero.**
  ///
  /// Optional on the wire on purpose (`mutualCount?: number` in
  /// `lib/friends/types.ts`): `GET /friends` does not pay for the count, while
  /// `/friends/suggestions` and `/friends/:userId` do. A row that arrived
  /// without it must read as "we weten het niet", because printing
  /// "0 gezamenlijke vrienden" for an unknown count is simply a lie. So this
  /// is `int?` with no default, and [mutualLabel] is the only sanctioned way
  /// to turn it into a line.
  final int? mutualCount;

  /// Whether `/gebruiker/<userId>` - this person's public progress tree - exists.
  ///
  /// Optional and additive like [mutualCount] (`publicProfile?: boolean` in
  /// `lib/friends/types.ts`, derived server-side from `isPublicTree`): an
  /// absent field reads as "no public page", so a build that does not know it
  /// simply does not link there. A link that 404s is worse than a name that is
  /// not a link, so only an explicit `true` opens the way on.
  final bool? publicProfile;

  /// True only when the public tree page is known to be there.
  bool get hasPublicTree => publicProfile == true;

  /// Whether the count is known at all. [mutualCount] of 0 is known-zero.
  bool get hasMutualCount => mutualCount != null;

  /// "3 gezamenlijke vrienden", or null when there is nothing honest to say -
  /// either because the count did not come back, or because it is 0 and a row
  /// of nothing-in-common deserves no line.
  String? get mutualLabel {
    final count = mutualCount;
    if (count == null || count <= 0) return null;
    return count == 1 ? '1 gezamenlijke vriend' : '$count gezamenlijke vrienden';
  }

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
      // No `?? 0`: an absent field has to stay absent all the way to the UI.
      mutualCount: (json['mutualCount'] as num?)?.toInt(),
      // Likewise absent-safe: anything that is not a real boolean stays null,
      // which reads as "no public tree page".
      publicProfile: json['publicProfile'] is bool ? json['publicProfile'] as bool : null,
    );
  }

  /// The `friends` / `mutuals` / `suggestions` array of a response, skipping
  /// anything that is not an object.
  static List<FriendSummary> listFrom(Object? raw) => raw is List
      ? [
          for (final item in raw)
            if (item is Map<String, dynamic>) FriendSummary.fromJson(item),
        ]
      : const [];
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

/// `GET /friends/:userId` - one person's profile.
///
/// What is visible to whom is graded server-side, not here
/// (`getFriendProfile` in `lib/friends/service.ts`):
///
/// * anyone who is not blocked sees [user], [friendCount], [mutualCount] and
///   the [mutuals] themselves - those are the reader's *own* friends, so no
///   new name reaches them;
/// * [FriendSummary.streak], `planDay`, `planTotalDays` and `friendsSince` on
///   [user] come back zeroed/null for a non-friend, so a profile card must not
///   read "0 dagen op rij" as a fact about them - check [isFriend] first;
/// * [friends] is their whole kring **for an actual friend only**.
///
/// The server answers 404 - never 403 - for a person the reader may not see at
/// all, because whether somebody is in the graph is itself private.
class FriendProfileView {
  const FriendProfileView({
    required this.user,
    this.isFriend = false,
    this.friendCount = 0,
    this.mutuals = const [],
    this.mutualCount = 0,
    this.friends,
  });

  final FriendSummary user;

  /// Whether the reader and this person are vrienden. Gates everything that is
  /// zeroed out above, so read it before trusting a number on [user].
  final bool isFriend;

  /// How many people are in their kring. A count is public; the list is not.
  final int friendCount;

  /// The shared friends, named. Capped at `MUTUALS_SHOWN` (12) server-side, so
  /// `mutuals.length` is *not* the total - [mutualCount] is.
  final List<FriendSummary> mutuals;

  final int mutualCount;

  /// Their kring - **null means "niet voor jou te zien", `[]` means they have
  /// nobody.**
  ///
  /// This is the one field in the whole contract where null and empty are
  /// different facts, so it is nullable with no default and the parser never
  /// substitutes a list. Do not read it directly in a widget: ask
  /// [canSeeFriends] first, or use [visibleFriends], which is null for exactly
  /// the same reason.
  final List<FriendSummary>? friends;

  /// True when [friends] was sent, so an empty list may honestly be rendered
  /// as "nog geen vrienden" rather than as a locked section.
  bool get canSeeFriends => friends != null;

  /// Their kring when it is the reader's to see, otherwise null. Exists so a
  /// caller cannot reach for `friends ?? const []` and quietly turn "mag je
  /// niet zien" into "heeft niemand".
  List<FriendSummary>? get visibleFriends => friends;

  /// More shared friends than [mutuals] names. "en 7 anderen".
  int get hiddenMutualCount {
    final rest = mutualCount - mutuals.length;
    return rest > 0 ? rest : 0;
  }

  factory FriendProfileView.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    final raw = json['friends'];
    return FriendProfileView(
      user: user is Map<String, dynamic>
          ? FriendSummary.fromJson(user)
          : const FriendSummary(userId: '', name: ''),
      isFriend: json['isFriend'] == true,
      friendCount: (json['friendCount'] as num?)?.toInt() ?? 0,
      mutuals: FriendSummary.listFrom(json['mutuals']),
      mutualCount: (json['mutualCount'] as num?)?.toInt() ?? 0,
      // A JSON null, or the key missing altogether, stays null: only an actual
      // array becomes a list, and an empty array becomes an empty list.
      friends: raw is List ? FriendSummary.listFrom(raw) : null,
    );
  }
}

/// `GET /friends/suggestions` - "Mensen die je misschien kent".
///
/// Friends of friends, most shared friends first, capped at
/// [maxFriendSuggestions] server-side. Existing friends, pending verzoeken in
/// either direction and anyone blocked either way are already gone by the time
/// this arrives, so every row is invitable as-is.
///
/// Every row here has [FriendSummary.mutualCount] set - that is the whole
/// point of the list - but the renderer still goes through
/// [FriendSummary.mutualLabel] rather than assuming it.
class FriendSuggestionsResponse {
  const FriendSuggestionsResponse({this.suggestions = const []});

  static const empty = FriendSuggestionsResponse();

  final List<FriendSummary> suggestions;

  bool get isEmpty => suggestions.isEmpty;

  factory FriendSuggestionsResponse.fromJson(Map<String, dynamic> json) {
    return FriendSuggestionsResponse(suggestions: FriendSummary.listFrom(json['suggestions']));
  }
}

/// `SUGGESTIONS_LIMIT` in `lib/friends/service.ts`.
const int maxFriendSuggestions = 20;

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

/// One row in the blocked list - all a client needs to render it and undo it.
class BlockedUser {
  const BlockedUser({required this.userId, required this.name, this.image});

  final String userId;
  final String name;
  final String? image;

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
    userId: '${json['userId'] ?? ''}',
    name: (json['name'] as String?)?.trim() ?? '',
    image: (json['image'] as String?)?.trim(),
  );
}

/// Which categories post to the kring by themselves.
class FriendAutoShare {
  const FriendAutoShare({
    this.milestones = true,
    this.verses = false,
    this.notes = false,
  });

  final bool milestones;
  final bool verses;
  final bool notes;

  factory FriendAutoShare.fromJson(Map<String, dynamic> json) => FriendAutoShare(
    milestones: json['milestones'] != false,
    verses: json['verses'] == true,
    notes: json['notes'] == true,
  );
}

/// `GET /friends/settings` - the reader's own vriendenkring settings.
///
/// [blocked] rides along here rather than on an endpoint of its own: blocking
/// is a setting, and a list that is nearly always empty does not deserve a
/// second round trip. [FriendSettingsUpdate] is the body that writes the
/// switches back, one named path at a time.
class FriendSettings {
  const FriendSettings({
    this.discoverable = false,
    this.autoShare = const FriendAutoShare(),
    this.hasContactHashes = false,
    this.blocked = const [],
  });

  static const empty = FriendSettings();

  final bool discoverable;
  final FriendAutoShare autoShare;

  /// Whether contact hashes are on file, so a client can offer "vergeten".
  final bool hasContactHashes;

  final List<BlockedUser> blocked;

  factory FriendSettings.fromJson(Map<String, dynamic> json) {
    final share = json['autoShare'];
    final raw = json['blocked'];
    return FriendSettings(
      discoverable: json['discoverable'] == true,
      autoShare: share is Map<String, dynamic>
          ? FriendAutoShare.fromJson(share)
          : const FriendAutoShare(),
      hasContactHashes: json['hasContactHashes'] == true,
      blocked: raw is List
          ? [
              for (final item in raw)
                if (item is Map<String, dynamic>) BlockedUser.fromJson(item),
            ]
          : const [],
    );
  }

  FriendSettings copyWith({
    bool? discoverable,
    FriendAutoShare? autoShare,
    bool? hasContactHashes,
    List<BlockedUser>? blocked,
  }) {
    return FriendSettings(
      discoverable: discoverable ?? this.discoverable,
      autoShare: autoShare ?? this.autoShare,
      hasContactHashes: hasContactHashes ?? this.hasContactHashes,
      blocked: blocked ?? this.blocked,
    );
  }
}

/// The body of `PATCH /friends/settings` - **one switch per named path.**
///
/// `updateSettings` in `lib/friends/service.ts` reads `discoverable` and
/// `autoShare.milestones` / `.verses` / `.notes` and `$set`s only the paths it
/// was given, never the whole `autoShare` object. So every field here is
/// nullable and null means "laat staan": sending a half-filled object cannot
/// reset the switches it did not mention. A boolean default on any of these
/// would silently undo the other two, which is exactly the bug the server went
/// out of its way to make impossible.
class FriendSettingsUpdate {
  const FriendSettingsUpdate({
    this.discoverable,
    this.autoShareMilestones,
    this.autoShareVerses,
    this.autoShareNotes,
  });

  /// Only [discoverable], for the findability switch on its own.
  const FriendSettingsUpdate.discoverability(bool value) : this(discoverable: value);

  final bool? discoverable;
  final bool? autoShareMilestones;
  final bool? autoShareVerses;
  final bool? autoShareNotes;

  /// Nothing to send - the repository answers without a round trip.
  bool get isEmpty =>
      discoverable == null &&
      autoShareMilestones == null &&
      autoShareVerses == null &&
      autoShareNotes == null;

  Map<String, Object?> toJson() {
    final share = <String, Object?>{
      if (autoShareMilestones != null) 'milestones': autoShareMilestones,
      if (autoShareVerses != null) 'verses': autoShareVerses,
      if (autoShareNotes != null) 'notes': autoShareNotes,
    };
    return {
      if (discoverable != null) 'discoverable': discoverable,
      // Left out entirely when empty, rather than sent as `{}`.
      if (share.isNotEmpty) 'autoShare': share,
    };
  }
}

/// Why something was reported.
///
/// The wire values are storage slugs (`REPORT_REASONS` in
/// `lib/friends/types.ts`); the Dutch wording lives here, in the client, so
/// rewording a reason is not a data migration. An unknown slug from a newer
/// server reads as [other] - the same forward-compatible shape
/// [FriendPostKind] uses.
enum FriendReportReason { spam, inappropriate, hate, harassment, misinformation, other }

FriendReportReason friendReportReasonFrom(String? raw) => switch (raw) {
  'spam' => FriendReportReason.spam,
  'inappropriate' => FriendReportReason.inappropriate,
  'hate' => FriendReportReason.hate,
  'harassment' => FriendReportReason.harassment,
  'misinformation' => FriendReportReason.misinformation,
  _ => FriendReportReason.other,
};

/// What `POST /friends/posts/:id/report` wants in `reason`. The server refuses
/// anything outside `REPORT_REASONS` with a 400, so this mapping is exhaustive
/// on purpose and never falls through to a guess.
String friendReportReasonWire(FriendReportReason reason) => switch (reason) {
  FriendReportReason.spam => 'spam',
  FriendReportReason.inappropriate => 'inappropriate',
  FriendReportReason.hate => 'hate',
  FriendReportReason.harassment => 'harassment',
  FriendReportReason.misinformation => 'misinformation',
  FriendReportReason.other => 'other',
};

/// The Dutch line for a reason, for the melden-sheet.
String friendReportReasonLabel(FriendReportReason reason) => switch (reason) {
  FriendReportReason.spam => 'Spam of reclame',
  FriendReportReason.inappropriate => 'Ongepast of aanstootgevend',
  FriendReportReason.hate => 'Haat of discriminatie',
  FriendReportReason.harassment => 'Pesten of bedreiging',
  FriendReportReason.misinformation => 'Onjuiste informatie',
  FriendReportReason.other => 'Iets anders',
};

/// The reasons to offer, in the order a sheet should list them: the common
/// ones first, "Iets anders" last. [FriendReportReason.values] happens to be
/// the same order today, but a sheet should not depend on enum declaration
/// order, so it is spelled out.
const List<FriendReportReason> friendReportReasons = [
  FriendReportReason.spam,
  FriendReportReason.inappropriate,
  FriendReportReason.hate,
  FriendReportReason.harassment,
  FriendReportReason.misinformation,
  FriendReportReason.other,
];

/// One reaction under a post, as `GET /friends/posts/:id/comments` sends it.
///
/// The server answers `{ "comments": [...] }`, oldest first, with no cursor
/// and no total: it returns the whole thread (capped server-side at 200). So
/// there is no page shape to model here, and the client must not pretend there
/// is one.
class FriendPostComment {
  const FriendPostComment({
    required this.id,
    required this.authorName,
    required this.createdAt,
    this.postId = '',
    this.authorId = '',
    this.authorImage,
    this.body = '',
  });

  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String? authorImage;
  final String body;
  final DateTime createdAt;

  factory FriendPostComment.fromJson(Map<String, dynamic> json) {
    final created = json['createdAt'];
    return FriendPostComment(
      id: '${json['id'] ?? ''}',
      postId: '${json['postId'] ?? ''}',
      authorId: '${json['authorId'] ?? ''}',
      authorName: (json['authorName'] as String?)?.trim() ?? '',
      authorImage: (json['authorImage'] as String?)?.trim(),
      body: (json['body'] as String?)?.trim() ?? '',
      createdAt: created is String
          ? (DateTime.tryParse(created)?.toLocal() ?? DateTime.now())
          : DateTime.now(),
    );
  }

  /// The `comments` array of the response, in the order the server sent it.
  static List<FriendPostComment> listFromJson(Map<String, dynamic> json) {
    final raw = json['comments'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map<String, dynamic>) FriendPostComment.fromJson(item),
    ];
  }
}

// ------------------------------------------------------------ contact match

/// Hex characters in one contact hash: HMAC-SHA256 truncated to 128 bits.
/// `HASH_LENGTH` in `lib/friends/discovery.ts`.
const int contactHashLength = 32;

/// `MAX_MATCH_HASHES` - the most hashes one match call may carry. The server
/// silently drops the rest (`sanitiseHashes`), so the client caps first and
/// knows it did.
const int maxContactMatchHashes = 2000;

/// The ceiling on how many accounts one match call reports (`.limit(200)` in
/// `matchContacts`). A bigger address book does not return more.
const int maxContactMatchResults = 200;

/// `POST /friends/discovery/match` - hashed contacts in, accounts out.
///
/// The hashing itself is deliberately *not* here: this type only carries and
/// validates the hex, so it stays testable without a crypto dependency. The
/// pepper comes from `GET /friends/discovery/pepper`, is never stored, and the
/// hashes are dropped server-side after the match.
class ContactDiscoveryHashes {
  ContactDiscoveryHashes({
    Iterable<String> phoneHashes = const [],
    Iterable<String> emailHashes = const [],
  }) : phoneHashes = sanitiseContactHashes(phoneHashes),
       emailHashes = sanitiseContactHashes(emailHashes);

  /// Already-validated lists, for a caller that did its own sanitising.
  const ContactDiscoveryHashes.raw({this.phoneHashes = const [], this.emailHashes = const []});

  final List<String> phoneHashes;
  final List<String> emailHashes;

  /// Nothing worth a round trip: the server answers `{found: []}` for this.
  bool get isEmpty => phoneHashes.isEmpty && emailHashes.isEmpty;

  int get length => phoneHashes.length + emailHashes.length;

  Map<String, Object?> toJson() => {'phoneHashes': phoneHashes, 'emailHashes': emailHashes};
}

/// Lower-cases, drops anything that is not [contactHashLength] hex characters,
/// de-duplicates and caps at [maxContactMatchHashes] - the same rules
/// `sanitiseHashes` applies server-side, done here so a malformed address book
/// does not spend one of the five calls an hour.
List<String> sanitiseContactHashes(Iterable<String> raw, {int max = maxContactMatchHashes}) {
  final out = <String>{};
  for (final item in raw) {
    final value = item.trim().toLowerCase();
    if (value.length != contactHashLength) continue;
    if (!_hexOnly.hasMatch(value)) continue;
    out.add(value);
    if (out.length >= max) break;
  }
  return List.unmodifiable(out);
}

final RegExp _hexOnly = RegExp(r'^[0-9a-f]+$');

/// What `POST /friends/discovery/match` answered.
///
/// [available] is false for the "feature off" state - every
/// `/friends/discovery/*` route answers 503 while `FRIENDS_CONTACT_PEPPER` is
/// unset, which is where all environments stand right now. That is not an
/// error and must not be shown as one: the screen simply offers no contact
/// matching.
class ContactMatchResult {
  const ContactMatchResult({this.found = const [], this.available = true, this.message});

  /// Contact matching is switched off server-side. Nothing is wrong.
  static const unavailable = ContactMatchResult(available: false);

  /// The feature is on, nobody in the address book has an account.
  static const none = ContactMatchResult();

  /// Accounts that chose to be findable, name and picture only. Existing
  /// friends and anyone blocked either way are already filtered out, so every
  /// row can be offered an "Uitnodigen".
  final List<FriendSummary> found;

  final bool available;

  /// The server's own Dutch line, when it sent one - the rate limiter's
  /// "Je hebt je contacten net al gecontroleerd." in particular.
  final String? message;

  bool get isEmpty => found.isEmpty;

  factory ContactMatchResult.fromJson(Map<String, dynamic> json) {
    // `matchContacts` answers `{ found: [...] }`, not `{ matches: ... }`.
    return ContactMatchResult(found: FriendSummary.listFrom(json['found']));
  }
}

/// The body of `POST /friends/discovery/hashes` - the reader's **own** phone
/// number and e-mail.
///
/// Counter-intuitively for the route's name, these go up **in the clear**:
/// `saveOwnHashes` normalises and hashes them server-side, because the server
/// already knows the account's e-mail anyway and hashing one's own two
/// identifiers under the pepper client-side would buy nothing. Only somebody
/// else's address book is hashed before it leaves the phone, by
/// [ContactDiscoveryHashes].
///
/// This is the second consent, separate from reading an address book: neither
/// implies the other. [discoverable] defaults to true server-side unless it is
/// explicitly false.
class OwnContactIdentifiers {
  const OwnContactIdentifiers({
    this.phone,
    this.email,
    this.country = 'NL',
    this.discoverable = true,
  });

  final String? phone;
  final String? email;

  /// ISO country for reading a national number, two letters. The server knows
  /// NL BE DE GB US ZA and falls back to NL.
  final String country;

  final bool discoverable;

  bool get isEmpty => (phone?.trim().isEmpty ?? true) && (email?.trim().isEmpty ?? true);

  Map<String, Object?> toJson() {
    final number = phone?.trim() ?? '';
    final address = email?.trim() ?? '';
    return {
      if (number.isNotEmpty) 'phone': number,
      if (address.isNotEmpty) 'email': address,
      'country': country.toUpperCase(),
      'discoverable': discoverable,
    };
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
