import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// The numbers the profile screen reports.
///
/// Every field traces back to something the app already fetches: the
/// `/dashboard` payload (streak, freezes, read chapters, earned badge ids) and
/// the `/notes` + `/highlights` lists. Nothing here is invented, so a section
/// with no data shows a zero or an empty state rather than a placeholder.
class ProfileStats {
  const ProfileStats({
    required this.streak,
    required this.freezes,
    required this.booksRead,
    required this.chaptersRead,
    required this.notesCount,
    required this.highlightsCount,
    required this.serverBadgeIds,
  });

  /// The Protestant canon - the denominator behind "... van 66 boeken".
  static const int canonBooks = 66;

  final int streak;

  /// Days the streak survives without a completed task. Earned server-side.
  final int freezes;

  /// Books with at least one chapter read.
  final int booksRead;

  final int chaptersRead;
  final int notesCount;
  final int highlightsCount;

  /// Badge ids the server has already granted, as `lib/gamification.ts`
  /// writes them.
  final List<String> serverBadgeIds;

  double get bookProgress =>
      (booksRead / canonBooks).clamp(0.0, 1.0).toDouble();
}

/// Which real number a badge is measured against.
enum BadgeTrack { streak, books, chapters, notes, highlights, awarded }

/// Tone of a badge tile. An enum rather than a [Color] so the definitions can
/// stay `const`: the theme colours are brightness-resolved getters.
enum BadgeTone { flame, teal, ai, positive }

extension BadgeToneX on BadgeTone {
  Color get color => switch (this) {
    BadgeTone.flame => AppTheme.flame,
    BadgeTone.teal => AppTheme.teal,
    BadgeTone.ai => AppTheme.ai,
    BadgeTone.positive => AppTheme.positive,
  };
}

/// One milestone in [BadgeCatalog].
class BadgeDefinition {
  const BadgeDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.tone,
    required this.track,
    required this.target,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final BadgeTone tone;
  final BadgeTrack track;

  /// The count that unlocks it. Zero for [BadgeTrack.awarded], which the server
  /// hands out and the app cannot measure.
  final int target;
}

/// A definition paired with the reader's real progress towards it.
class BadgeProgress {
  const BadgeProgress({
    required this.definition,
    required this.value,
    required this.unlocked,
  });

  final BadgeDefinition definition;

  /// Where the reader stands on [BadgeDefinition.track] right now.
  final int value;

  final bool unlocked;

  double get fraction {
    if (unlocked) return 1;
    final target = definition.target;
    if (target <= 0) return 0;
    return (value / target).clamp(0.0, 1.0).toDouble();
  }

  /// "3 / 7" while it runs, the description once it is earned.
  String get progressLabel =>
      unlocked ? definition.description : '$value / ${definition.target}';
}

/// The milestones the app can prove from its own data, plus a reading of the
/// badge ids the backend awards.
///
/// The backend has no "list every badge and its criteria" endpoint - it only
/// returns the ids already earned - so the running totals below are computed
/// here from the same numbers the stat cards show. Server ids this build does
/// not recognise are still rendered, as earned, under a neutral label.
abstract final class BadgeCatalog {
  /// Ids `lib/gamification.ts` is known to award. Anything else falls through
  /// to [_awarded].
  static const Map<String, BadgeDefinition> serverBadges = {
    'firstlesson': BadgeDefinition(
      id: 'firstlesson',
      label: 'Eerste les',
      description: 'Eerste les afgerond',
      icon: Icons.school_outlined,
      tone: BadgeTone.ai,
      track: BadgeTrack.awarded,
      target: 0,
    ),
    'completed1': BadgeDefinition(
      id: 'completed1',
      label: 'Studie af',
      description: 'Een bijbelstudie voltooid',
      icon: Icons.workspace_premium_outlined,
      tone: BadgeTone.ai,
      track: BadgeTrack.awarded,
      target: 0,
    ),
  };

  /// Milestones measured against [ProfileStats].
  static const List<BadgeDefinition> milestones = [
    BadgeDefinition(
      id: 'streak3',
      label: 'Op dreef',
      description: '3 dagen op rij gelezen',
      icon: Icons.local_fire_department_outlined,
      tone: BadgeTone.flame,
      track: BadgeTrack.streak,
      target: 3,
    ),
    BadgeDefinition(
      id: 'streak7',
      label: 'Week vol',
      description: '7 dagen op rij gelezen',
      icon: Icons.local_fire_department,
      tone: BadgeTone.flame,
      track: BadgeTrack.streak,
      target: 7,
    ),
    BadgeDefinition(
      id: 'streak30',
      label: 'Maand vol',
      description: '30 dagen op rij gelezen',
      icon: Icons.whatshot_outlined,
      tone: BadgeTone.flame,
      track: BadgeTrack.streak,
      target: 30,
    ),
    BadgeDefinition(
      id: 'books5',
      label: 'Ontdekker',
      description: '5 bijbelboeken geopend',
      icon: Icons.explore_outlined,
      tone: BadgeTone.teal,
      track: BadgeTrack.books,
      target: 5,
    ),
    BadgeDefinition(
      id: 'books20',
      label: 'Doorlezer',
      description: '20 bijbelboeken geopend',
      icon: Icons.auto_stories_outlined,
      tone: BadgeTone.teal,
      track: BadgeTrack.books,
      target: 20,
    ),
    BadgeDefinition(
      id: 'books66',
      label: 'Hele Bijbel',
      description: 'Alle 66 boeken geopend',
      icon: Icons.menu_book_outlined,
      tone: BadgeTone.teal,
      track: BadgeTrack.books,
      target: ProfileStats.canonBooks,
    ),
    BadgeDefinition(
      id: 'chapters50',
      label: 'Vijftig',
      description: '50 hoofdstukken gelezen',
      icon: Icons.layers_outlined,
      tone: BadgeTone.positive,
      track: BadgeTrack.chapters,
      target: 50,
    ),
    BadgeDefinition(
      id: 'notes10',
      label: 'Aantekenaar',
      description: '10 notities geschreven',
      icon: Icons.edit_note_outlined,
      tone: BadgeTone.ai,
      track: BadgeTrack.notes,
      target: 10,
    ),
    BadgeDefinition(
      id: 'notes50',
      label: 'Schrijver',
      description: '50 notities geschreven',
      icon: Icons.history_edu_outlined,
      tone: BadgeTone.ai,
      track: BadgeTrack.notes,
      target: 50,
    ),
    BadgeDefinition(
      id: 'highlights25',
      label: 'Markeerder',
      description: '25 verzen gemarkeerd',
      icon: Icons.brush_outlined,
      tone: BadgeTone.positive,
      track: BadgeTrack.highlights,
      target: 25,
    ),
  ];

  /// A stand-in for a server badge id this build does not know yet, so a new
  /// award still shows up instead of silently disappearing.
  static BadgeDefinition _awarded(String id) => BadgeDefinition(
    id: id,
    label: 'Badge',
    description: 'Toegekend door BijbelStudie',
    icon: Icons.military_tech_outlined,
    tone: BadgeTone.ai,
    track: BadgeTrack.awarded,
    target: 0,
  );

  /// Every badge with the reader's real standing: earned ones first, then the
  /// nearest to done, so the row opens on what matters.
  static List<BadgeProgress> resolve(ProfileStats stats) {
    final earnedIds = stats.serverBadgeIds.toSet();
    final out = <BadgeProgress>[];

    for (final id in stats.serverBadgeIds) {
      out.add(
        BadgeProgress(
          definition: serverBadges[id] ?? _awarded(id),
          value: 1,
          unlocked: true,
        ),
      );
    }

    for (final definition in milestones) {
      if (earnedIds.contains(definition.id)) continue;
      final value = switch (definition.track) {
        BadgeTrack.streak => stats.streak,
        BadgeTrack.books => stats.booksRead,
        BadgeTrack.chapters => stats.chaptersRead,
        BadgeTrack.notes => stats.notesCount,
        BadgeTrack.highlights => stats.highlightsCount,
        BadgeTrack.awarded => 0,
      };
      out.add(
        BadgeProgress(
          definition: definition,
          value: value,
          unlocked: value >= definition.target,
        ),
      );
    }

    out.sort((a, b) {
      if (a.unlocked != b.unlocked) return a.unlocked ? -1 : 1;
      return b.fraction.compareTo(a.fraction);
    });
    return out;
  }
}
