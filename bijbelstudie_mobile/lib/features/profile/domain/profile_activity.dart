import 'package:flutter/material.dart';

import '../../notes/domain/note_models.dart';
import '../../studies/data/study_models.dart';
import 'profile_stats.dart';

/// What produced an entry in the activity feed.
enum ProfileActivityKind { highlight, note, study, badge }

/// The filter bar above the feed.
enum ProfileActivityFilter { all, highlights, notes, studies, badges }

extension ProfileActivityFilterX on ProfileActivityFilter {
  String get label => switch (this) {
    ProfileActivityFilter.all => 'Alle activiteit',
    ProfileActivityFilter.highlights => 'Markeringen',
    ProfileActivityFilter.notes => 'Notities',
    ProfileActivityFilter.studies => 'Bijbelstudies',
    ProfileActivityFilter.badges => 'Badges',
  };

  IconData get icon => switch (this) {
    ProfileActivityFilter.all => Icons.auto_awesome_outlined,
    ProfileActivityFilter.highlights => Icons.brush_outlined,
    ProfileActivityFilter.notes => Icons.edit_note_outlined,
    ProfileActivityFilter.studies => Icons.auto_stories_outlined,
    ProfileActivityFilter.badges => Icons.military_tech_outlined,
  };

  /// The empty-state heading. Written out rather than derived from [label],
  /// which would read as "Nog geen alle activiteit".
  String get emptyTitle => switch (this) {
    ProfileActivityFilter.all => 'Nog geen activiteit',
    ProfileActivityFilter.highlights => 'Nog geen markeringen',
    ProfileActivityFilter.notes => 'Nog geen notities',
    ProfileActivityFilter.studies => 'Nog geen bijbelstudies',
    ProfileActivityFilter.badges => 'Nog geen badges',
  };

  /// The empty-state line for this tab. The feed is assembled locally, so an
  /// empty tab means the account genuinely has nothing of that kind.
  String get emptyLine => switch (this) {
    ProfileActivityFilter.all =>
      'Zodra je markeert, notities schrijft of een bijbelstudie start, verschijnt het hier.',
    ProfileActivityFilter.highlights =>
      'Houd een vers ingedrukt in de lezer om het te markeren.',
    ProfileActivityFilter.notes =>
      'Houd een vers ingedrukt in de lezer om er een notitie bij te schrijven.',
    ProfileActivityFilter.studies =>
      'Start een bijbelstudie om je voortgang hier terug te zien.',
    ProfileActivityFilter.badges =>
      'Lees, markeer en schrijf notities om je eerste badge te verdienen.',
  };

  bool matches(ProfileActivityKind kind) => switch (this) {
    ProfileActivityFilter.all => true,
    ProfileActivityFilter.highlights => kind == ProfileActivityKind.highlight,
    ProfileActivityFilter.notes => kind == ProfileActivityKind.note,
    ProfileActivityFilter.studies => kind == ProfileActivityKind.study,
    ProfileActivityFilter.badges => kind == ProfileActivityKind.badge,
  };
}

/// One card in the feed.
///
/// There is no `/activity` endpoint: every entry is assembled on the device
/// from records the app already holds - highlights, notes, the study plans in
/// shared_preferences, and the badge ids on the dashboard payload. That is
/// also why nothing here carries a like or comment count: no such thing is
/// stored anywhere, so the card renders those icons as marks rather than as
/// buttons.
class ProfileActivity {
  const ProfileActivity({
    required this.id,
    required this.kind,
    required this.actionLabel,
    this.at,
    this.note,
    this.study,
    this.lessonsDone = 0,
    this.lessonsTotal = 0,
    this.badge,
  });

  final String id;
  final ProfileActivityKind kind;

  /// "markeerde een vers", "schreef een notitie", ... - the verb on the
  /// metadata row.
  final String actionLabel;

  /// Null when the source record carries no timestamp, e.g. a badge the server
  /// awarded without saying when. The card then omits the time instead of
  /// guessing one.
  final DateTime? at;

  /// Set for [ProfileActivityKind.highlight] and [ProfileActivityKind.note].
  final StudyNote? note;

  /// Set for [ProfileActivityKind.study].
  final CuratedStudy? study;
  final int lessonsDone;
  final int lessonsTotal;

  /// Set for [ProfileActivityKind.badge].
  final BadgeProgress? badge;

  double get studyProgress => lessonsTotal == 0
      ? 0
      : (lessonsDone / lessonsTotal).clamp(0.0, 1.0).toDouble();
}

/// "vandaag", "gisteren", "3 dagen geleden", then a plain date.
String formatActivityTimestamp(DateTime when, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final days = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime(when.year, when.month, when.day)).inDays;

  if (days <= 0) return 'vandaag';
  if (days == 1) return 'gisteren';
  if (days < 7) return '$days dagen geleden';
  if (days < 14) return 'vorige week';
  if (days < 60) return '${days ~/ 7} weken geleden';

  const months = [
    'jan',
    'feb',
    'mrt',
    'apr',
    'mei',
    'jun',
    'jul',
    'aug',
    'sep',
    'okt',
    'nov',
    'dec',
  ];
  return '${when.day} ${months[when.month - 1]} ${when.year}';
}
