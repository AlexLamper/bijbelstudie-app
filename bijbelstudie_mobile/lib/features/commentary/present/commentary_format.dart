/// Turns one commentary entry into the blocks the reader paints.
///
/// Mirrors `formatCommentaryText()` in
/// `components/study/CommentaryComponent.tsx` on the website, which dispatches
/// on the shape of the entry and hands each shape to its own formatter:
///
///  - an HTML fragment (Dachsel, KingComments) to `formatHtmlCommentary`,
///    verified against the live API, e.g.
///    `<ol><li><div class="s9">Vs. 1 en 2. God schept...</div></li>`;
///  - a Dachsel plain-text entry, recognised by its `***verse***` citation, to
///    `formatDachselText`;
///  - plain prose (Matthew Henry) to `formatPlainText`.
///
/// The website's formatters emit styled HTML and let the browser lay it out.
/// The app has no browser, so the same three emit [CommentaryBlock]s and
/// `commentary_body.dart` paints them.
///
/// Parsing to a model rather than adding an HTML rendering package is
/// deliberate. Two of the three shapes are not HTML at all, so a package would
/// still need a formatter in front of it; the reader's typography preferences
/// have to reach every line of text, which is far easier to honour when the
/// app owns the `TextStyle`; and this ships on iOS, where every dependency is
/// binary the reviewer can trip over. The subset of HTML the corpus actually
/// contains is a dozen tags wide.
///
/// Anything the parser does not recognise is dropped, which is the right
/// failure mode: a stray tag must never appear as literal `<div>` in the
/// reader.
library;

import '../../../core/data/text_format.dart';

/// What a block is, which is what decides how it is painted.
enum CommentaryBlockKind {
  /// Body prose. [CommentaryBlock.indent] carries the outline depth.
  paragraph,

  /// A Roman-numeral outline heading in Matthew Henry: `I.`, `II.`, `III.`.
  /// The website gives these a teal left rule.
  section,

  /// `<h1>`-`<h3>` in an HTML entry.
  heading,

  /// `<h4>`-`<h6>` in an HTML entry.
  subheading,

  /// `<li>`. [CommentaryBlock.marker] is the number or bullet.
  listItem,

  /// `<blockquote>`, and the `***verse***` citation that opens a Dachsel
  /// entry.
  quote,

  /// A Dachsel footnote. [CommentaryBlock.marker] is its number, absent on the
  /// second and later paragraphs of the same footnote.
  footnote,
}

/// A run of text within a block, carrying the emphasis it was written with.
class CommentarySpan {
  const CommentarySpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.accent = false,
    this.superscript = false,
  });

  final String text;
  final bool bold;
  final bool italic;

  /// Painted in the brand teal: internal MyBible references, footnote markers.
  final bool accent;

  final bool superscript;
}

/// One paintable block of a commentary entry.
class CommentaryBlock {
  const CommentaryBlock({
    required this.kind,
    required this.spans,
    this.indent = 0,
    this.marker,
  });

  final CommentaryBlockKind kind;
  final List<CommentarySpan> spans;

  /// Outline depth, 0-3. Mirrors the `padding-left` steps `formatPlainText`
  /// gives numbered, lettered and parenthesised points.
  final int indent;

  /// Rendered in the gutter: a list number, a footnote number.
  final String? marker;

  String get text => spans.map((span) => span.text).join();
}

/// The website's dispatcher, `formatCommentaryText`.
List<CommentaryBlock> parseCommentary(String input) {
  // Both the em dash fold and the MySword escape apply to every shape, so they
  // happen before the dispatch rather than three times after it. `1\.` is an
  // artefact of the MySword export the corpus was built from; the website
  // strips it at the head of all three of its formatters.
  final raw = normaliseDashes(
    input,
  ).replaceAllMapped(_mySwordEscape, (m) => '${m[1]}.');

  if (raw.trim().isEmpty) return const [];
  if (_htmlish.hasMatch(raw)) return _parseHtml(raw);
  if (raw.contains('***')) return _parseDachselText(raw);
  return _parsePlainText(raw);
}

final _htmlish = RegExp(r'<[a-zA-Z][^>]*>');
final _mySwordEscape = RegExp(r'([A-Za-z0-9])\\\.');
final _blockBreak = RegExp(r'\n{2,}');
final _whitespace = RegExp(r'\s+');

// --- Plain prose, Matthew Henry ------------------------------------------
//
// Mirrors `formatPlainText`. The outline markers are the only structure the
// text carries, and they are what turn eleven kilobytes of Henry from a wall
// into something with a shape.

final _romanPoint = RegExp(r'^(I{1,3}|IV|VI{0,3}|IX|X{1,3})\.\s');
final _numberedPoint = RegExp(r'^\d+\.\s');
final _capitalPoint = RegExp(r'^[A-Z]\.\s');
final _lowercasePoint = RegExp(r'^[a-z]\.\s');
final _parenthesisedPoint = RegExp(r'^\(\d+\)[.)\s]');

List<CommentaryBlock> _parsePlainText(String raw) {
  final blocks = <CommentaryBlock>[];

  for (final part in raw.split(_blockBreak)) {
    final line = _oneLine(part);
    if (line.isEmpty) continue;

    if (_romanPoint.hasMatch(line)) {
      blocks.add(
        CommentaryBlock(
          kind: CommentaryBlockKind.section,
          spans: [CommentarySpan(line)],
        ),
      );
      continue;
    }

    final indent = _numberedPoint.hasMatch(line) || _capitalPoint.hasMatch(line)
        ? 1
        : _lowercasePoint.hasMatch(line)
        ? 2
        : _parenthesisedPoint.hasMatch(line)
        ? 3
        : 0;

    blocks.add(
      CommentaryBlock(
        kind: CommentaryBlockKind.paragraph,
        spans: [CommentarySpan(line)],
        indent: indent,
      ),
    );
  }

  return blocks;
}

// --- Dachsel plain text ---------------------------------------------------
//
// Mirrors `formatDachselText`: a `***Bible text 1) ...***` citation, then the
// commentary, then numbered footnotes that the citation's markers point at.

final _verseCitation = RegExp(r'^\*{1,3}([\s\S]+?)\*{1,3}$');
final _citationNumber = RegExp(r'^\d+\.\s*');
final _footnoteOpener = RegExp(r'^(\d{1,2})\)\s+(.+)$');

/// A footnote marker inside the citation: `1)` with a space or comma on both
/// sides, so ordinary parentheses in the text are left alone.
final _inlineMarker = RegExp(r'([\s,])(\d{1,2})\)(?=[\s,])');

List<CommentaryBlock> _parseDachselText(String raw) {
  final citation = <CommentaryBlock>[];
  final body = <CommentaryBlock>[];
  final footnotes = <CommentaryBlock>[];
  var inFootnote = false;

  for (final part in raw.split(_blockBreak)) {
    final line = _oneLine(part);
    if (line.isEmpty) continue;

    final cited = _verseCitation.firstMatch(line);
    if (cited != null) {
      inFootnote = false;
      citation.add(
        CommentaryBlock(
          kind: CommentaryBlockKind.quote,
          spans: _withInlineMarkers(
            cited.group(1)!.replaceFirst(_citationNumber, ''),
            italic: true,
          ),
        ),
      );
      continue;
    }

    final opener = _footnoteOpener.firstMatch(line);
    if (opener != null) {
      inFootnote = true;
      footnotes.add(
        CommentaryBlock(
          kind: CommentaryBlockKind.footnote,
          spans: [CommentarySpan(opener.group(2)!)],
          marker: opener.group(1),
        ),
      );
      continue;
    }

    if (inFootnote) {
      // A continuation of the footnote above, so no marker of its own.
      footnotes.add(
        CommentaryBlock(
          kind: CommentaryBlockKind.footnote,
          spans: [CommentarySpan(line)],
        ),
      );
    } else {
      body.add(
        CommentaryBlock(
          kind: CommentaryBlockKind.paragraph,
          spans: [CommentarySpan(line)],
        ),
      );
    }
  }

  return [...citation, ...body, ...footnotes];
}

List<CommentarySpan> _withInlineMarkers(String text, {bool italic = false}) {
  final spans = <CommentarySpan>[];
  var cursor = 0;

  for (final match in _inlineMarker.allMatches(text)) {
    final before = text.substring(cursor, match.start) + match.group(1)!;
    if (before.isNotEmpty) spans.add(CommentarySpan(before, italic: italic));
    spans.add(
      CommentarySpan(
        match.group(2)!,
        accent: true,
        bold: true,
        superscript: true,
      ),
    );
    cursor = match.end;
  }

  final rest = text.substring(cursor);
  if (rest.isNotEmpty) spans.add(CommentarySpan(rest, italic: italic));
  return spans;
}

// --- HTML fragments -------------------------------------------------------
//
// Mirrors `formatHtmlCommentary`, which cleans up the MySword export and hands
// the rest to the browser. Here the "rest" is a tokeniser over the dozen tags
// the corpus uses; everything else is dropped.

final _tagToken = RegExp(r'<(/?)\s*([a-zA-Z][a-zA-Z0-9]*)([^>]*)>');
final _internalLink = RegExp(r'href\s*=\s*"#b', caseSensitive: false);

/// The emphasis in force at a point in the fragment.
class _Emphasis {
  const _Emphasis({
    this.bold = false,
    this.italic = false,
    this.accent = false,
    this.superscript = false,
  });

  final bool bold;
  final bool italic;
  final bool accent;
  final bool superscript;

  _Emphasis merge({
    bool bold = false,
    bool italic = false,
    bool accent = false,
    bool superscript = false,
  }) {
    return _Emphasis(
      bold: this.bold || bold,
      italic: this.italic || italic,
      accent: this.accent || accent,
      superscript: this.superscript || superscript,
    );
  }
}

List<CommentaryBlock> _parseHtml(String raw) {
  final blocks = <CommentaryBlock>[];
  var spans = <CommentarySpan>[];

  // Tags that change the kind of block nest, so they are a stack rather than a
  // single value: a `<li>` inside a `<blockquote>` is still a list item.
  final kinds = <(String, CommentaryBlockKind)>[
    ('', CommentaryBlockKind.paragraph),
  ];
  // Likewise emphasis. Keeping the tag name alongside lets a stray `</b>` in
  // the export close the `<b>` it belongs to and nothing else.
  final emphasis = <(String, _Emphasis)>[('', const _Emphasis())];
  // One entry per open `<ol>`/`<ul>`: the counter, or null for a bullet list.
  final lists = <int?>[];

  String? marker;

  void flush() {
    final trimmed = _trimSpans(spans);
    spans = <CommentarySpan>[];
    if (trimmed.isEmpty) return;
    blocks.add(
      CommentaryBlock(
        kind: kinds.last.$2,
        spans: trimmed,
        marker: marker,
      ),
    );
    // A list item that wraps two paragraphs is numbered once.
    marker = null;
  }

  void closeKind(String tag) {
    for (var i = kinds.length - 1; i > 0; i--) {
      if (kinds[i].$1 != tag) continue;
      flush();
      kinds.removeRange(i, kinds.length);
      return;
    }
    flush();
  }

  void closeEmphasis(String tag) {
    for (var i = emphasis.length - 1; i > 0; i--) {
      if (emphasis[i].$1 != tag) continue;
      emphasis.removeRange(i, emphasis.length);
      return;
    }
  }

  var cursor = 0;
  void addText(String source) {
    final text = _decodeEntities(source).replaceAll(_whitespace, ' ');
    if (text.isEmpty) return;
    if (text == ' ' && spans.isEmpty) return;
    spans.add(
      CommentarySpan(
        text,
        bold: emphasis.last.$2.bold,
        italic: emphasis.last.$2.italic,
        accent: emphasis.last.$2.accent,
        superscript: emphasis.last.$2.superscript,
      ),
    );
  }

  for (final match in _tagToken.allMatches(raw)) {
    if (match.start > cursor) addText(raw.substring(cursor, match.start));
    cursor = match.end;

    final closing = match.group(1)!.isNotEmpty;
    final tag = match.group(2)!.toLowerCase();
    final attributes = match.group(3)!;

    switch (tag) {
      case 'br':
        flush();
      case 'p':
      case 'div':
        flush();
      case 'ol':
      case 'ul':
        flush();
        if (closing) {
          if (lists.isNotEmpty) lists.removeLast();
        } else {
          lists.add(tag == 'ol' ? 0 : null);
        }
      case 'li':
        if (closing) {
          closeKind('li');
        } else {
          flush();
          if (lists.isEmpty) {
            marker = '•';
          } else if (lists.last == null) {
            marker = '•';
          } else {
            lists[lists.length - 1] = lists.last! + 1;
            marker = '${lists.last}.';
          }
          kinds.add(('li', CommentaryBlockKind.listItem));
        }
      case 'blockquote':
        if (closing) {
          closeKind('blockquote');
        } else {
          flush();
          kinds.add(('blockquote', CommentaryBlockKind.quote));
        }
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        if (closing) {
          closeKind(tag);
        } else {
          flush();
          final level = int.parse(tag.substring(1));
          kinds.add((
            tag,
            level <= 3
                ? CommentaryBlockKind.heading
                : CommentaryBlockKind.subheading,
          ));
        }
      case 'b':
      case 'strong':
        if (closing) {
          closeEmphasis(tag);
        } else {
          emphasis.add((tag, emphasis.last.$2.merge(bold: true)));
        }
      case 'i':
      case 'em':
        if (closing) {
          closeEmphasis(tag);
        } else {
          emphasis.add((tag, emphasis.last.$2.merge(italic: true)));
        }
      case 'sup':
        if (closing) {
          closeEmphasis(tag);
        } else {
          emphasis.add((
            tag,
            emphasis.last.$2.merge(superscript: true, accent: true, bold: true),
          ));
        }
      case 'a':
        // The MyBible links (`#bGen.1.1`) go nowhere the app can follow, so
        // the website paints them as teal italic rather than as a link, and so
        // does this.
        if (closing) {
          closeEmphasis(tag);
        } else {
          final internal = _internalLink.hasMatch(attributes);
          emphasis.add((
            tag,
            emphasis.last.$2.merge(accent: true, italic: internal),
          ));
        }
    }
  }

  if (cursor < raw.length) addText(raw.substring(cursor));
  flush();

  return blocks;
}

List<CommentarySpan> _trimSpans(List<CommentarySpan> spans) {
  final kept = spans.where((span) => span.text.isNotEmpty).toList();
  if (kept.isEmpty) return const [];

  kept[0] = _replaceText(kept.first, kept.first.text.trimLeft());
  kept[kept.length - 1] = _replaceText(kept.last, kept.last.text.trimRight());

  final result = kept.where((span) => span.text.isNotEmpty).toList();
  final joined = result.map((span) => span.text).join();
  return joined.trim().isEmpty ? const [] : result;
}

CommentarySpan _replaceText(CommentarySpan span, String text) {
  return CommentarySpan(
    text,
    bold: span.bold,
    italic: span.italic,
    accent: span.accent,
    superscript: span.superscript,
  );
}

/// One block of source text as a single line, the way the website's formatters
/// do it: `trimmed.replace(/\n+/g, ' ')`.
String _oneLine(String source) =>
    _decodeEntities(source).replaceAll(_whitespace, ' ').trim();

const _entities = <String, String>{
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&apos;': "'",
  '&#39;': "'",
  '&nbsp;': ' ',
  '&ndash;': '–',
  '&mdash;': '-',
  '&hellip;': '…',
  '&eacute;': 'é',
  '&euml;': 'ë',
  '&iuml;': 'ï',
  '&ouml;': 'ö',
  '&uuml;': 'ü',
};

String _decodeEntities(String input) {
  var out = input;
  _entities.forEach((entity, replacement) {
    out = out.replaceAll(entity, replacement);
  });
  // Numeric entities, e.g. &#233;
  out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
    final code = int.tryParse(match.group(1)!);
    return code == null ? match.group(0)! : String.fromCharCode(code);
  });
  // Second of the two places an em dash can still enter: `&#8212;` decodes to
  // one long after [parseCommentary] folded the literal ones.
  return normaliseDashes(out);
}
