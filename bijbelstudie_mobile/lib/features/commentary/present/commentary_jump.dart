import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A verse in a particular chapter. Carries its chapter so a target set for
/// one chapter can never be applied to another one.
@immutable
class ChapterVerse {
  const ChapterVerse(this.book, this.chapter, this.verse);

  final String book;
  final int chapter;
  final int verse;

  bool sameChapter(String book, int chapter) =>
      this.book == book && this.chapter == chapter;

  @override
  bool operator ==(Object other) =>
      other is ChapterVerse &&
      other.book == book &&
      other.chapter == chapter &&
      other.verse == verse;

  @override
  int get hashCode => Object.hash(book, chapter, verse);

  @override
  String toString() => '$book $chapter:$verse';
}

/// The verse the Commentaar tab of `/studie` should scroll to next.
///
/// Set by the verse action sheet ("Commentaar bij vers N") and by the
/// Bijbel -> Studie switch; the study page's `CommentaryPane` consumes it
/// (resets it to null) once its chapter has rendered, the same pattern as
/// `pendingVerseAnchorProvider` on the reader side.
final pendingCommentaryVerseProvider =
    NotifierProvider<PendingCommentaryVerse, ChapterVerse?>(
      PendingCommentaryVerse.new,
    );

class PendingCommentaryVerse extends Notifier<ChapterVerse?> {
  /// The reader verse the commentary was last lined up with, so switching
  /// panes back and forth without reading on never pulls the commentary away
  /// from wherever the user had scrolled it.
  ChapterVerse? _lastSynced;

  @override
  ChapterVerse? build() => null;

  /// An explicit request for [target]'s commentary.
  ///
  /// Also counts as a sync with where the reader is now: the reader has not
  /// moved, so the next Studie tap must not undo this jump.
  void jumpTo(ChapterVerse target) {
    _lastSynced = ref.read(readerTopVerseProvider);
    state = target;
  }

  /// Lines the commentary up with the top verse on the Bible side - but only
  /// when that verse changed since the last time. Returns whether it did.
  bool syncToReader() {
    final top = ref.read(readerTopVerseProvider);
    if (top == null || top == _lastSynced) return false;
    _lastSynced = top;
    // At the head of the chapter the introduction is the right place to be,
    // not the entry for verse 1 just below it.
    state = top.verse <= 1 ? ChapterVerse(top.book, top.chapter, 0) : top;
    return true;
  }

  void consume() {
    if (state != null) state = null;
  }
}

/// The first verse visible at the top of the Bible text, published by
/// `ReadScreen` when a scroll comes to rest - never per frame. Null until the
/// reader has scrolled at all.
final readerTopVerseProvider = NotifierProvider<ReaderTopVerse, ChapterVerse?>(
  ReaderTopVerse.new,
);

class ReaderTopVerse extends Notifier<ChapterVerse?> {
  @override
  ChapterVerse? build() => null;

  void set(ChapterVerse? verse) {
    if (verse != state) state = verse;
  }
}

/// Index of the commentary entry that covers [verse]: the last entry at or
/// before it, since a commentator who skips a verse is usually still
/// discussing it under the entry above. A verse before the first entry maps
/// to the first entry. Null when there are no entries.
///
/// [entryNumbers] must be ascending, as the API returns them.
int? commentaryEntryIndexFor(List<int> entryNumbers, int verse) {
  if (entryNumbers.isEmpty) return null;
  var match = 0;
  for (var i = 0; i < entryNumbers.length; i++) {
    if (entryNumbers[i] > verse) break;
    match = i;
  }
  return match;
}
