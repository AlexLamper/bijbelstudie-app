/// Everything the tree needs, as `GET /api/v1/gamification` returns it.
///
/// One endpoint for level, XP, streak, badges *and* the tree, so the phone and
/// the website cannot disagree about any of them. Nothing here describes the
/// tree's shape - that is derived from [seed], [level], [progress] and
/// [health] by `tree_generator.dart`.
library;

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

  /// 0..1 within the current level; drives how many leaves are open.
  double get progress => xpForNextLevel > 0 ? xpIntoLevel / xpForNextLevel : 0;

  int get xpToNextLevel {
    final left = xpForNextLevel - xpIntoLevel;
    return left < 0 ? 0 : left;
  }

  bool get shouldCelebrate => level > lastSeenLevel;

  /// The optimistic update after an XP-earning call, before the next fetch.
  /// Both sides use the same level curve, so this and the server agree.
  TreeState applyGrant(XpGrant grant) {
    final level = _levelForXp(grant.xp);
    final floor = _xpForLevel(level);
    final ceiling = _xpForLevel(level + 1);
    final span = ceiling - floor < 1 ? 1 : ceiling - floor;
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
      badges: {...badges, ...grant.newBadges}.toList(),
    );
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
    );
  }

  factory TreeState.fromJson(Map<String, dynamic> json) {
    final tree = (json['levensboom'] as Map?)?.cast<String, dynamic>() ?? const {};
    final level = (json['level'] as num?)?.toInt() ?? 1;

    return TreeState(
      xp: (json['xp'] as num?)?.toInt() ?? 0,
      level: level,
      xpIntoLevel: (json['xpIntoLevel'] as num?)?.toInt() ?? 0,
      xpForNextLevel: (json['xpForNextLevel'] as num?)?.toInt() ?? 100,
      progressPercentage: (json['progressPercentage'] as num?)?.toInt() ?? 0,
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      freezes: (json['freezes'] as num?)?.toInt() ?? 0,
      badges: (json['badges'] as List?)?.whereType<String>().toList() ?? const [],
      // An older server that does not send the block yet still renders a tree;
      // the seed simply falls back to something stable per response.
      seed: (tree['seed'] as String?) ?? '',
      health: (tree['health'] as num?)?.toDouble() ?? 1,
      wilting: tree['wilting'] == true,
      daysSinceActive: (tree['daysSinceActive'] as num?)?.toInt() ?? 0,
      lastSeenLevel: (tree['lastSeenLevel'] as num?)?.toInt() ?? level,
      // Served rather than derived, so a build older than a trait-table change
      // still shows the right list in the detail screen.
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
    );
  }

  Map<String, dynamic> toJson() => {
    'xp': xp,
    'level': level,
    'xpIntoLevel': xpIntoLevel,
    'xpForNextLevel': xpForNextLevel,
    'progressPercentage': progressPercentage,
    'streak': streak,
    'freezes': freezes,
    'badges': badges,
    'levensboom': {
      'seed': seed,
      'health': health,
      'wilting': wilting,
      'daysSinceActive': daysSinceActive,
      'lastSeenLevel': lastSeenLevel,
      'traitsUnlocked': traitsUnlocked.map((t) => kTraitIds[t]).toList(),
      'reducedMotion': reducedMotion,
      'disabled': disabled,
    },
    'xpTable': [
      for (final row in xpTable)
        {'event': row.event, 'value': row.value, 'label': row.label},
    ],
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
