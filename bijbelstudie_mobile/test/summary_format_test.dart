import 'package:flutter_test/flutter_test.dart';

import 'package:bijbelstudie_mobile/features/study/domain/summary_format.dart';

/// The "Algemene info" tab used to render the API's string as-is, and the
/// separators in that string are bare carriage returns — which buy no vertical
/// space in a Flutter paragraph. Several thousand words arrived as one block.

void main() {
  test('bare carriage returns are real paragraph breaks', () {
    // Exactly the shape /api/v1/summary returns for Genesis.
    const raw = 'Ongeveer 1805 VC.\r\rIn het begin spreekt God (Gen 1:1).'
        '\r\rMaar in Eden sluipt bedrog binnen (Gen 3:1-6).';

    final paragraphs = formatSummary(raw);

    expect(paragraphs, hasLength(3));
    expect(paragraphs.first.text, 'Ongeveer 1805 VC.');
    expect(paragraphs.last.text, 'Maar in Eden sluipt bedrog binnen (Gen 3:1-6).');
    expect(
      paragraphs.every((p) => p.kind == SummaryParagraphKind.body),
      isTrue,
    );
  });

  test('\\r\\n and blank lines break too', () {
    final paragraphs = formatSummary('Eerste alinea.\r\n\r\nTweede alinea.');
    expect(paragraphs.map((p) => p.text), ['Eerste alinea.', 'Tweede alinea.']);
  });

  test('a single unbroken block is grouped into paragraphs', () {
    // Six sentences, no breaks anywhere: the branch that stops a book with no
    // markup from rendering as one page-long block.
    const raw = 'Een zin over het boek. Twee zin over het boek. '
        'Drie zin over het boek. Vier zin over het boek. '
        'Vijf zin over het boek. Zes zin over het boek.';

    final paragraphs = formatSummary(raw);

    expect(paragraphs.length, greaterThan(1));
    // Nothing is lost in the regrouping.
    expect(
      paragraphs.map((p) => p.text).join(' '),
      raw,
    );
  });

  test('a paragraph closes on a scripture reference', () {
    const raw = 'God schiep de hemel. Hij vormde het land (Gen 1:3-19). '
        'Daarna kwam de mens. En toen rustte Hij.';
    final paragraphs = formatSummary(raw);
    expect(paragraphs.first.text.endsWith('(Gen 1:3-19).'), isTrue);
  });

  test('ALL CAPS lines are headings and numbered points are numbered', () {
    final paragraphs = formatSummary(
      'DE SCHEPPING\r\r1. God spreekt.\r\rGewone tekst.',
    );
    expect(paragraphs[0].kind, SummaryParagraphKind.heading);
    expect(paragraphs[1].kind, SummaryParagraphKind.numbered);
    expect(paragraphs[2].kind, SummaryParagraphKind.body);
  });

  test('nothing in, nothing out', () {
    expect(formatSummary(null), isEmpty);
    expect(formatSummary(''), isEmpty);
    expect(formatSummary('   \r\n  '), isEmpty);
  });

  test('scripture references are found for highlighting', () {
    final matches = summaryReferencePattern
        .allMatches('Hij vormde het land (Gen 1:3-19) en de zee (Num 1:1-54).')
        .map((m) => m.group(0))
        .toList();
    expect(matches, ['(Gen 1:3-19)', '(Num 1:1-54)']);
  });
}
