import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bijbelstudie_mobile/features/commentary/present/commentary_body.dart';
import 'package:bijbelstudie_mobile/features/commentary/present/commentary_format.dart';
import 'package:bijbelstudie_mobile/features/settings/data/reading_settings.dart';

/// Guards the commentary reader against the two ways it can go wrong.
///
/// It used to flatten every entry to plain text before painting it, which made
/// Matthew Henry - eleven kilobytes of nested outline per verse - one unbroken
/// column. The parser now keeps the structure the website styles in
/// `formatCommentaryText()`, and these tests hold the three shapes it has to
/// keep telling apart: an HTML fragment, a Dachsel `***verse***` entry, and
/// plain prose.
void main() {
  group('plain prose, Matthew Henry', () {
    test('splits on blank lines and reads the outline markers', () {
      final blocks = parseCommentary(
        'In dit vers hebben wij het werk van de schepping.\n\n'
        'I. In haar korte samenvatting, vers 1.\n\n'
        '${r'1\. De uitwerking.'}\n\n'
        'a. Een onderpunt.\n\n'
        '(1) Nog een stap dieper.',
      );

      expect(blocks.map((b) => b.kind).toList(), [
        CommentaryBlockKind.paragraph,
        CommentaryBlockKind.section,
        CommentaryBlockKind.paragraph,
        CommentaryBlockKind.paragraph,
        CommentaryBlockKind.paragraph,
      ]);
      expect(blocks.map((b) => b.indent).toList(), [0, 0, 1, 2, 3]);
    });

    test('undoes the MySword escape, as all three web formatters do', () {
      final blocks = parseCommentary(r'1\. De uitwerking.');
      expect(blocks.single.text, '1. De uitwerking.');
    });

    test('folds the em dash the source texts are full of', () {
      // Written as the code point, because the repo does not carry the
      // character itself outside of what `normaliseDashes` folds away.
      const emDash = '\u2014';
      final blocks = parseCommentary('Een zin $emDash en nog een.');
      expect(blocks.single.text, 'Een zin - en nog een.');
      expect(blocks.single.text, isNot(contains(emDash)));
    });

    test('joins single newlines inside a paragraph', () {
      final blocks = parseCommentary('Een regel\nen de volgende.');
      expect(blocks.single.text, 'Een regel en de volgende.');
    });
  });

  group('HTML fragments, Dachsel and KingComments', () {
    // The shape verified against the live API.
    const fragment =
        '<ol><li><div class="s9">Vs. 1 en 2. God schept&#8212;in den '
        'beginne.</div></li>\n'
        '<li><div class="s10">In den beginne <sup>1</sup> schiep '
        '<b>God</b> den hemel.</div></li></ol>';

    test('numbers the list items and drops every tag', () {
      final blocks = parseCommentary(fragment);

      expect(blocks.length, 2);
      expect(blocks.every((b) => b.kind == CommentaryBlockKind.listItem), true);
      expect(blocks.map((b) => b.marker).toList(), ['1.', '2.']);
      expect(blocks.map((b) => b.text).join(), isNot(contains('<')));
    });

    test('decodes entities and folds the em dash they can carry', () {
      final blocks = parseCommentary(fragment);
      expect(blocks.first.text, 'Vs. 1 en 2. God schept-in den beginne.');
    });

    test('keeps the emphasis the fragment was written with', () {
      final blocks = parseCommentary(fragment);
      final marker = blocks.last.spans.firstWhere((s) => s.superscript);
      expect(marker.text, '1');
      expect(marker.accent, true);
      expect(blocks.last.spans.any((s) => s.bold && s.text == 'God'), true);
    });

    test('reads headings and emphasis out of a KingComments entry', () {
      final blocks = parseCommentary(
        '<h3>De schepping</h3><p>Het <i>eerste</i> woord.</p>'
        '<h4>Aantekening</h4><p>Zie '
        '<a href="#bGen.1.1">Genesis 1:1</a>.</p>',
      );

      expect(blocks.map((b) => b.kind).toList(), [
        CommentaryBlockKind.heading,
        CommentaryBlockKind.paragraph,
        CommentaryBlockKind.subheading,
        CommentaryBlockKind.paragraph,
      ]);
      expect(blocks[1].spans.any((s) => s.italic && s.text == 'eerste'), true);
      // The MyBible links go nowhere the app can follow, so they are painted
      // rather than linked - as on the website.
      expect(blocks.last.spans.any((s) => s.accent && s.italic), true);
    });
  });

  group('Dachsel plain text', () {
    const entry =
        '***1. In den beginne 1) schiep God den hemel.***\n\n'
        'Het begin waarvan hier sprake is, is het begin van de tijd.\n\n'
        '1) Hebr. bara, scheppen uit niets.\n\n'
        'En dat is meer dan formeren.';

    test('lifts the verse citation into a quote with raised markers', () {
      final blocks = parseCommentary(entry);

      expect(blocks.first.kind, CommentaryBlockKind.quote);
      expect(blocks.first.text, startsWith('In den beginne'));
      final marker = blocks.first.spans.firstWhere((s) => s.superscript);
      expect(marker.text, '1');
    });

    test('collects the footnotes under the body, in order', () {
      final blocks = parseCommentary(entry);

      expect(blocks.map((b) => b.kind).toList(), [
        CommentaryBlockKind.quote,
        CommentaryBlockKind.paragraph,
        CommentaryBlockKind.footnote,
        CommentaryBlockKind.footnote,
      ]);
      expect(blocks[2].marker, '1');
      // A continuation of the same footnote is not numbered again.
      expect(blocks[3].marker, isNull);
    });
  });

  group('CommentaryBody', () {
    Future<void> pump(WidgetTester tester, ReadingSettings settings) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentaryBody(
              text: 'Eerste alinea.\n\nI. Een kop.',
              settings: settings,
            ),
          ),
        ),
      );
    }

    testWidgets('honours every reader typography setting', (tester) async {
      await pump(
        tester,
        const ReadingSettings(
          fontSize: ReaderFontSize.large,
          lineHeight: ReaderLineHeight.loose,
          fontFamily: ReaderFontFamily.serif,
        ),
      );

      final style = tester
          .widget<Text>(find.byType(Text).first)
          .textSpan!
          .style!;
      expect(style.fontFamily, ReaderFontFamily.serif.fontName);
      expect(style.fontSize, ReaderFontSize.large.points * 0.92);
      expect(style.height, ReaderLineHeight.loose.factor);
    });

    testWidgets('rescales when the reader changes the font size', (
      tester,
    ) async {
      await pump(tester, const ReadingSettings());
      final before = tester
          .widget<Text>(find.byType(Text).first)
          .textSpan!
          .style!
          .fontSize!;

      await pump(
        tester,
        const ReadingSettings(fontSize: ReaderFontSize.xlarge),
      );
      final after = tester
          .widget<Text>(find.byType(Text).first)
          .textSpan!
          .style!
          .fontSize!;

      expect(after, greaterThan(before));
    });

    testWidgets('paints nothing for an entry with no text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CommentaryBody(text: '   ', settings: ReadingSettings()),
          ),
        ),
      );
      expect(find.byType(Text), findsNothing);
    });
  });
}
