import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/data/bible_books.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/bible_progress.dart';
import '../domain/bookcase.dart';
import 'bible_book_groups.dart';

/// "Je boekenkast": the 66 books as spines on three shelves of a deep-teal
/// case, a library ladder leaning on it as the overall progress bar.
///
/// Drawn entirely in code. Geometry lives in a fixed 370 x 436 design space
/// (the approved mockup's own) and is scaled to the width on hand, so the case
/// looks the same on every phone. `components/profile/Bookcase.tsx` on the
/// website draws the same case from the same numbers.

/// One colour per book group, in the order of [BibleBookGroup.all]: gold for
/// de Wet, brick for Geschiedenis, rose for Poëzie, indigo for de Profeten,
/// sky for the Evangeliën and leaf green for the Brieven.
const List<Color> shelfGroupColors = [
  Color(0xFFE0A43A),
  Color(0xFFC8553D),
  Color(0xFFD9779B),
  Color(0xFF6C7FD8),
  Color(0xFF3FA7D6),
  Color(0xFF7FB069),
];

/// The red of the reading ribbon (leeslint).
const Color ribbonRed = Color(0xFFDC2626);
const Color ribbonRedDark = Color(0xFFB91C1C);

/// The brass of plaques, bands and the milestone bars.
const Color brass = Color(0xFFD4A84B);

/// Index into [BibleBookGroup.all] for every book.
final Map<String, int> bookGroupIndex = () {
  final out = <String, int>{};
  for (var g = 0; g < BibleBookGroup.all.length; g++) {
    for (final name in BibleBookGroup.all[g].books) {
      out[name] = g;
    }
  }
  return out;
}();

/// The group colour for [book].
Color shelfColorFor(String book) => shelfGroupColors[bookGroupIndex[book] ?? 0];

/// [c] lightened (positive [amount]) or darkened, per channel, out of 255.
Color shadeColor(Color c, int amount) {
  int ch(double v) => ((v * 255).round() + amount).clamp(0, 255);
  return Color.fromARGB(255, ch(c.r), ch(c.g), ch(c.b));
}

/// Text that reads on [background]: near-black on light fills, white on dark.
Color inkOn(Color background) =>
    background.computeLuminance() > 0.18 ? const Color(0xFF1F1A10) : Colors.white;

/// Colours of the room and the case, per brightness.
class BookcasePalette {
  const BookcasePalette._({
    required this.wallTop,
    required this.wallBottom,
    required this.wallLine,
    required this.floorTop,
    required this.floorBottom,
    required this.floorEdge,
    required this.caseLeft,
    required this.caseMid,
    required this.caseRight,
    required this.cornice,
    required this.corniceShadow,
    required this.post,
    required this.backTop,
    required this.backBottom,
    required this.plank,
    required this.board,
    required this.boardEdge,
    required this.ghostFill,
    required this.ghostStroke,
    required this.ghostText,
    required this.pillFill,
    required this.pillStroke,
    required this.pillText,
    required this.markerRing,
    required this.shadow,
    required this.potBody,
    required this.potRim,
    required this.chapterEmpty,
    required this.chapterNext,
  });

  final Color wallTop;
  final Color wallBottom;
  final Color wallLine;
  final Color floorTop;
  final Color floorBottom;
  final Color floorEdge;
  final Color caseLeft;
  final Color caseMid;
  final Color caseRight;
  final Color cornice;
  final Color corniceShadow;
  final Color post;
  final Color backTop;
  final Color backBottom;
  final Color plank;
  final Color board;
  final Color boardEdge;
  final Color ghostFill;
  final Color ghostStroke;
  final Color ghostText;
  final Color pillFill;
  final Color pillStroke;
  final Color pillText;
  final Color markerRing;
  final Color shadow;
  final Color potBody;
  final Color potRim;

  /// An unread chapter in the leeslint card's strip.
  final Color chapterEmpty;

  /// The chapter the leeslint lies at.
  final Color chapterNext;

  static const light = BookcasePalette._(
    wallTop: Color(0xFFEEF3F6),
    wallBottom: Color(0xFFE4EBF0),
    wallLine: Color(0x060F172A),
    floorTop: Color(0xFFD7DFE6),
    floorBottom: Color(0xFFCDD6DE),
    floorEdge: Color(0xFFC3CDD6),
    caseLeft: Color(0xFF15524D),
    caseMid: Color(0xFF1A5F59),
    caseRight: Color(0xFF124A45),
    cornice: Color(0xFF1E6B64),
    corniceShadow: Color(0xFF0E403C),
    post: Color(0xFF17574F),
    backTop: Color(0xFF0A2F2D),
    backBottom: Color(0xFF0E3B38),
    plank: Color(0x24000000),
    board: Color(0xFF1F6E67),
    boardEdge: Color(0xFF2E857D),
    ghostFill: Color(0x13FFFFFF),
    ghostStroke: Color(0x3DFFFFFF),
    ghostText: Color(0x57FFFFFF),
    pillFill: Color(0xFFF8FAFC),
    pillStroke: Color(0xFFCBD5E1),
    pillText: Color(0xFF64748B),
    markerRing: Colors.white,
    shadow: Color(0x470F172A),
    potBody: Color(0xFFCBD5E1),
    potRim: Color(0xFF94A3B8),
    chapterEmpty: Color(0xFFE8EDF2),
    chapterNext: Color(0xFFC2410C),
  );

  static const dark = BookcasePalette._(
    wallTop: Color(0xFF1D2222),
    wallBottom: Color(0xFF191D1D),
    wallLine: Color(0x07FFFFFF),
    floorTop: Color(0xFF272C2C),
    floorBottom: Color(0xFF222727),
    floorEdge: Color(0xFF313838),
    caseLeft: Color(0xFF104541),
    caseMid: Color(0xFF14524C),
    caseRight: Color(0xFF0E3F3B),
    cornice: Color(0xFF186059),
    corniceShadow: Color(0xFF0A312E),
    post: Color(0xFF134A44),
    backTop: Color(0xFF061B1A),
    backBottom: Color(0xFF092624),
    plank: Color(0x2E000000),
    board: Color(0xFF1B625B),
    boardEdge: Color(0xFF287A72),
    ghostFill: Color(0x10FFFFFF),
    ghostStroke: Color(0x33FFFFFF),
    ghostText: Color(0x4DFFFFFF),
    pillFill: Color(0xFF262626),
    pillStroke: Color(0xFF454545),
    pillText: Color(0xFFB0B0B0),
    markerRing: Color(0xFFE5E5E5),
    shadow: Color(0x80000000),
    potBody: Color(0xFF5E6870),
    potRim: Color(0xFF48525A),
    chapterEmpty: Color(0xFF333333),
    chapterNext: Color(0xFFF97316),
  );

  static BookcasePalette get current => AppTheme.isDark ? dark : light;
}

/// One book on the shelf, in design units.
class SpineGeom {
  const SpineGeom({
    required this.book,
    required this.index,
    required this.group,
    required this.x,
    required this.width,
    required this.height,
    required this.base,
    required this.color,
    required this.label,
  });

  final BookProgress book;

  /// Canonical position, 0-65.
  final int index;

  /// Index into [BibleBookGroup.all].
  final int group;
  final double x;
  final double width;
  final double height;

  /// The shelf board the spine stands on.
  final double base;
  final Color color;
  final String label;

  double get top => base - height;
  double get centerX => x + width / 2;
}

/// The brass plate under one book group.
class PlaqueGeom {
  const PlaqueGeom({
    required this.group,
    required this.centerX,
    required this.base,
    required this.read,
    required this.total,
  });

  final int group;
  final double centerX;
  final double base;
  final int read;
  final int total;

  String get label => '${shelfPlaques[group]} ${formatShelfCount(read)}/${formatShelfCount(total)}';
}

/// Where everything sits, in the 370 x 436 design space.
class BookcaseLayout {
  BookcaseLayout._(this.spines, this.plaques, this.bookends);

  static const double width = 370;
  static const double height = 436;
  static const double inset = 22;
  static const List<double> shelfTops = [72, 186, 300];
  static const double shelfHeight = 100;
  static const double boardHeight = 14;
  static const double ladderX = 338;
  static const double ladderTop = 62;
  static const double ladderBottom = 426;

  /// The two groups on each shelf.
  static const List<List<int>> rows = [
    [0, 1],
    [2, 3],
    [4, 5],
  ];

  final List<SpineGeom> spines;
  final List<PlaqueGeom> plaques;

  /// The x of each brass bookend between the two groups on a shelf, with its
  /// shelf base.
  final List<({double x, double base})> bookends;

  static double ladderY(double fraction) =>
      ladderBottom - (ladderBottom - ladderTop) * fraction.clamp(0.0, 1.0);

  factory BookcaseLayout.of(BibleProgress progress) {
    final byName = {for (final b in progress.books) b.name: b};
    final spines = <SpineGeom>[];
    final plaques = <PlaqueGeom>[];
    final bookends = <({double x, double base})>[];
    const gapGroup = 14.0;
    const gap = 1.4;

    for (var r = 0; r < rows.length; r++) {
      final base = shelfTops[r] + shelfHeight;
      final groups = rows[r];
      final names = [for (final g in groups) ...BibleBookGroup.all[g].books];
      final raw = names.fold<double>(0, (s, n) => s + _rawWidth(BibleBooks.chaptersIn(n)));
      final avail = (width - inset) - inset - gapGroup - gap * names.length - 6;
      final k = math.min(1.25, avail / raw);
      var x = inset + 2;

      for (var gk = 0; gk < groups.length; gk++) {
        final g = groups[gk];
        final startX = x;
        var read = 0;
        var total = 0;
        for (final name in BibleBookGroup.all[g].books) {
          final chapters = BibleBooks.chaptersIn(name);
          final i = canonIndex[name] ?? 0;
          final book = byName[name] ??
              BookProgress(
                name: name,
                isNewTestament: BibleBooks.newTestament.contains(name),
                chapters: chapters,
                readChapters: const [],
              );
          final w = math.max(6.0, _rawWidth(chapters) * k);
          final h = (62 + shelfJitter(i, 1) * 16 + math.min(10.0, chapters / 10)).roundToDouble();
          spines.add(
            SpineGeom(
              book: book,
              index: i,
              group: g,
              x: x,
              width: w,
              height: h,
              base: base,
              color: shadeColor(shelfGroupColors[g], ((shelfJitter(i, 2) - 0.5) * 36).round()),
              label: spineLabels[name] ?? name,
            ),
          );
          read += book.readCount;
          total += book.chapters;
          x += w + gap;
        }
        plaques.add(PlaqueGeom(group: g, centerX: (startX + x) / 2, base: base, read: read, total: total));
        if (gk == 0) {
          bookends.add((x: x, base: base));
          x += gapGroup;
        }
      }
    }
    return BookcaseLayout._(spines, plaques, bookends);
  }

  static double _rawWidth(int chapters) => 5 + math.sqrt(chapters) * 2.15;
}

/// Timing of the opening reveal, shared by the painter and the hit targets.
abstract final class BookcaseMotion {
  /// When the spine at canonical [index] starts filling, as a share of the
  /// intro: one wave from Genesis to Openbaring.
  static double spineStart(int index) => 0.06 + 0.42 * index / 65;

  /// How much of the intro one spine takes to fill.
  static const double spineSpan = 0.3;

  /// 0-1 fill of the spine at [index] at [intro].
  static double spineFill(double intro, int index) =>
      Curves.easeOutCubic.transform(((intro - spineStart(index)) / spineSpan).clamp(0.0, 1.0));

  /// 0-1 of the gold lettering on a finished spine.
  static double gold(double intro, int index) =>
      ((intro - spineStart(index) - spineSpan) / 0.12).clamp(0.0, 1.0);

  /// The ladder marker's share of its climb.
  static double ladder(double intro) =>
      Curves.easeOutCubic.transform(const Interval(0.15, 0.8).transform(intro.clamp(0.0, 1.0)));
}

/// The case as a widget: the painting, plus one invisible, labelled tap target
/// per spine so a screen reader can walk the shelves book by book.
class Bookcase extends StatelessWidget {
  const Bookcase({
    super.key,
    required this.layout,
    required this.fraction,
    required this.markerLabel,
    required this.intro,
    required this.onTapBook,
    this.current,
    this.celebrating = const {},
    this.celebrate = 0,
    this.pulled,
    this.pull = 0,
  });

  final BookcaseLayout layout;

  /// 0-1 share of all chapters read.
  final double fraction;

  /// What the ladder marker prints, "11%".
  final String markerLabel;
  final double intro;
  final void Function(BookProgress book) onTapBook;

  /// The book the leeslint lies in.
  final String? current;
  final Set<String> celebrating;
  final double celebrate;
  final String? pulled;
  final double pull;

  static const double maxWidth = 560;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, maxWidth);
        final s = width / BookcaseLayout.width;
        return SizedBox(
          width: width,
          height: BookcaseLayout.height * s,
          child: Stack(
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  child: CustomPaint(
                    painter: BookcasePainter(
                      layout: layout,
                      palette: BookcasePalette.current,
                      fraction: fraction,
                      markerLabel: markerLabel,
                      intro: intro,
                      current: current,
                      celebrating: celebrating,
                      celebrate: celebrate,
                      pulled: pulled,
                      pull: pull,
                    ),
                  ),
                ),
              ),
              for (final spine in layout.spines)
                Positioned(
                  left: (spine.x - 0.7) * s,
                  top: (spine.base - BookcaseLayout.shelfHeight) * s,
                  width: (spine.width + 1.4) * s,
                  height: (BookcaseLayout.shelfHeight + BookcaseLayout.boardHeight) * s,
                  child: Semantics(
                    button: true,
                    excludeSemantics: true,
                    label: spineSemantics(spine.book, current: spine.book.name == current),
                    onTap: () => onTapBook(spine.book),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTapBook(spine.book),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// "Exodus, 9 van 40 hoofdstukken gelezen, hier ligt je leeslint".
String spineSemantics(BookProgress book, {bool current = false}) {
  final buf = StringBuffer('${book.name}, ');
  if (book.completed) {
    buf.write('uit, alle ${book.chapters} hoofdstukken gelezen');
  } else {
    buf.write('${book.readCount} van ${book.chapters} hoofdstukken gelezen');
  }
  if (current) buf.write(', hier ligt je leeslint');
  return buf.toString();
}

/// Text layouts are cached across frames: the reveal repaints the case some
/// hundred times and the labels never change while it runs.
final Map<String, TextPainter> _textCache = {};

TextPainter _label(
  String text, {
  required double size,
  required Color color,
  FontWeight weight = FontWeight.w600,
  bool serif = false,
}) {
  final key = '$text|$size|${weight.value}|${color.toARGB32()}|$serif';
  final hit = _textCache[key];
  if (hit != null) return hit;
  if (_textCache.length > 800) {
    for (final p in _textCache.values) {
      p.dispose();
    }
    _textCache.clear();
  }
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: serif ? AppTheme.serifFontName : AppTheme.sansFontName,
        fontSize: size,
        fontWeight: weight,
        fontVariations: serif ? [FontVariation.weight(weight.value.toDouble())] : null,
        color: color,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return _textCache[key] = painter;
}

/// Paints [painter] with its alphabetic baseline at [baseline].
void _paintOnBaseline(Canvas canvas, TextPainter painter, Offset baseline) {
  final ascent = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  painter.paint(canvas, baseline.translate(0, -ascent));
}

class BookcasePainter extends CustomPainter {
  BookcasePainter({
    required this.layout,
    required this.palette,
    required this.fraction,
    required this.markerLabel,
    required this.intro,
    this.current,
    this.celebrating = const {},
    this.celebrate = 0,
    this.pulled,
    this.pull = 0,
  });

  final BookcaseLayout layout;
  final BookcasePalette palette;
  final double fraction;
  final String markerLabel;
  final double intro;
  final String? current;
  final Set<String> celebrating;
  final double celebrate;
  final String? pulled;
  final double pull;

  static const _gold = [Color(0xFFB98A2E), Color(0xFFF5D98B), Color(0xFFC49533)];
  static const _goldStops = [0.0, 0.45, 1.0];

  Paint _goldPaint(Rect r) => Paint()
    ..shader = const LinearGradient(colors: _gold, stops: _goldStops).createShader(r);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / BookcaseLayout.width;
    canvas.save();
    canvas.scale(s);

    _cabinet(canvas);
    _decor(canvas);

    final over = <void Function()>[];
    for (var r = 0; r < BookcaseLayout.rows.length; r++) {
      final top = BookcaseLayout.shelfTops[r];
      final base = top + BookcaseLayout.shelfHeight;
      _backPanel(canvas, top);
      for (final spine in layout.spines.where((sp) => sp.base == base)) {
        _spine(canvas, spine, over);
      }
      for (final end in layout.bookends.where((e) => e.base == base)) {
        _bookend(canvas, end.x, end.base);
      }
      _board(canvas, base);
    }
    for (final paintOver in over) {
      paintOver();
    }
    for (final plaque in layout.plaques) {
      _plaque(canvas, plaque);
    }
    _posts(canvas);
    _ladder(canvas);
    _sparkles(canvas);

    canvas.restore();
  }

  void _cabinet(Canvas canvas) {
    const w = BookcaseLayout.width;
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(8, 52, w - 16, 370), const Radius.circular(6));
    canvas.drawRRect(
      body.shift(const Offset(0, 10)),
      Paint()
        ..color = palette.shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: [palette.caseLeft, palette.caseMid, palette.caseRight],
          stops: const [0, 0.5, 1],
        ).createShader(body.outerRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(2, 42, w - 4, 16), const Radius.circular(4)),
      Paint()..color = palette.cornice,
    );
    canvas.drawRect(const Rect.fromLTWH(2, 55, w - 4, 4), Paint()..color = palette.corniceShadow);
    canvas.drawRect(const Rect.fromLTWH(12, 410, w - 24, 10), Paint()..color = palette.corniceShadow);
  }

  /// A plant on the left of the top, a little brass lamp on the right.
  void _decor(Canvas canvas) {
    canvas.save();
    canvas.translate(36, 42);
    canvas.drawPath(
      Path()
        ..moveTo(-9, 0)
        ..relativeLineTo(18, 0)
        ..relativeLineTo(-3, -14)
        ..relativeLineTo(-12, 0)
        ..close(),
      Paint()..color = palette.potBody,
    );
    canvas.drawRect(const Rect.fromLTWH(-10, -17, 20, 3), Paint()..color = palette.potRim);
    canvas.drawPath(
      Path()
        ..moveTo(0, -17)
        ..relativeQuadraticBezierTo(-14, -6, -12, -22)
        ..relativeQuadraticBezierTo(8, 6, 12, 22),
      Paint()..color = const Color(0xFF4CA36F),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, -14)
        ..relativeQuadraticBezierTo(14, -10, 10, -26)
        ..relativeQuadraticBezierTo(-10, 8, -10, 26),
      Paint()..color = const Color(0xFF3E8E5E),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, -14)
        ..relativeQuadraticBezierTo(-2, -16, 4, -28)
        ..relativeQuadraticBezierTo(4, 14, -4, 28),
      Paint()..color = const Color(0xFF5DBB7E),
    );
    canvas.restore();

    canvas.save();
    canvas.translate(300, 42);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(-10, -4, 20, 4), const Radius.circular(2)),
      Paint()..color = const Color(0xFFA47C2C),
    );
    canvas.drawRect(const Rect.fromLTWH(-1.5, -26, 3, 22), Paint()..color = const Color(0xFFC9A24A));
    canvas.drawPath(
      Path()
        ..moveTo(-12, -26)
        ..relativeLineTo(24, 0)
        ..relativeLineTo(-5, -14)
        ..relativeLineTo(-14, 0)
        ..close(),
      Paint()..color = const Color(0xFFE9C46A),
    );
    canvas.restore();
  }

  void _backPanel(Canvas canvas, double top) {
    const x0 = BookcaseLayout.inset - 4;
    const w = BookcaseLayout.width - 2 * x0;
    const h = BookcaseLayout.shelfHeight;
    final rect = Rect.fromLTWH(x0, top, w, h);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.backTop, palette.backBottom],
        ).createShader(rect),
    );
    final plank = Paint()
      ..color = palette.plank
      ..strokeWidth = 1;
    for (var px = BookcaseLayout.inset + 18; px < BookcaseLayout.width - BookcaseLayout.inset; px += 36) {
      canvas.drawLine(Offset(px, top), Offset(px, top + h), plank);
    }
    // The lamp's warm light falling on the top of each shelf: a band that
    // fades downwards and towards both sides.
    final glow = Rect.fromLTWH(x0, top, w, 22);
    canvas.drawRect(
      glow,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x4DFDE68A), Color(0x00FDE68A)],
        ).createShader(glow),
    );
    canvas.drawRect(
      glow,
      Paint()
        ..shader = LinearGradient(
          colors: [palette.backTop.withValues(alpha: 0.5), palette.backTop.withValues(alpha: 0), palette.backTop.withValues(alpha: 0.5)],
          stops: const [0, 0.5, 1],
        ).createShader(glow),
    );
  }

  double _lift(SpineGeom spine) {
    var dy = 0.0;
    if (spine.book.name == pulled) dy -= 7 * Curves.easeOutBack.transform(pull.clamp(0.0, 1.0));
    if (celebrating.contains(spine.book.name) && celebrate > 0 && celebrate < 1) {
      dy -= 7 * math.sin(math.pi * math.min(1.0, celebrate * 1.6));
    }
    return dy;
  }

  void _spine(Canvas canvas, SpineGeom sp, List<void Function()> over) {
    final book = sp.book;
    final dy = _lift(sp);
    final x = sp.x;
    final ww = sp.width;
    final h = sp.height;
    final base = sp.base + dy;
    final y = base - h;
    final rect = Rect.fromLTWH(x, y, ww, h);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(1.6));
    final fill = BookcaseMotion.spineFill(intro, sp.index);
    final isCurrent = book.name == current;
    final labelSize = ww > 16 ? 9.5 : 8.0;

    if (isCurrent) {
      final glowIn = const Interval(0.55, 0.95).transform(intro.clamp(0.0, 1.0));
      if (glowIn > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(3)),
          Paint()
            ..color = const Color(0xFFFDE68A).withValues(alpha: 0.55 * glowIn)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
    }
    if (celebrating.contains(book.name) && celebrate > 0 && celebrate < 1) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(4), const Radius.circular(3)),
        Paint()
          ..color = const Color(0xFFF5D98B).withValues(alpha: 0.75 * math.sin(math.pi * celebrate))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }

    final gold = book.completed ? BookcaseMotion.gold(intro, sp.index) : 0.0;
    if (book.completed && gold > 0) {
      // A finished book: full colour, gold bands and gold lettering.
      canvas.drawRRect(rrect, Paint()..color = sp.color);
      // The bands fade in once the colour has risen to the top.
      if (gold < 1) {
        canvas.saveLayer(rect.inflate(1), Paint()..color = Color.fromRGBO(0, 0, 0, gold));
      } else {
        canvas.save();
      }
      for (final band in [
        Rect.fromLTWH(x + 0.6, y + 6, ww - 1.2, 2.4),
        Rect.fromLTWH(x + 0.6, y + 10, ww - 1.2, 1),
        Rect.fromLTWH(x + 0.6, base - 9, ww - 1.2, 2.4),
      ]) {
        canvas.drawRect(band, _goldPaint(band));
      }
      canvas.drawCircle(Offset(x + ww / 2, y + 18), 1.6, Paint()..color = const Color(0xFFF5D98B));
      canvas.restore();
      if (ww >= 11) {
        _spineLabel(
          canvas,
          sp,
          Offset(x + ww / 2 + 3.2, base - 14),
          const Color(0xFFFBE7A9),
          labelSize,
          maxLength: h - 30,
        );
      }
      canvas.drawRect(
        Rect.fromLTWH(x, y, math.max(1.5, ww * 0.22), h),
        Paint()..color = Colors.white.withValues(alpha: 0.14),
      );
    } else {
      // Not finished (or still filling): a ghost spine with colour rising
      // from the bottom as chapters are read.
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(1.6)),
        Paint()..color = palette.ghostFill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(1.6)),
        Paint()
          ..color = palette.ghostStroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final share = book.completed ? 1.0 : book.readCount / math.max(1, book.chapters);
      if (book.started && fill > 0) {
        final fh = math.max(4.0, h * share) * fill;
        final wy = base - fh + 1.5;
        // The surface wobbles while it rises and settles into a soft wave.
        final amp = 3 + 2.5 * math.sin(fill * math.pi * 2) * (1 - fill);
        canvas.save();
        canvas.clipRRect(rrect);
        canvas.drawPath(
          Path()
            ..moveTo(x, wy)
            ..quadraticBezierTo(x + ww / 4, wy - amp, x + ww / 2, wy)
            ..quadraticBezierTo(x + ww * 3 / 4, wy + amp, x + ww, wy)
            ..lineTo(x + ww, base)
            ..lineTo(x, base)
            ..close(),
          Paint()..color = sp.color,
        );
        canvas.drawRect(
          Rect.fromLTWH(x, base - fh, math.max(1.5, ww * 0.22), fh),
          Paint()..color = Colors.white.withValues(alpha: 0.14),
        );
        canvas.restore();
      }
      if (book.started && fill > 0 && ww >= 11) {
        _spineLabel(
          canvas,
          sp,
          Offset(x + ww / 2 + 3.2, base - 6),
          Color.lerp(palette.ghostText, Colors.white.withValues(alpha: 0.9), (fill * 4).clamp(0.0, 1.0))!,
          labelSize,
          maxLength: h - 10,
        );
      } else if (ww >= 12) {
        _spineLabel(
          canvas,
          sp,
          Offset(x + ww / 2 + 3, base - 6),
          palette.ghostText,
          ww > 16 ? 9 : 7.6,
          weight: FontWeight.w500,
          maxLength: h - 10,
        );
      }
    }

    if (book.name == pulled && pull > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(1.6)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.7 * pull)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    if (isCurrent) {
      final ribbonIn = const Interval(0.6, 1).transform(intro.clamp(0.0, 1.0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(1.6)),
        Paint()
          ..color = const Color(0xFFFDE68A).withValues(alpha: math.max(0.35, ribbonIn))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      // The leeslint hangs out of the book you are in, over the shelf board.
      over.add(() {
        final rx = x + ww - 6;
        final drop = 30 * Curves.easeOutBack.transform(ribbonIn);
        if (drop <= 0.5) return;
        final top = base - 8;
        canvas.drawPath(
          Path()
            ..moveTo(rx, top)
            ..lineTo(rx, top + drop)
            ..lineTo(rx - 3, top + drop - 4)
            ..lineTo(rx - 6, top + drop)
            ..lineTo(rx - 6, top)
            ..close(),
          Paint()..color = ribbonRed,
        );
        canvas.drawPath(
          Path()
            ..moveTo(rx, top)
            ..lineTo(rx, top + drop)
            ..lineTo(rx - 3, top + drop - 4)
            ..lineTo(rx - 3, top)
            ..close(),
          Paint()..color = ribbonRedDark,
        );
      });
    }
  }

  /// A spine title running bottom to top, its baseline on [at].
  void _spineLabel(
    Canvas canvas,
    SpineGeom sp,
    Offset at,
    Color color,
    double size, {
    FontWeight weight = FontWeight.w600,
    required double maxLength,
  }) {
    var painter = _label(sp.label, size: size, color: color, weight: weight, serif: true);
    if (painter.width > maxLength) {
      painter = _label(sp.label, size: size * maxLength / painter.width, color: color, weight: weight, serif: true);
    }
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(-math.pi / 2);
    _paintOnBaseline(canvas, painter, Offset.zero);
    canvas.restore();
  }

  void _bookend(Canvas canvas, double x, double base) {
    canvas.drawPath(
      Path()
        ..moveTo(x + 2, base)
        ..lineTo(x + 2, base - 30)
        ..quadraticBezierTo(x + 2, base - 36, x + 8, base - 36)
        ..lineTo(x + 8, base)
        ..close(),
      Paint()..color = const Color(0xFFC9A24A),
    );
    canvas.drawRect(Rect.fromLTWH(x + 2, base - 2, 10, 2), Paint()..color = const Color(0xFFA47C2C));
  }

  void _board(Canvas canvas, double base) {
    const x0 = BookcaseLayout.inset - 6;
    const w = BookcaseLayout.width - 2 * x0;
    canvas.drawRect(Rect.fromLTWH(x0, base, w, BookcaseLayout.boardHeight), Paint()..color = palette.board);
    canvas.drawRect(Rect.fromLTWH(x0, base, w, 2.5), Paint()..color = palette.boardEdge);
  }

  void _plaque(Canvas canvas, PlaqueGeom plaque) {
    final text = _label(plaque.label, size: 7.6, color: const Color(0xFF5B4314), weight: FontWeight.w700);
    final w = text.width + 14;
    final rect = Rect.fromCenter(center: Offset(plaque.centerX, plaque.base + 7.5), width: w, height: 11);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2.5)), _goldPaint(rect));
    _paintOnBaseline(canvas, text, Offset(plaque.centerX - text.width / 2, plaque.base + 10.1));
  }

  void _posts(Canvas canvas) {
    const w = BookcaseLayout.inset - 12;
    final paint = Paint()..color = palette.post;
    canvas.drawRect(const Rect.fromLTWH(8, 59, w, 355), paint);
    canvas.drawRect(const Rect.fromLTWH(BookcaseLayout.width - BookcaseLayout.inset + 4, 59, w, 355), paint);
  }

  /// The library ladder: rails, rungs, the four milestone tags and the
  /// reader's own marker, which climbs to the share read during the intro.
  void _ladder(Canvas canvas) {
    const lx = BookcaseLayout.ladderX;
    const top = BookcaseLayout.ladderTop;
    const bot = BookcaseLayout.ladderBottom;

    final rail = Paint()
      ..color = const Color(0xFF7A4E2A)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final shine = Paint()
      ..color = const Color(0xFFA9744A)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(lx - 16, top - 6), const Offset(lx - 6, bot), rail);
    canvas.drawLine(const Offset(lx + 10, top - 6), const Offset(lx + 20, bot), rail);
    canvas.drawLine(const Offset(lx - 17.2, top - 6), const Offset(lx - 7.2, bot), shine);
    canvas.drawLine(const Offset(lx + 8.8, top - 6), const Offset(lx + 18.8, bot), shine);
    final foot = Paint()..color = const Color(0xFF3F2A17);
    canvas.drawCircle(const Offset(lx - 6, bot + 2), 3.5, foot);
    canvas.drawCircle(const Offset(lx + 20, bot + 2), 3.5, foot);

    final rung = Paint()
      ..color = const Color(0xFF8B5A33)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < 12; i++) {
      final y = BookcaseLayout.ladderY(i / 12);
      final xl = lx - 16 + ((y - (top - 6)) / (bot - top + 6)) * 10;
      canvas.drawLine(Offset(xl, y), Offset(xl + 26, y), rung);
    }

    const tags = [(0.25, '25%'), (0.5, '50%'), (0.75, '75%'), (1.0, 'Alles')];
    for (final (m, label) in tags) {
      final y = BookcaseLayout.ladderY(m) + (m == 1 ? 10 : 0);
      final pill = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(lx + 2, y), width: 34, height: 16),
        const Radius.circular(8),
      );
      canvas.drawRRect(pill, Paint()..color = palette.pillFill);
      canvas.drawRRect(
        pill,
        Paint()
          ..color = palette.pillStroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final text = _label(label, size: 9, color: palette.pillText, weight: FontWeight.w700);
      _paintOnBaseline(canvas, text, Offset(lx + 2 - text.width / 2, y + 3.4));
    }

    final climbed = fraction * BookcaseMotion.ladder(intro);
    // Never lower than just above the feet, so a fresh reader's 0% still
    // shows over the floor.
    final center = Offset(lx + 4, math.min(BookcaseLayout.ladderY(climbed), bot - 20));
    canvas.drawCircle(
      center,
      15,
      Paint()
        ..color = const Color(0x80FDE68A)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(center, 11.5, Paint()..color = AppTheme.lightTeal);
    canvas.drawCircle(
      center,
      11.5,
      Paint()
        ..color = palette.markerRing
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    var text = _label(markerLabel, size: 10, color: Colors.white, weight: FontWeight.w700);
    if (text.width > 19) {
      text = _label(markerLabel, size: math.max(6.5, 10 * 19 / text.width), color: Colors.white, weight: FontWeight.w700);
    }
    _paintOnBaseline(canvas, text, Offset(center.dx - text.width / 2, center.dy + text.height * 0.36));
  }

  /// Gold sparks flying off a book that was finished since the last visit.
  void _sparkles(Canvas canvas) {
    if (celebrating.isEmpty || celebrate <= 0 || celebrate >= 1) return;
    final t = Curves.easeOutCubic.transform(celebrate);
    final fade = 1 - Curves.easeIn.transform(celebrate);
    for (final sp in layout.spines) {
      if (!celebrating.contains(sp.book.name)) continue;
      final origin = Offset(sp.centerX, sp.top + _lift(sp) + 6);
      for (var j = 0; j < 10; j++) {
        final angle = -math.pi / 2 + (j / 9 - 0.5) * math.pi * 1.1;
        final dist = 6 + (22 + 10 * shelfJitter(sp.index * 10 + j, 7)) * t;
        final p = origin + Offset(math.cos(angle) * dist, math.sin(angle) * dist);
        final r = 1 + 2.4 * fade;
        final color = (j.isEven ? const Color(0xFFF5D98B) : Colors.white).withValues(alpha: fade);
        canvas.drawPath(_star(p, r), Paint()..color = color);
      }
    }
  }

  Path _star(Offset c, double r) {
    final q = r * 0.32;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + q, c.dy - q)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx + q, c.dy + q)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - q, c.dy + q)
      ..lineTo(c.dx - r, c.dy)
      ..lineTo(c.dx - q, c.dy - q)
      ..close();
  }

  @override
  bool shouldRepaint(BookcasePainter old) =>
      !identical(old.layout, layout) ||
      old.palette != palette ||
      old.fraction != fraction ||
      old.markerLabel != markerLabel ||
      old.intro != intro ||
      old.current != current ||
      old.celebrate != celebrate ||
      old.celebrating != celebrating ||
      old.pulled != pulled ||
      old.pull != pull;
}

/// The room behind the case: a softly striped wall and a floor strip of
/// [floorHeight] at the bottom.
class BookcaseRoomPainter extends CustomPainter {
  BookcaseRoomPainter({required this.palette, required this.floorHeight});

  final BookcasePalette palette;
  final double floorHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final wall = Offset.zero & size;
    canvas.drawRect(
      wall,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.wallTop, palette.wallBottom],
        ).createShader(wall),
    );
    final line = Paint()..color = palette.wallLine;
    for (var x = 22.0; x < size.width; x += 23) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), line);
    }
    final floor = Rect.fromLTWH(0, size.height - floorHeight, size.width, floorHeight);
    canvas.drawRect(
      floor,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.floorTop, palette.floorBottom],
        ).createShader(floor),
    );
    canvas.drawRect(Rect.fromLTWH(0, floor.top, size.width, 3), Paint()..color = palette.floorEdge);
  }

  @override
  bool shouldRepaint(BookcaseRoomPainter old) =>
      old.palette != palette || old.floorHeight != floorHeight;
}

/// The bookcase in miniature, for the "Je Bijbel" card on Start: the same
/// three shelves and group colours, each spine filling from the bottom.
/// [intro] runs the same Genesis-to-Openbaring wave as the big case.
class MiniBookcasePainter extends CustomPainter {
  MiniBookcasePainter({required this.books, required this.intro, required this.palette});

  static const size = Size(132, 72);

  final List<BookProgress> books;
  final double intro;
  final BookcasePalette palette;

  @override
  void paint(Canvas canvas, Size _) {
    final byName = {for (final b in books) b.name: b};
    final frame = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
    canvas.drawRRect(
      frame,
      Paint()
        ..shader = LinearGradient(
          colors: [palette.caseLeft, palette.caseMid, palette.caseRight],
        ).createShader(frame.outerRect),
    );
    const inner = 5.0;
    const shelfH = 19.0;
    const tops = [5.0, 27.0, 49.0];
    final ghost = Paint()..color = palette.ghostFill;
    final ghostLine = Paint()
      ..color = palette.ghostStroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    for (var r = 0; r < 3; r++) {
      final top = tops[r];
      final base = top + shelfH;
      canvas.drawRect(
        Rect.fromLTWH(inner - 1, top, size.width - 2 * (inner - 1), shelfH),
        Paint()..color = palette.backBottom,
      );
      final names = [for (final g in BookcaseLayout.rows[r]) ...BibleBookGroup.all[g].books];
      final raw = names.fold<double>(0, (s, n) => s + math.sqrt(BibleBooks.chaptersIn(n)) + 1.2);
      const gap = 0.7;
      final k = (size.width - 2 * inner - gap * names.length) / raw;
      var x = inner;
      for (final name in names) {
        final i = canonIndex[name] ?? 0;
        final g = bookGroupIndex[name] ?? 0;
        final chapters = BibleBooks.chaptersIn(name);
        final w = (math.sqrt(chapters) + 1.2) * k;
        final h = 12 + shelfJitter(i, 1) * 4 + math.min(2.0, chapters / 25);
        final rect = Rect.fromLTWH(x, base - h, w, h);
        final book = byName[name];
        final share = book == null ? 0.0 : book.readCount / math.max(1, book.chapters);
        canvas.drawRect(rect, ghost);
        if (w > 1.6) canvas.drawRect(rect.deflate(0.3), ghostLine);
        if (share > 0) {
          final t = BookcaseMotion.spineFill(intro, i);
          final fh = math.max(1.5, h * share) * t;
          if (fh > 0.2) {
            final color = shadeColor(shelfGroupColors[g], ((shelfJitter(i, 2) - 0.5) * 36).round());
            canvas.drawRect(Rect.fromLTWH(x, base - fh, w, fh), Paint()..color = color);
            if (book!.completed && t >= 1) {
              canvas.drawRect(
                Rect.fromLTWH(x, base - h + 2, w, 1),
                Paint()..color = const Color(0xFFF5D98B),
              );
            }
          }
        }
        x += w + gap;
      }
      canvas.drawRect(
        Rect.fromLTWH(inner - 2, base, size.width - 2 * (inner - 2), 2),
        Paint()..color = palette.boardEdge,
      );
    }
  }

  @override
  bool shouldRepaint(MiniBookcasePainter old) =>
      old.intro != intro || !identical(old.books, books) || old.palette != palette;
}
