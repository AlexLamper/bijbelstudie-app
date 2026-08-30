/// Turns a raw book introduction into paragraphs the reader can actually read.
///
/// The port of `formatSummaryText` in the website's
/// `components/study/HistoricalContext.tsx`. The app was rendering the API's
/// string straight into a `SelectableText`, which is why the tab looked like
/// one unbroken wall of prose: the separators the text does carry are bare
/// carriage returns (`\r\r`, not `\n\n`), and a lone `\r` buys nothing in a
/// Flutter paragraph. Even where it did break, nothing put vertical space
/// between the resulting lines.
///
/// Two shapes have to be handled, exactly as the website handles them:
///
///  1. Text with explicit blank-line breaks — split on those and keep them.
///  2. One long block with no breaks at all — group sentences into paragraphs,
///     closing one after a sentence that ends on a scripture reference, and
///     after four sentences regardless, so a book with no markup still reads
///     as paragraphs rather than as a page-long block.
library;

enum SummaryParagraphKind {
  /// An ALL CAPS line acting as a section title.
  heading,

  /// A numbered point: `1. …`.
  numbered,

  /// Ordinary prose.
  body,
}

class SummaryParagraph {
  const SummaryParagraph(this.text, this.kind);

  final String text;
  final SummaryParagraphKind kind;
}

/// Matches a parenthesised scripture reference, e.g. `(Gen 1:1)` or
/// `(Num 1:1-54)`. Rendered in teal so a reference reads as a citation rather
/// than as part of the sentence.
final RegExp summaryReferencePattern = RegExp(
  r'\(([A-Z][a-z]{0,5}\.?\s*\d+:\d+[\d:,\s\-–]*)\)',
);

final RegExp _allCapsHeading = RegExp(r'^[A-Z\s]{6,}$');
final RegExp _numberedPoint = RegExp(r'^\d+\.\s');

/// Sentence boundary: a full stop, whitespace, then a capital. The accented
/// capitals matter — Dutch prose opens sentences with `Één`, `Óók`, and a bare
/// `A-Z` class would run those into the previous sentence.
final RegExp _sentenceBoundary = RegExp(r'\.\s+(?=[A-ZÀ-Þ])');

/// A sentence that closes on a scripture reference, which is where the website
/// prefers to end a paragraph.
final RegExp _endsWithReference = RegExp(r'\([\w\s.:,\-–]+\)\.?\s*$');

List<SummaryParagraph> formatSummary(String? raw) {
  if (raw == null) return const [];

  // `\r\n` and lone `\r` both mean "line break" here. The API's own text uses
  // bare `\r`, so normalising is what makes the blank-line branch below fire
  // at all rather than falling through to sentence grouping every time.
  final normalised = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (normalised.trim().isEmpty) return const [];

  final paragraphs = RegExp(r'\n{2,}').hasMatch(normalised)
      ? _splitOnBlankLines(normalised)
      : _groupSentences(normalised);

  return [
    for (final paragraph in paragraphs) _classify(paragraph),
  ];
}

List<String> _splitOnBlankLines(String text) {
  return text
      .split(RegExp(r'\n{2,}'))
      .map((p) => p.replaceAll('\n', ' ').trim())
      .where((p) => p.isNotEmpty)
      .toList(growable: false);
}

List<String> _groupSentences(String text) {
  final flat = text.replaceAll('\n', ' ').trim();

  // Split without losing the full stop that marked the boundary.
  final sentences = <String>[];
  var start = 0;
  for (final match in _sentenceBoundary.allMatches(flat)) {
    // `end` of the match swallows the whitespace; the stop itself belongs to
    // the sentence being closed.
    final sentence = flat.substring(start, match.start + 1).trim();
    if (sentence.isNotEmpty) sentences.add(sentence);
    start = match.end;
  }
  final tail = flat.substring(start).trim();
  if (tail.isNotEmpty) sentences.add(tail);

  final paragraphs = <String>[];
  var current = <String>[];
  for (final sentence in sentences) {
    current.add(sentence);
    final closesOnReference = _endsWithReference.hasMatch(sentence);
    if ((closesOnReference && current.length >= 2) || current.length >= 4) {
      paragraphs.add(current.join(' '));
      current = <String>[];
    }
  }
  if (current.isNotEmpty) paragraphs.add(current.join(' '));

  return paragraphs.where((p) => p.trim().isNotEmpty).toList(growable: false);
}

SummaryParagraph _classify(String paragraph) {
  final trimmed = paragraph.trim();
  if (_allCapsHeading.hasMatch(trimmed)) {
    return SummaryParagraph(trimmed, SummaryParagraphKind.heading);
  }
  if (_numberedPoint.hasMatch(trimmed)) {
    return SummaryParagraph(trimmed, SummaryParagraphKind.numbered);
  }
  return SummaryParagraph(trimmed, SummaryParagraphKind.body);
}
