/// Where inside one commentary entry a new verse starts being discussed.
///
/// Some commentators publish their work verse by verse but ship it in
/// chapter-sized chunks: the payload has a handful of keyed entries and the
/// real verse boundaries live inside the markup of each one. KingComments is
/// the clearest case. `1 Petrus 2` arrives as six entries - keyed 1, 3, 9, 13,
/// 18 and 22 - while the entry keyed 3 opens a paragraph for each of the
/// verses 3, 4, 5, 6 and 8:
///
/// ```html
/// <p>Nederlandse verzen (3-8)</p><h3>Een heilig priesterdom</h3><br/>
/// <p><i><a href="#b60.2.3">1Pt 2:3</a>.</i> Het is belangrijk dat ...</p>
/// <p><i><a href="#b60.2.4">1Pt 2:4</a>.</i> De groei heeft ook een doel ...</p>
/// ```
///
/// Reading only the keys, "Ga naar vers" could offer six of the twenty-five
/// verses of that chapter; reading the markers too, it offers all of them.
///
/// Three forms of marker occur, in that order of preference:
///
///  1. [VerseMarkerKind.anchor] - the MyBible self-link KingComments writes,
///     `<a href="#b60.2.4">1Pt 2:4</a>`, whose href carries book, chapter and
///     verse as numbers. This is the only form in the KingComments corpus
///     today, and the most trustworthy one: the chapter in the href has to
///     match the chapter being read, which throws out cross references to
///     other chapters.
///  2. [VerseMarkerKind.label] - a Dutch verse label, `Vers 4.`,
///     `Verzen 4-6.`, `Vs. 1 en 2.`.
///  3. [VerseMarkerKind.reference] - the same reference as form 1 but written
///     as plain text, `1Pt 2:4.`, with no link around it.
///
/// Only a marker that opens a block counts. A reference in the middle of a
/// sentence is a cross reference, not a boundary - KingComments writes plenty
/// of those, including to the very chapter being read ("Eerder, in 1Pt 2:5,
/// heb je gezien ..."), and treating one as a boundary would cut a paragraph
/// in half. Markers inside a list or a blockquote are skipped for the same
/// reason: Dachsel's entries are one long `<ol>`, and a split there would
/// break the list apart.
library;

import 'package:flutter/foundation.dart';

enum VerseMarkerKind { anchor, label, reference }

/// One verse boundary found in a fragment.
@immutable
class VerseMarker {
  const VerseMarker({
    required this.verse,
    required this.endVerse,
    required this.offset,
    required this.kind,
  });

  /// First verse the marker names.
  final int verse;

  /// Last verse it names: equal to [verse] unless the marker is a range.
  final int endVerse;

  /// Index in the fragment where the block holding the marker opens, so a
  /// caller can cut the fragment there without losing the marker itself.
  final int offset;

  final VerseMarkerKind kind;

  bool get isRange => endVerse > verse;

  /// `4` or `4-6`, for a label the reader can be shown.
  String get label => isRange ? '$verse-$endVerse' : '$verse';

  @override
  String toString() => 'VerseMarker($label @$offset ${kind.name})';
}

/// Block-level openers a marker may follow. `<div>` is in because the MySword
/// exports wrap some paragraphs in one; `<li>` is deliberately out, see the
/// library comment.
final _blockOpen = RegExp(r'<\s*(?:p|div|h[1-6])(?:\s[^>]*)?>', caseSensitive: false);

/// Containers a marker must not be inside of. Tracked as a depth, so a `<p>`
/// nested in a list item is skipped while the next top-level `<p>` is not.
final _container = RegExp(
  r'<\s*(/?)\s*(?:ol|ul|li|blockquote|table|thead|tbody|tr|td|th)(?:\s[^>]*)?>',
  caseSensitive: false,
);

/// Whitespace, `<br>` and inline emphasis between the block opener and the
/// marker. KingComments writes `<p><i><a href=...`, sometimes with a `<br/>`
/// in between.
final _skippable = RegExp(
  r'(?:\s|<\s*br\s*/?>|<\s*(?:i|b|em|strong|span|u|small)(?:\s[^>]*)?>)*',
  caseSensitive: false,
);

/// `<a href="#b60.2.4">` and `<a href="#b46.1.1-3">`: book, chapter, verse,
/// and the last verse of a range.
final _anchorRef = RegExp(
  r'<\s*a\s[^>]*href\s*=\s*"#b(\d+)\.(\d+)\.(\d+)(?:-(\d+))?"',
  caseSensitive: false,
);

/// `Vers 4.`, `Verzen 4-6.`, `Vs. 1 en 2.`, `Vers 4:` - the trailing
/// punctuation or tag is what tells a label apart from prose that happens to
/// open with the word.
final _verseLabel = RegExp(
  r'(?:Verzen|Vers|Vss?\.?)\s*(\d+)\s*(?:(?:-|–|t/m|en|,)\s*(\d+))?\s*(?=[.:;)\]<]|$)',
  caseSensitive: false,
);

/// `1Pt 2:4`, `Rm 8:8`, `1 Ko 15:42-44`: an abbreviation of one to four
/// letters, optionally numbered, then chapter and verse.
final _plainRef = RegExp(
  r'(?:[1-3]\s?)?[A-Z][A-Za-zÀ-ſ]{0,3}\.?\s?(\d+):(\d+)(?:-(\d+))?'
  r'\s*(?=[.:;)\]<]|$)',
);

/// Every verse boundary in [fragment], in the order they appear.
///
/// [chapter] is the chapter the fragment belongs to; a reference naming any
/// other chapter is a cross reference and is ignored. Verse numbers are
/// returned exactly as written - de-duplication and range checks belong to the
/// caller, which is the only side that knows which verses the entry may cover.
List<VerseMarker> findVerseMarkers(String fragment, {required int chapter}) {
  if (fragment.isEmpty) return const [];

  final closes = <int>[];
  final opens = <int>[];
  for (final match in _container.allMatches(fragment)) {
    (match.group(1)!.isEmpty ? opens : closes).add(match.start);
  }

  int depthAt(int index) {
    var depth = 0;
    for (final open in opens) {
      if (open >= index) break;
      depth++;
    }
    for (final close in closes) {
      if (close >= index) break;
      depth--;
    }
    return depth;
  }

  final markers = <VerseMarker>[];
  for (final block in _blockOpen.allMatches(fragment)) {
    if (depthAt(block.start) > 0) continue;
    final at = _skippable.matchAsPrefix(fragment, block.end)?.end ?? block.end;
    final marker = _markerAt(fragment, at, chapter: chapter, offset: block.start);
    if (marker != null) markers.add(marker);
  }
  return markers;
}

VerseMarker? _markerAt(
  String fragment,
  int at, {
  required int chapter,
  required int offset,
}) {
  final anchor = _anchorRef.matchAsPrefix(fragment, at);
  if (anchor != null) {
    // The href is machine-written, so a chapter mismatch is a real cross
    // reference rather than a parse slip, and there is nothing to fall back to.
    if (int.parse(anchor.group(2)!) != chapter) return null;
    return _marker(anchor.group(3)!, anchor.group(4), offset, VerseMarkerKind.anchor);
  }

  final label = _verseLabel.matchAsPrefix(fragment, at);
  if (label != null) {
    return _marker(label.group(1)!, label.group(2), offset, VerseMarkerKind.label);
  }

  final plain = _plainRef.matchAsPrefix(fragment, at);
  if (plain != null && int.parse(plain.group(1)!) == chapter) {
    return _marker(plain.group(2)!, plain.group(3), offset, VerseMarkerKind.reference);
  }
  return null;
}

VerseMarker? _marker(String first, String? last, int offset, VerseMarkerKind kind) {
  final verse = int.tryParse(first);
  if (verse == null || verse < 1) return null;
  final end = last == null ? verse : (int.tryParse(last) ?? verse);
  return VerseMarker(
    verse: verse,
    endVerse: end < verse ? verse : end,
    offset: offset,
    kind: kind,
  );
}
