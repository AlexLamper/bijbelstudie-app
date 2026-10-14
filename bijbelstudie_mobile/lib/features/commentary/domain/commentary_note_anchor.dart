import 'package:flutter/foundation.dart';

/// Where in a commentary a note was written, encoded so it survives the trip
/// through the notes API and back.
///
/// ── Why it rides in `tags` ──────────────────────────────────────────────────
///
/// The note record the app syncs has no commentary field. `noteFieldsFrom` in
/// the website's `lib/mobileUserData.ts` keeps exactly `book`, `chapter`,
/// `verse`, `verseEnd`, `verseReference`, `verseText`, `noteText`,
/// `translation`, `highlightColor` and `tags`, and silently drops anything
/// else - so a `commentaryId` field invented here would be written, accepted,
/// and never come back.
///
/// `tags` does come back: an arbitrary string array, capped at twenty entries,
/// no length or charset rules. Three of those twenty carry the anchor:
///
///   commentaar          this note hangs off a commentary, not a bible verse
///   `bron:<commentaryId>` which commentary
///   `sectie:<n>`         which entry in the chapter, `0` for the Inleiding
///
/// The book and the chapter are the note's own `book`/`chapter`, which the
/// server does keep, and `translation` carries the commentary id a second time
/// because that field is "where the text came from" and for these notes the
/// text came from the commentary. The excerpt is the note's `verseText`, cut to
/// `maxCommentaryExcerptChars`.
///
/// All three tags must be present for [fromTags] to answer. A reader who tags
/// a note "commentaar" by hand on the website therefore does not turn it into
/// a commentary note, and an anchor written by an older or newer build either
/// parses whole or not at all.
///
/// What the backend would need for this to be first class is small: a
/// `commentarySource` and `commentarySection` pair on the note record, kept by
/// `noteFieldsFrom` and returned by `/api/v1/notes`. Until then the tags are
/// the record, and [toTags] is the only place that writes them.
@immutable
class CommentaryNoteAnchor {
  const CommentaryNoteAnchor({
    required this.commentaryId,
    required this.book,
    required this.chapter,
    required this.section,
  });

  final String commentaryId;
  final String book;
  final int chapter;

  /// The commentary entry the note hangs off: the verse number the commentator
  /// filed it under, or `0` for a chapter introduction - which is how Matthew
  /// Henry keys its opening, and what `CommentaryPane` labels "Inleiding".
  final int section;

  /// Marks a note as hanging off a commentary. Dutch, like `studie`, the one
  /// tag the server writes itself - these are values a reader can see, not
  /// identifiers.
  static const String markerTag = 'commentaar';
  static const String sourcePrefix = 'bron:';
  static const String sectionPrefix = 'sectie:';

  List<String> toTags() => [
    markerTag,
    '$sourcePrefix$commentaryId',
    '$sectionPrefix$section',
  ];

  /// The anchor [tags] encode, or null when they do not encode one.
  ///
  /// [book] and [chapter] come from the note record itself; the tags only have
  /// to supply what the record cannot hold.
  static CommentaryNoteAnchor? fromTags(
    Iterable<String> tags, {
    required String book,
    required int chapter,
  }) {
    var marked = false;
    String? commentaryId;
    int? section;

    for (final tag in tags) {
      if (tag == markerTag) {
        marked = true;
      } else if (tag.startsWith(sourcePrefix)) {
        final id = tag.substring(sourcePrefix.length).trim();
        if (id.isNotEmpty) commentaryId = id;
      } else if (tag.startsWith(sectionPrefix)) {
        section = int.tryParse(tag.substring(sectionPrefix.length).trim());
      }
    }

    if (!marked || commentaryId == null || section == null) return null;
    if (book.isEmpty || section < 0) return null;
    return CommentaryNoteAnchor(
      commentaryId: commentaryId,
      book: book,
      chapter: chapter,
      section: section,
    );
  }

  /// "Inleiding" or "Vers 3", the same two labels the commentary pane pills its
  /// entries with, so the note names the spot the way the reader saw it.
  String get sectionLabel => section == 0 ? 'Inleiding' : 'Vers $section';

  /// Where the note points, for a sheet header: "Genesis 1 - Vers 3".
  String get reference => '$book $chapter - $sectionLabel';

  @override
  bool operator ==(Object other) =>
      other is CommentaryNoteAnchor &&
      other.commentaryId == commentaryId &&
      other.book == book &&
      other.chapter == chapter &&
      other.section == section;

  @override
  int get hashCode => Object.hash(commentaryId, book, chapter, section);

  @override
  String toString() => 'CommentaryNoteAnchor($commentaryId, $reference)';
}
