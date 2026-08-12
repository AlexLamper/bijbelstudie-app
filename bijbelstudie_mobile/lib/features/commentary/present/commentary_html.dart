/// Dachsel's commentary entries arrive as small HTML fragments — verified
/// against the live API, e.g.
/// `<ol><li><div class="s9">Vs. 1 en 2. God schept...</div></li>`.
/// Matthew Henry's are plain text.
///
/// Rather than pull in a full HTML rendering package for a handful of block
/// tags, this flattens the fragment to readable text: list items become
/// bullets, block ends become line breaks, entities are decoded. Anything it
/// does not recognise is simply dropped, which is the right failure mode —
/// a stray tag must never appear as literal `<div>` in the reader.
String commentaryToPlainText(String input) {
  if (!input.contains('<')) return input.trim();

  var text = input;

  // Block boundaries first, while the tags are still there to see.
  text = text.replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ');
  text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAll(
    RegExp(r'</(p|div|li|ol|ul|h[1-6]|blockquote)>', caseSensitive: false),
    '\n',
  );

  // Everything else goes.
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');

  text = _decodeEntities(text);

  // Collapse the whitespace the tag soup left behind.
  text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
  text = text.replaceAll(RegExp(r' *\n *'), '\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  return text.trim();
}

const _entities = <String, String>{
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&apos;': "'",
  '&#39;': "'",
  '&nbsp;': ' ',
  '&ndash;': '–',
  '&mdash;': '—',
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
  return out;
}
