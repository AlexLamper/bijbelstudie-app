/// Everything the tree needs, as `GET /api/v1/gamification` returns it.
///
/// One endpoint for level, XP, streak, badges *and* the tree, so the phone and
/// the website cannot disagree about any of them. Nothing here describes the
/// tree's shape - that is derived from [seed], [level], [progress], [health]
/// and the species by `tree_generator.dart`.
library;

import 'catalog.dart';
import 'stages.dart';
import 'traits.dart';

class XpTableRow {
  const XpTableRow({required this.event, required this.value, required this.label});

  final String event;
  final int value;
  final String label;
}

/// Where a repository hands the raw `xp` field of a response.
///
/// Wired in each repository's provider to the Levensboom animation bus. Passing
/// a sink in rather than making every repository depend on Riverpod state keeps
/// the data layer ignorant of the tree: it forwards what the server said and
/// nothing more, and a null sink (tests, preview mode) is a no-op.
typedef XpSink = void Function(Object? xp);

/// What an XP-earning endpoint hands back, so the tree can animate without a
/// second request. Every XP route on the server returns this as `xp`.
class XpGrant {
  const XpGrant({
    required this.xp,
    required this.level,
    required this.levelledUp,
    required this.awarded,
    required this.newBadges,
  });

  final int xp;
  final int level;
  final bool levelledUp;
  final int awarded;
  final List<String> newBadges;

  static XpGrant? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final awarded = (raw['awarded'] as num?)?.toInt() ?? 0;
    if (awarded <= 0) return null;
    return XpGrant(
      xp: (raw['xp'] as num?)?.toInt() ?? 0,
      level: (raw['level'] as num?)?.toInt() ?? 1,
      levelledUp: raw['levelledUp'] == true,
      awarded: awarded,
      newBadges: (raw['newBadges'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }
}

/// The nearest level-gated catalog item still locked, for the progress strip.
class NextUnlock {
  const NextUnlock({required this.kind, required this.id, required this.name, required this.level});

  final String kind;
  final String id;
  final String name;
  final int level;

  static NextUnlock? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return NextUnlock(
      kind: raw['kind'] as String? ?? '',
      id: raw['id'] as String? ?? '',
      name: raw['name'] as String? ?? '',
      level: (raw['level'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> toJson() => {'kind': kind, 'id': id, 'name': name, 'level': level};
}

class TreeState {
  const TreeState({
    required this.xp,
    required this.level,
    required this.xpIntoLevel,
    required this.xpForNextLevel,
    required this.progressPercentage,
    required this.streak,
    required this.freezes,
    required this.badges,
    required this.seed,
    required this.health,
    required this.wilting,
    required this.daysSinceActive,
    required this.lastSeenLevel,
    required this.traitsUnlocked,
    required this.reducedMotion,
    required this.disabled,
    required this.xpTable,
    this.chosen = AvatarChoice.defaults,
    this.avatar = AvatarChoice.defaults,
    this.unlocked = const {},
    this.nextUnlock,
    this.longestStreak = 0,
    this.planted = false,
    this.introSeen = false,
    this.publicProfile = false,
    this.seenItems = const {},
  });

  final int xp;
  final int level;
  final int xpIntoLevel;
  final int xpForNextLevel;
  final int progressPercentage;
  final int streak;
  final int freezes;
  final List<String> badges;

  /// Stable per user; the tree's shape hangs off this.
  final String seed;

  /// 0.3..1. Never lower - there is no dead tree.
  final double health;
  final bool wilting;
  final int daysSinceActive;

  /// The highest level the reader has already been shown a celebration for.
  final int lastSeenLevel;

  final List<TreeTrait> traitsUnlocked;
  final bool reducedMotion;
  final bool disabled;
  final List<XpTableRow> xpTable;

  /// What is stored on the account. May name items the account has lost.
  final AvatarChoice chosen;

  /// What to draw: [chosen] after the server's unlock check.
  final AvatarChoice avatar;

  /// `kind:id` keys the account may pick today, as the server serves them.
  final Set<String> unlocked;
  final NextUnlock? nextUnlock;
  final int longestStreak;
  final bool planted;
  final bool introSeen;
  final bool publicProfile;
  final Set<String> seenItems;

  /// 0..1 within the current level; drives how many leaves are open.
  double get progress => xpForNextLevel > 0 ? xpIntoLevel / xpForNextLevel : 0;

  int get xpToNextLevel {
    final left = xpForNextLevel - xpIntoLevel;
    return left < 0 ? 0 : left;
  }

  bool get shouldCelebrate => level > lastSeenLevel;

  /// Derived locally from the same table the server uses.
  StageInfo get stage => stageForLevel(level);

  /// Whether the server considers this account Pro: it never serves the gold
  /// ring to anyone else.
  bool get isProUnlocked => unlocked.contains('ring:goud');

  UnlockContext get unlockContext => UnlockContext(
    level: level,
    badges: badges,
    longestStreak: longestStreak > streak ? longestStreak : streak,
    isPro: isProUnlocked,
  );

  /// The optimistic update after an XP-earning call, before the next fetch.
  /// Both sides use the same level curve, so this and the server agree. The
  /// unlocked set is widened locally by level; a real refresh follows a
  /// level-up so the server has the last word.
  TreeState applyGrant(XpGrant grant) {
    final level = _levelForXp(grant.xp);
    final floor = _xpForLevel(level);
    final ceiling = _xpForLevel(level + 1);
    final span = ceiling - floor < 1 ? 1 : ceiling - floor;
    final badges = {...this.badges, ...grant.newBadges}.toList();
    final ctx = UnlockContext(
      level: level,
      badges: badges,
      longestStreak: longestStreak > streak ? longestStreak : streak,
      isPro: isProUnlocked,
    );
    return copyWith(
      xp: grant.xp,
      level: level,
      xpIntoLevel: grant.xp - floor,
      xpForNextLevel: ceiling - floor,
      progressPercentage: (((grant.xp - floor) / span) * 100).round().clamp(0, 100),
      // Earning XP means the reader is here today, so the tree is healthy again
      // - the streak flow has already moved `lastStreakDate` server-side.
      health: 1,
      wilting: false,
      daysSinceActive: 0,
      badges: badges,
      unlocked: {...unlocked, ...unlockedKeys(ctx)},
    );
  }

  /// Replaces the tree block with what `/api/v1/levensboom` answered.
  TreeState mergeTree(Map<String, dynamic> tree) {
    final parsed = TreeState.fromJson({
      ..._summaryJson(),
      'levensboom': tree,
    });
    return parsed;
  }

  TreeState copyWith({
    int? xp,
    int? level,
    int? xpIntoLevel,
    int? xpForNextLevel,
    int? progressPercentage,
    int? streak,
    int? freezes,
    List<String>? badges,
    double? health,
    bool? wilting,
    int? daysSinceActive,
    int? lastSeenLevel,
    bool? reducedMotion,
    bool? disabled,
    AvatarChoice? chosen,
    AvatarChoice? avatar,
    Set<String>? unlocked,
    NextUnlock? nextUnlock,
    int? longestStreak,
    bool? planted,
    bool? introSeen,
    bool? publicProfile,
    Set<String>? seenItems,
  }) {
    return TreeState(
      xp: xp ?? this.xp,
      level: level ?? this.level,
      xpIntoLevel: xpIntoLevel ?? this.xpIntoLevel,
      xpForNextLevel: xpForNextLevel ?? this.xpForNextLevel,
      progressPercentage: progressPercentage ?? this.progressPercentage,
      streak: streak ?? this.streak,
      freezes: freezes ?? this.freezes,
      badges: badges ?? this.badges,
      seed: seed,
      health: health ?? this.health,
      wilting: wilting ?? this.wilting,
      daysSinceActive: daysSinceActive ?? this.daysSinceActive,
      lastSeenLevel: lastSeenLevel ?? this.lastSeenLevel,
      traitsUnlocked: traitsForLevel(level ?? this.level),
      reducedMotion: reducedMotion ?? this.reducedMotion,
      disabled: disabled ?? this.disabled,
      xpTable: xpTable,
      chosen: chosen ?? this.chosen,
      avatar: avatar ?? this.avatar,
      unlocked: unlocked ?? this.unlocked,
      nextUnlock: nextUnlock ?? this.nextUnlock,
      longestStreak: longestStreak ?? this.longestStreak,
      planted: planted ?? this.planted,
      introSeen: introSeen ?? this.introSeen,
      publicProfile: publicProfile ?? this.publicProfile,
      seenItems: seenItems ?? this.seenItems,
    );
  }

  factory TreeState.fromJson(Map<String, dynamic> json) {
    final tree = (json['levensboom'] as Map?)?.cast<String, dynamic>() ?? const {};
    final level = (json['level'] as num?)?.toInt() ?? 1;
    final badges = (json['badges'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final streak = (json['streak'] as num?)?.toInt() ?? 0;
    final longestStreak = (tree['longestStreak'] as num?)?.toInt() ?? 0;
    final chosen = AvatarChoice.fromJson(tree['chosen']);

    // A server older than the studio serves no unlock list; derive one from
    // what it does serve, so the tree still draws and the tiles still lock.
    final served = (tree['unlocked'] as List?)?.whereType<String>().toSet();
    final unlocked = served ??
        unlockedKeys(
          UnlockContext(
            level: level,
            badges: badges,
            longestStreak: longestStreak > streak ? longestStreak : streak,
            isPro: badges.contains('premium'),
          ),
        );
    final avatar = tree['avatar'] is Map
        ? AvatarChoice.fromJson(tree['avatar'])
        : resolveAvatar(chosen, unlocked);

    return TreeState(
      xp: (json['xp'] as num?)?.toInt() ?? 0,
      level: level,
      xpIntoLevel: (json['xpIntoLevel'] as num?)?.toInt() ?? 0,
      xpForNextLevel: (json['xpForNextLevel'] as num?)?.toInt() ?? 100,
      progressPercentage: (json['progressPercentage'] as num?)?.toInt() ?? 0,
      streak: streak,
      freezes: (json['freezes'] as num?)?.toInt() ?? 0,
      badges: badges,
      // An older server that does not send the block yet still renders a tree;
      // the seed simply falls back to something stable per response.
      seed: (tree['seed'] as String?) ?? '',
      health: (tree['health'] as num?)?.toDouble() ?? 1,
      wilting: tree['wilting'] == true,
      daysSinceActive: (tree['daysSinceActive'] as num?)?.toInt() ?? 0,
      lastSeenLevel: (tree['lastSeenLevel'] as num?)?.toInt() ?? level,
      // Served rather than derived, so a build older than a trait-table change
      // still shows the right list.
      traitsUnlocked: _traitsFromJson(tree['traitsUnlocked']) ?? traitsForLevel(level),
      reducedMotion: tree['reducedMotion'] == true,
      disabled: tree['disabled'] == true,
      xpTable: ((json['xpTable'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (row) => XpTableRow(
              event: row['event'] as String? ?? '',
              value: (row['value'] as num?)?.toInt() ?? 0,
              label: row['label'] as String? ?? '',
            ),
          )
          .toList(),
      chosen: chosen,
      avatar: avatar,
      unlocked: unlocked,
      nextUnlock: NextUnlock.fromJson(tree['nextUnlock']),
      longestStreak: longestStreak,
      planted: tree['planted'] == true,
      introSeen: tree['introSeen'] == true,
      publicProfile: tree['publicProfile'] == true,
      seenItems: (tree['seenItems'] as List?)?.whereType<String>().toSet() ?? const {},
    );
  }

  Map<String, dynamic> _summaryJson() => {
    'xp': xp,
    'level': level,
    'xpIntoLevel': xpIntoLevel,
    'xpForNextLevel': xpForNextLevel,
    'progressPercentage': progressPercentage,
    'streak': streak,
    'freezes': freezes,
    'badges': badges,
    'xpTable': [
      for (final row in xpTable)
        {'event': row.event, 'value': row.value, 'label': row.label},
    ],
  };

  Map<String, dynamic> toJson() => {
    ..._summaryJson(),
    'levensboom': {
      'seed': seed,
      'health': health,
      'wilting': wilting,
      'daysSinceActive': daysSinceActive,
      'lastSeenLevel': lastSeenLevel,
      'traitsUnlocked': traitsUnlocked.map((t) => kTraitIds[t]).toList(),
      'reducedMotion': reducedMotion,
      'disabled': disabled,
      'chosen': chosen.toJson(),
      'avatar': avatar.toJson(),
      'unlocked': unlocked.toList(),
      'nextUnlock': nextUnlock?.toJson(),
      'longestStreak': longestStreak,
      'planted': planted,
      'introSeen': introSeen,
      'publicProfile': publicProfile,
      'seenItems': seenItems.toList(),
    },
  };
}

List<TreeTrait>? _traitsFromJson(Object? raw) {
  if (raw is! List) return null;
  final ids = raw.whereType<String>().toSet();
  final matched = kTraitOrder.where((t) => ids.contains(kTraitIds[t])).toList();
  return matched.isEmpty && ids.isNotEmpty ? null : matched;
}

int _xpForLevel(int level) => level <= 1 ? 0 : 50 * (level - 1) * level;

int _levelForXp(int xp) {
  var level = 1;
  while (level < 200 && xp >= _xpForLevel(level + 1)) {
    level++;
  }
  return level;
}
