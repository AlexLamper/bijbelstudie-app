/// The list of entries the commentary pane scrolls through, and which verses
/// each one answers for.
///
/// The payload's keys are not the same thing as the verses a commentator
/// covers. Which of the two the pane needs depends on the source, so the
/// difference is handled here, once, as a strategy per commentary id rather
/// than as source checks spread over the UI:
///
///  - `matthew_henry_nl`, `dachsel`, `calvijn_nl` - one key per entry is also
///    one entry per verse (or per section), and Matthew Henry's chapter
///    introduction is already keyed as verse 0. Nothing to do: the keys are
///    the entries, which is [_KeyedEntries].
///  - `kingcomments*` - verse by verse in the text, chunked in the payload.
///    [_MarkerSplitEntries] cuts each chunk at the verse markers inside it
///    (see `commentary_verse_markers.dart`) so every verse the commentator
///    actually wrote about becomes an entry of its own, with its own position
///    in the list to scroll to.
///
/// Splitting rather than annotating is what keeps the jump honest: the pane
/// already keys one widget per entry and scrolls to it, so a verse that
/// becomes an entry is reachable by the machinery that is already there, and
/// an entry that would render blank is dropped here instead of turning into a
/// jump target that goes nowhere.
library;

import 'package:flutter/foundation.dart';

import '../../bible/domain/bible_models.dart';
import 'commentary_verse_markers.dart';

/// What the pane shows: the entries to paint, and the verses that are covered
/// by an entry filed under a different number.
@immutable
class CommentaryEntries {
  const CommentaryEntries({required this.entries, this.sharedVerses = const {}});

  static const empty = CommentaryEntries(entries: []);

  /// Ascending by verse number; 0 is the chapter introduction.
  final List<Verse> entries;

  /// A verse that is discussed inside an entry filed under another number,
  /// mapped to that entry's label - verse 2 of a `Verzen 1-3` entry gives
  /// `{2: '1-3'}`. Such a verse is reachable and lands in the right place, so
  /// the jump sheet may offer it as covered rather than dimming it.
  final Map<int, String> sharedVerses;

  List<int> get numbers => [for (final entry in entries) entry.number];

  bool get isEmpty => entries.isEmpty;
}

abstract class CommentaryEntryStrategy {
  const CommentaryEntryStrategy();

  CommentaryEntries entriesFor(ChapterContent chapter);
}

const _keyed = _KeyedEntries();
const _markerSplit = _MarkerSplitEntries();

/// Sources whose payload keys are not the verses they cover, by id prefix -
/// the KingComments licence ships under more than one id (`kingcomments_nl`
/// and the English variant), and both are chunked the same way.
const _strategyByIdPrefix = <String, CommentaryEntryStrategy>{
  'kingcomments': _markerSplit,
};

CommentaryEntryStrategy commentaryEntryStrategy(String commentaryId) {
  final id = commentaryId.toLowerCase();
  for (final entry in _strategyByIdPrefix.entries) {
    if (id.startsWith(entry.key)) return entry.value;
  }
  return _keyed;
}

/// The entries of [chapter], per its source's strategy.
///
/// [commentaryId] defaults to the id in the payload; the pane may pass the id
/// it asked for instead, which is the same thing for every live source and
/// survives a payload that came off disk before the field existed.
CommentaryEntries commentaryEntriesOf(ChapterContent chapter, {String? commentaryId}) {
  final id = commentaryId ?? chapter.sourceId;
  return commentaryEntryStrategy(id).entriesFor(chapter);
}

/// One entry per payload key, empty ones dropped.
///
/// Empty entries were always skipped when rendering; dropping them here keeps
/// list index and entry index the same thing for the pane.
class _KeyedEntries extends CommentaryEntryStrategy {
  const _KeyedEntries();

  @override
  CommentaryEntries entriesFor(ChapterContent chapter) {
    return CommentaryEntries(
      entries: [
        for (final verse in chapter.verses)
          if (verse.text.trim().isNotEmpty) verse,
      ],
    );
  }
}

/// One entry per verse the commentator wrote a block about.
class _MarkerSplitEntries extends CommentaryEntryStrategy {
  const _MarkerSplitEntries();

  /// How much prose has to sit above the first verse marker of the chapter
  /// before it counts as a chapter introduction rather than as the section
  /// heading of verse 1. KingComments writes both: `<h3>Inzameling en
  /// reisplannen</h3>` alone belongs to verse 1, while `<h3>De liefde</h3>`
  /// followed by two paragraphs about the chapter as a whole is an
  /// introduction, and the reader meets it as "Inleiding" - the same name
  /// Matthew Henry's verse 0 gets.
  static const _introProseChars = 120;

  @override
  CommentaryEntries entriesFor(ChapterContent chapter) {
    final kept = [
      for (final verse in chapter.verses)
        if (verse.text.trim().isNotEmpty) verse,
    ];
    if (kept.isEmpty) return CommentaryEntries.empty;

    final entries = <Verse>[];
    final shared = <int, String>{};

    for (var i = 0; i < kept.length; i++) {
      final entry = kept[i];
      final nextNumber = i + 1 < kept.length ? kept[i + 1].number : null;
      _split(
        entry: entry,
        isFirst: i == 0,
        nextNumber: nextNumber,
        chapter: chapter.chapter,
        into: entries,
        shared: shared,
      );
    }

    // A verse that also has an entry of its own is not shared with anything.
    final numbers = {for (final entry in entries) entry.number};
    shared.removeWhere((verse, _) => numbers.contains(verse));
    return CommentaryEntries(entries: entries, sharedVerses: shared);
  }

  void _split({
    required Verse entry,
    required bool isFirst,
    required int? nextNumber,
    required int chapter,
    required List<Verse> into,
    required Map<int, String> shared,
  }) {
    final text = entry.text;
    final markers = findVerseMarkers(text, chapter: chapter);

    // Cut points as (verse number, offset), the first one opening the entry.
    final cuts = <(int, int)>[];
    var previous = entry.number;

    final intro = isFirst ? _introCut(entry, markers) : null;
    if (intro != null) {
      cuts.add((0, 0));
      previous = 0;
    } else {
      cuts.add((entry.number, 0));
    }

    void recordRange(VerseMarker marker) {
      if (!marker.isRange) return;
      final last = nextNumber == null
          ? marker.endVerse
          : (marker.endVerse < nextNumber ? marker.endVerse : nextNumber - 1);
      for (var verse = marker.verse + 1; verse <= last; verse++) {
        shared[verse] = marker.label;
      }
    }

    for (final marker in markers) {
      // The marker of the entry currently open: either the one that opens the
      // entry itself, or a repeat of a verse split over two blocks (`1Jh
      // 2:13a`, `1Jh 2:13b`), which belongs to the block before it. No cut,
      // but its range still says which verses that block answers for.
      if (marker.verse == previous) {
        recordRange(marker);
        continue;
      }
      if (marker.verse < previous) continue;
      // Past the next entry's number the payload itself disagrees with the
      // markup, and the next entry is the better place for that verse.
      if (nextNumber != null && marker.verse >= nextNumber) continue;
      if (marker.offset <= cuts.last.$2) continue;

      cuts.add((marker.verse, marker.offset));
      previous = marker.verse;
      recordRange(marker);
    }

    for (var i = 0; i < cuts.length; i++) {
      final start = cuts[i].$2;
      final end = i + 1 < cuts.length ? cuts[i + 1].$2 : text.length;
      final slice = text.substring(start, end);
      // A slice with nothing to paint would render as a blank row, and a jump
      // target that lands on nothing is worse than none at all. Dropping it
      // lets the verse fall back to the entry above, which is where the
      // commentator is still talking about it.
      if (!_hasVisibleText(slice)) continue;
      into.add(Verse(number: cuts[i].$1, text: slice));
    }
  }

  /// The offset to cut a chapter introduction off at, or null when this entry
  /// does not open with one.
  int? _introCut(Verse entry, List<VerseMarker> markers) {
    if (entry.number != 1 || markers.isEmpty) return null;
    final first = markers.first;
    if (first.verse != 1 || first.offset <= 0) return null;
    final prefix = entry.text.substring(0, first.offset);
    return _plainLength(_withoutHeadings(prefix)) >= _introProseChars ? first.offset : null;
  }
}

final _tag = RegExp(r'<[^>]*>');
final _heading = RegExp(r'<\s*h[1-6](?:\s[^>]*)?>.*?<\s*/\s*h[1-6]\s*>',
    caseSensitive: false, dotAll: true);

String _withoutHeadings(String html) => html.replaceAll(_heading, ' ');

int _plainLength(String html) => html.replaceAll(_tag, ' ').trim().length;

bool _hasVisibleText(String html) => _plainLength(html) > 0;
