import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../domain/bible_progress.dart';
import '../domain/bookcase.dart';
import 'bookcase_view.dart';

/// A closed book seen from the front: the group colour, a darker spine edge,
/// the title in Lora, a rule under it and, when [ribbon] is set, a leeslint
/// hanging out at the bottom. Used for the leeslint card, the reading table
/// and the book sheet.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.title,
    required this.color,
    this.width = 70,
    this.height = 90,
    this.titleSize,
    this.ruleTop,
    this.ribbon,
  });

  final String title;
  final Color color;
  final double width;
  final double height;
  final double? titleSize;
  final double? ruleTop;

  /// Colour of the leeslint, or null for none.
  final Color? ribbon;

  @override
  Widget build(BuildContext context) {
    final k = width / 70;
    // Shrink so the longest word fits the cover; Lora runs about 0.6 em a
    // letter. Same rule as BookCover on the website.
    final longest = title.split(' ').fold<int>(1, (m, w) => math.max(m, w.length));
    final size = math.min(titleSize ?? (title.length > 9 ? 8.6 : 10.5) * k, (width - 18 * k) / (longest * 0.6));
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(3.5 * k),
                  right: Radius.circular(8 * k),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x660F172A),
                    blurRadius: 14,
                    offset: Offset(0, 8),
                    spreadRadius: -8,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 7 * k,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.24),
                borderRadius: BorderRadius.horizontal(left: Radius.circular(3.5 * k)),
              ),
            ),
          ),
          if (title.isNotEmpty)
            Positioned(
              left: 13 * k,
              right: 5 * k,
              top: 11 * k,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontFamily: AppTheme.serifFontName,
                  fontVariations: const [FontVariation.weight(600)],
                  fontWeight: FontWeight.w600,
                  fontSize: size,
                  height: 1.15,
                  color: Colors.white,
                ),
              ),
            ),
          Positioned(
            left: 13 * k,
            right: 9 * k,
            top: ruleTop ?? 40 * k,
            height: 1,
            child: const ColoredBox(color: Color(0x80FFFFFF)),
          ),
          if (ribbon != null)
            Positioned(
              right: 12 * k,
              bottom: -11 * k,
              width: 8 * k,
              height: 24 * k,
              child: CustomPaint(painter: RibbonPainter(ribbon!)),
            ),
        ],
      ),
    );
  }
}

/// A ribbon end with a V cut, the darker right half suggesting the fold.
class RibbonPainter extends CustomPainter {
  RibbonPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final notch = h * 0.2;
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..lineTo(w, h)
        ..lineTo(w / 2, h - notch)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = color,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w / 2, 0)
        ..lineTo(w, 0)
        ..lineTo(w, h)
        ..lineTo(w / 2, h - notch)
        ..close(),
      Paint()..color = Colors.black.withValues(alpha: 0.14),
    );
  }

  @override
  bool shouldRepaint(RibbonPainter old) => old.color != color;
}

/// A slim rounded bar in [color] over the sunken track.
class ShelfBar extends StatelessWidget {
  const ShelfBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 6,
    this.width,
  });

  final double value;
  final Color color;
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final v = value.clamp(0.0, 1.0);
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: AppTheme.paperSunkenStrong)),
            if (v > 0)
              FractionallySizedBox(
                widthFactor: math.max(v, 0.04),
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Opens the sheet for one book on the shelf: how far along it is, a button
/// to carry on reading, and every chapter as a tappable cell. [leeslint] is
/// the chapter the reading ribbon lies at when this is the current book.
/// [onRead] gets the chapter to open after the sheet has closed itself.
Future<void> showShelfBookSheet(
  BuildContext context, {
  required BookProgress book,
  int? leeslint,
  required void Function(int chapter) onRead,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _BookSheet(
      book: book,
      leeslint: leeslint,
      onRead: (chapter) {
        Navigator.of(sheetContext).pop();
        onRead(chapter);
      },
    ),
  );
}

class _BookSheet extends StatelessWidget {
  const _BookSheet({required this.book, required this.leeslint, required this.onRead});

  final BookProgress book;
  final int? leeslint;
  final void Function(int chapter) onRead;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final palette = BookcasePalette.current;
    final color = shelfColorFor(book.name);
    final group = bookGroupIndex[book.name] ?? 0;
    final share = book.readCount / math.max(1, book.chapters);
    final next = leeslint ?? (book.completed ? 1 : firstUnreadChapter(book));
    final cta = book.completed ? 'Lees ${book.name} opnieuw' : 'Lees ${book.name} $next';
    final status = book.completed
        ? 'Alle ${book.chapters} hoofdstukken gelezen'
        : book.started
            ? '${book.readCount} van ${book.chapters} hoofdstukken gelezen'
            : 'Nog niet begonnen, ${book.chapters} ${book.chapters == 1 ? 'hoofdstuk' : 'hoofdstukken'}';
    final media = MediaQuery.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + media.padding.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                BookCover(
                  title: spineLabels[book.name] ?? '',
                  color: color,
                  width: 50,
                  height: 66,
                  titleSize: 10,
                  ruleTop: 28,
                  ribbon: leeslint != null ? ribbonRed : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shelfPlaques[group], style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600)),
                      Semantics(
                        header: true,
                        child: Text(
                          book.name,
                          style: TextStyle(
                            fontFamily: AppTheme.serifFontName,
                            fontVariations: const [FontVariation.weight(600)],
                            fontWeight: FontWeight.w600,
                            fontSize: 24,
                            height: 1.2,
                            color: AppTheme.ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (book.completed) ...[
                            const _GoldPill(label: 'Uit'),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              status,
                              style: AppTheme.caption.copyWith(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: ShelfBar(value: share, color: color, height: 7)),
                const SizedBox(width: 10),
                Text(
                  '${book.percent}%',
                  style: AppTheme.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkSoft,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (leeslint != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(width: 8, height: 16, child: CustomPaint(painter: RibbonPainter(ribbonRed))),
                  const SizedBox(width: 8),
                  Text(
                    'Je leeslint ligt bij hoofdstuk $leeslint',
                    style: AppTheme.caption.copyWith(fontSize: 13, color: AppTheme.inkSoft),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SiteButton(label: cta, height: 46, onPressed: () => onRead(next)),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(child: Text('Hoofdstukken', style: AppTheme.bodyStrong)),
                Text('Tik om te openen', style: AppTheme.caption),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                // As many 40-wide cells as fit, then stretched to the edge.
                const gap = 6.0;
                final cols = math.max(1, ((constraints.maxWidth + gap) / (40 + gap)).floor());
                final cell = (constraints.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (var n = 1; n <= book.chapters; n++)
                      _ChapterCell(
                        number: n,
                        width: cell,
                        read: book.isRead(n),
                        next: n == leeslint,
                        color: color,
                        nextColor: palette.chapterNext,
                        onTap: () => onRead(n),
                        bookName: book.name,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _GoldPill extends StatelessWidget {
  const _GoldPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFB98A2E), Color(0xFFF5D98B), Color(0xFFC49533)]),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
        child: Text(
          label,
          style: AppTheme.caption.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF5B4314),
          ),
        ),
      ),
    );
  }
}

class _ChapterCell extends StatelessWidget {
  const _ChapterCell({
    required this.number,
    required this.width,
    required this.read,
    required this.next,
    required this.color,
    required this.nextColor,
    required this.onTap,
    required this.bookName,
  });

  final int number;
  final double width;
  final bool read;
  final bool next;
  final Color color;
  final Color nextColor;
  final VoidCallback onTap;
  final String bookName;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final bg = read ? color : AppTheme.paperSunken;
    final fg = read ? inkOn(color) : (next ? nextColor : AppTheme.inkMuted);
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '$bookName $number, ${read ? 'gelezen' : 'nog niet gelezen'}'
          '${next ? ', hier ligt je leeslint' : ''}',
      onTap: onTap,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: next ? BorderSide(color: nextColor, width: 1.6) : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: width,
            height: 36,
            child: Center(
              child: Text(
                '$number',
                style: AppTheme.caption.copyWith(
                  fontSize: 13,
                  fontWeight: read || next ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
