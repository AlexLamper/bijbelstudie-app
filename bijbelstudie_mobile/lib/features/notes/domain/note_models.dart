import 'package:flutter/material.dart';

/// Records that sync with `/api/v1/{notes,highlights,bookmarks,reading-history}`.
///
/// Every record carries a client-generated UUID as its `id`. The server keys on
/// it, so creating a record offline and uploading it later — possibly twice,
/// after a dropped connection — produces exactly one row.

enum HighlightColor { yellow, blue, green, pink, purple, orange }

extension HighlightColorX on HighlightColor {
  String get id => name;

  Color get swatch => switch (this) {
    HighlightColor.yellow => const Color(0xFFF2E3A8),
    HighlightColor.blue => const Color(0xFFBFD2EE),
    HighlightColor.green => const Color(0xFFBCD8C3),
    HighlightColor.pink => const Color(0xFFF0C7D2),
    HighlightColor.purple => const Color(0xFFD5C9E8),
    HighlightColor.orange => const Color(0xFFF3CDB0),
  };

  /// Dark-mode fill: deep, muted variants of [swatch] chosen so the reader's
  /// light body text (`AppTheme.darkInk`, `0xFFE5E5E5`) keeps >=4.5:1
  /// contrast against them. `swatch` itself is a light pastel meant to sit
  /// under *dark* text — used as-is in dark mode it made the (light) reader
  /// text nearly invisible. This never touches `id`/`swatch`, only how a
  /// highlight is painted, so the synced colour value is unchanged.
  Color get _darkFill => switch (this) {
    HighlightColor.yellow => const Color(0xFF4A3F17),
    HighlightColor.blue => const Color(0xFF1E3A5F),
    HighlightColor.green => const Color(0xFF1F4A33),
    HighlightColor.pink => const Color(0xFF5C2A3A),
    HighlightColor.purple => const Color(0xFF3C2A5C),
    HighlightColor.orange => const Color(0xFF5C3517),
  };

  /// The colour to actually paint a highlight fill with, for the given
  /// [brightness]. Use this everywhere a highlight is rendered (reader,
  /// notes list, marks sheet, colour picker) instead of [swatch] directly.
  Color fill(Brightness brightness) =>
      brightness == Brightness.dark ? _darkFill : swatch;

  String get label => switch (this) {
    HighlightColor.yellow => 'Geel',
    HighlightColor.blue => 'Blauw',
    HighlightColor.green => 'Groen',
    HighlightColor.pink => 'Roze',
    HighlightColor.purple => 'Paars',
    HighlightColor.orange => 'Oranje',
  };

  static HighlightColor fromId(String? id) => HighlightColor.values.firstWhere(
    (c) => c.id == id,
    orElse: () => HighlightColor.yellow,
  );
}

class StudyNote {
  const StudyNote({
    required this.id,
    required this.book,
    required this.chapter,
    this.verse,
    this.verseEnd,
    required this.verseText,
    required this.noteText,
    required this.translation,
    this.color = HighlightColor.yellow,
    this.tags = const [],
    required this.isHighlight,
    required this.updatedAt,
  });

  final String id;
  final String book;
  final int chapter;
  final int? verse;

  /// Last verse of a passage note written on the website ("gedeelte"). The app
  /// only creates single-verse notes, but must carry this through so a
  /// re-save (the delete undo) does not shrink "Genesis 1:1-5" to "Genesis 1:1".
  final int? verseEnd;
  final String verseText;
  final String noteText;
  final String translation;
  final HighlightColor color;
  final List<String> tags;
  final bool isHighlight;
  final DateTime updatedAt;

  String get reference {
    if (verse == null) return '$book $chapter';
    final end = verseEnd;
    return end != null && end > verse! ? '$book $chapter:$verse-$end' : '$book $chapter:$verse';
  }

  /// A note the server wrote from a study lesson's reflection step
  /// (`promoteReflectionToNote` in the website repo), rather than one the
  /// reader made themselves. Those are always tagged `studie` plus the study's
  /// id; the id, a Mongo ObjectId, is what sets them apart from a note the
  /// reader happened to tag `studie` on their own.
  bool get isStudyReflection =>
      !isHighlight && tags.contains('studie') && tags.any(_objectId.hasMatch);

  static final _objectId = RegExp(r'^[0-9a-f]{24}$');

  /// A reflection note split into the lesson's question and what the reader
  /// wrote and ticked under it.
  ///
  /// The server joins those with blank lines, and a reflection with nothing
  /// written comes out with three in a row between the question and "Deze
  /// week:". Blank lines are dropped here so the answer sits right under the
  /// question it answers.
  ({String question, String answer}) get reflectionParts {
    final lines = noteText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return (question: '', answer: '');
    return (question: lines.first, answer: lines.skip(1).join('\n'));
  }

  /// A copy under a fresh id. Needed to restore a deleted note: the server
  /// keeps a tombstone for the old id and refuses to resurrect it (409).
  StudyNote withNewId(String id) => StudyNote(
    id: id,
    book: book,
    chapter: chapter,
    verse: verse,
    verseEnd: verseEnd,
    verseText: verseText,
    noteText: noteText,
    translation: translation,
    color: color,
    tags: tags,
    isHighlight: isHighlight,
    updatedAt: DateTime.now(),
  );

  factory StudyNote.fromSyncRecord(Map<String, dynamic> record) {
    final data = (record['data'] as Map<String, dynamic>? ?? const {});
    return StudyNote(
      id: record['id'] as String,
      book: data['book'] as String? ?? '',
      chapter: (data['chapter'] as num?)?.toInt() ?? 0,
      verse: (data['verse'] as num?)?.toInt(),
      verseEnd: (data['verseEnd'] as num?)?.toInt(),
      verseText: (data['verseText'] as String? ?? '').trim(),
      noteText: (data['noteText'] as String? ?? '').trim(),
      translation: data['translation'] as String? ?? 'statenvertaling',
      color: HighlightColorX.fromId(data['highlightColor'] as String?),
      tags: (data['tags'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
      isHighlight: record['kind'] == 'highlight',
      updatedAt:
          DateTime.tryParse(record['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toRequestData() => {
    'book': book,
    'chapter': chapter,
    if (verse != null) 'verse': verse,
    if (verseEnd != null) 'verseEnd': verseEnd,
    'verseReference': reference,
    'verseText': verseText.isEmpty ? ' ' : verseText,
    'noteText': noteText.isEmpty ? ' ' : noteText,
    'translation': translation,
    'highlightColor': color.id,
    'tags': tags,
  };
}

class Bookmark {
  const Bookmark({
    required this.id,
    required this.book,
    required this.chapter,
    this.verse,
    required this.version,
    this.label,
    required this.updatedAt,
  });

  final String id;
  final String book;
  final int chapter;
  final int? verse;
  final String version;
  final String? label;
  final DateTime updatedAt;

  String get reference => verse == null ? '$book $chapter' : '$book $chapter:$verse';

  factory Bookmark.fromSyncRecord(Map<String, dynamic> record) {
    final data = (record['data'] as Map<String, dynamic>? ?? const {});
    return Bookmark(
      id: record['id'] as String,
      book: data['book'] as String? ?? '',
      chapter: (data['chapter'] as num?)?.toInt() ?? 0,
      verse: (data['verse'] as num?)?.toInt(),
      version: data['version'] as String? ?? 'statenvertaling',
      label: data['label'] as String?,
      updatedAt:
          DateTime.tryParse(record['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toRequestData() => {
    'book': book,
    'chapter': chapter,
    if (verse != null) 'verse': verse,
    'version': version,
    if (label != null) 'label': label,
  };
}

/// Where the reader stopped, so "verder lezen" reopens the exact position.
class ReadingPosition {
  const ReadingPosition({
    required this.id,
    required this.book,
    required this.chapter,
    required this.version,
    required this.scrollProgress,
    required this.readAt,
  });

  final String id;
  final String book;
  final int chapter;
  final String version;
  final double scrollProgress;
  final DateTime readAt;

  String get reference => '$book $chapter';

  factory ReadingPosition.fromSyncRecord(Map<String, dynamic> record) {
    final data = (record['data'] as Map<String, dynamic>? ?? const {});
    return ReadingPosition(
      id: record['id'] as String,
      book: data['book'] as String? ?? '',
      chapter: (data['chapter'] as num?)?.toInt() ?? 0,
      version: data['version'] as String? ?? 'statenvertaling',
      scrollProgress: (data['scrollProgress'] as num?)?.toDouble() ?? 0,
      readAt: DateTime.tryParse(data['readAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toRequestData() => {
    'book': book,
    'chapter': chapter,
    'version': version,
    'scrollProgress': scrollProgress,
    'readAt': readAt.toUtc().toIso8601String(),
  };
}
