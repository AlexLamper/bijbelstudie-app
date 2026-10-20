import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../auth/present/auth_controller.dart';
import '../../profile/domain/bible_progress.dart';
import '../data/bible_progress_seen_store.dart';
import '../domain/bible_milestones.dart';

/// "Je Bijbel" on Start, under the tekst van de dag: the share of all 1189
/// chapters read, a 66-square map of the books, a milestone bar and what is
/// left to the next milestone. Built from the `readChapters` map `/dashboard`
/// already returns; a tap opens the full list at `/profile/bijbel`.
///
/// The first time it shows in a session the number counts up, the squares fill
/// in reading order and the bar grows, all in about 1.4 s. A milestone crossed
/// since the card last showed (remembered per account on the device) makes its
/// tick glow and turns the footer into a short celebration.
class BibleProgressCard extends ConsumerStatefulWidget {
  const BibleProgressCard({super.key, required this.readChapters});

  final Map<String, List<int>> readChapters;

  @override
  ConsumerState<BibleProgressCard> createState() => _BibleProgressCardState();
}

class _BibleProgressCardState extends ConsumerState<BibleProgressCard>
    with TickerProviderStateMixin {
  /// The intro plays once per app session, not every time Start rebuilds.
  static bool _introPlayed = false;

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late BibleProgress _progress = BibleProgress.fromReadChapters(widget.readChapters);
  BibleMilestone? _celebrating;

  @override
  void initState() {
    super.initState();
    final playIntro = !_introPlayed;
    _introPlayed = true;
    if (!playIntro) _intro.value = 1;
    unawaited(_sync(playIntro: playIntro));
  }

  @override
  void didUpdateWidget(BibleProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.readChapters, widget.readChapters)) return;
    final before = _progress.percent;
    _progress = BibleProgress.fromReadChapters(widget.readChapters);
    if (_progress.percent != before) unawaited(_sync(playIntro: false));
  }

  @override
  void dispose() {
    _intro.dispose();
    _glow.dispose();
    super.dispose();
  }

  /// Compares the shown share with the last one seen, remembers the new one
  /// and starts whatever animation is due.
  Future<void> _sync({required bool playIntro}) async {
    final userId = ref.read(authControllerProvider).value?.id;
    final now = _progress.percent;
    final lastSeen = await BibleProgressSeenStore.read(userId);
    if (!mounted) return;
    if (lastSeen != now) unawaited(BibleProgressSeenStore.write(userId, now));

    final crossed = crossedBibleMilestone(lastSeen: lastSeen, now: now);
    if (crossed != null) setState(() => _celebrating = crossed);

    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      return;
    }
    void glow() {
      if (mounted && crossed != null) _glow.forward(from: 0);
    }

    if (playIntro) {
      _intro.forward(from: 0).whenCompleteOrCancel(glow);
    } else {
      glow();
    }
  }

  void _open() => context.push('/profile/bijbel');

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final p = _progress;
    final footer = _celebrating?.celebration ??
        bibleMilestoneFooter(p.chaptersRead, p.chaptersTotal);
    final inProgress = p.booksStarted - p.booksCompleted;

    return Semantics(
      button: true,
      label: 'Je Bijbel, ${formatBiblePercent(p.percent)} van alle hoofdstukken gelezen. '
          '${p.booksCompleted} van ${p.booksTotal} boeken gelezen'
          '${inProgress > 0 ? ', $inProgress bezig' : ''}. $footer',
      onTap: _open,
      excludeSemantics: true,
      child: AppCard(
        padding: EdgeInsets.zero,
        clip: true,
        onTap: _open,
        child: AnimatedBuilder(
          animation: Listenable.merge([_intro, _glow]),
          builder: (context, _) => _content(context, scheme.surface, footer),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, Color surface, String footer) {
    final p = _progress;
    final v = _intro.value;
    final count = p.percent * Curves.easeOutCubic.transform(const Interval(0, 0.6).transform(v));
    final shown = v >= 1 ? p.percent : count;
    final percentText = shown < 0.1 && shown < p.percent ? '0%' : formatBiblePercent(shown);
    final footerIn = Curves.easeOut.transform(const Interval(0.72, 1).transform(v));
    final celebrating = _celebrating != null;
    final textScaler = MediaQuery.textScalerOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Je Bijbel',
                          style: AppTheme.caption.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          percentText,
                          style: AppTheme.statNumber.copyWith(
                            fontSize: 32,
                            height: 1.1,
                            letterSpacing: -0.5,
                            color: AppTheme.teal,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${p.booksCompleted} van ${p.booksTotal} boeken gelezen',
                          style: AppTheme.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: CustomPaint(
                      size: _BookGridPainter.size,
                      painter: _BookGridPainter(
                        books: p.books,
                        intro: v,
                        done: AppTheme.teal,
                        partial: AppTheme.teal.withValues(alpha: 0.35),
                        empty: AppTheme.paperSunkenStrong,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: _MilestoneBarPainter.heightFor(textScaler),
                child: CustomPaint(
                  painter: _MilestoneBarPainter(
                    fraction: p.percent / 100,
                    intro: v,
                    glow: _glow.value,
                    glowAt: _celebrating?.fraction,
                    track: AppTheme.paperSunkenStrong,
                    fill: AppTheme.teal,
                    cut: surface,
                    tickIdle: AppTheme.inkFaint.withValues(alpha: 0.45),
                    labelColor: AppTheme.inkFaint,
                    textScaler: textScaler,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          color: AppTheme.tealTint,
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Opacity(
            opacity: footerIn,
            child: Transform.translate(
              offset: Offset(0, 6 * (1 - footerIn)),
              child: Row(
                children: [
                  Icon(
                    celebrating ? Icons.flag : Icons.flag_outlined,
                    size: 16,
                    color: AppTheme.teal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      footer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(
                        fontSize: 13,
                        fontWeight: celebrating ? FontWeight.w700 : FontWeight.w600,
                        color: celebrating ? AppTheme.teal : AppTheme.inkSoft,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 20, color: AppTheme.inkFaint),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 11 x 6 squares, one per book in canonical order: teal when finished, light
/// teal when started, grey when not. During the intro each started square pops
/// into its colour in turn, a quick wave from Genesis to Openbaring.
class _BookGridPainter extends CustomPainter {
  _BookGridPainter({
    required this.books,
    required this.intro,
    required this.done,
    required this.partial,
    required this.empty,
  });

  static const _cols = 11;
  static const _rows = 6;
  static const _cell = 9.0;
  static const _gap = 3.0;
  static const size = Size(
    _cols * _cell + (_cols - 1) * _gap,
    _rows * _cell + (_rows - 1) * _gap,
  );

  /// Where in the intro the wave starts and ends, and how long one square takes.
  static const _waveStart = 0.08;
  static const _waveSpan = 0.45;
  static const _pop = 0.14;

  final List<BookProgress> books;
  final double intro;
  final Color done;
  final Color partial;
  final Color empty;

  @override
  void paint(Canvas canvas, Size _) {
    final n = math.min(books.length, _cols * _rows);
    for (var i = 0; i < n; i++) {
      final book = books[i];
      final center = Offset(
        (i % _cols) * (_cell + _gap) + _cell / 2,
        (i ~/ _cols) * (_cell + _gap) + _cell / 2,
      );
      var color = empty;
      var scale = 1.0;
      if (book.started) {
        final start = _waveStart + _waveSpan * i / math.max(1, n - 1);
        final t = ((intro - start) / _pop).clamp(0.0, 1.0);
        color = Color.lerp(empty, book.completed ? done : partial, Curves.easeOut.transform(t))!;
        scale = 1 + 0.28 * math.sin(math.pi * t);
      }
      final side = _cell * scale;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: side, height: side),
          Radius.circular(2.5 * scale),
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_BookGridPainter old) =>
      old.intro != intro ||
      !identical(old.books, books) ||
      old.done != done ||
      old.partial != partial ||
      old.empty != empty;
}

/// The bar with ticks at 25, 50 and 75% and labels under it. A tick the fill
/// has passed is cut into the fill in the card colour; while the fill grows
/// past a tick, the tick pulses once. [glowAt] marks a milestone just reached.
class _MilestoneBarPainter extends CustomPainter {
  _MilestoneBarPainter({
    required this.fraction,
    required this.intro,
    required this.glow,
    required this.glowAt,
    required this.track,
    required this.fill,
    required this.cut,
    required this.tickIdle,
    required this.labelColor,
    required this.textScaler,
  });

  static const _barHeight = 8.0;
  static const _labelGap = 6.0;
  static const _labelSize = 10.0;
  static const _ticks = [0.25, 0.5, 0.75];
  static const _fillInterval = Interval(0.15, 0.75, curve: Curves.easeOutCubic);
  static const _pulse = 0.14;

  static double heightFor(TextScaler scaler) =>
      _barHeight + _labelGap + scaler.scale(_labelSize) * 1.3 + 1;

  final double fraction;
  final double intro;
  final double glow;
  final double? glowAt;
  final Color track;
  final Color fill;
  final Color cut;
  final Color tickIdle;
  final Color labelColor;
  final TextScaler textScaler;

  double _fillAt(double t) => fraction * _fillInterval.transform(t.clamp(0.0, 1.0));

  /// The intro value at which the growing fill reaches [x].
  double _crossingTime(double x) {
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      if (_fillAt(mid) < x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return hi;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cy = _barHeight / 2;
    final shown = _fillAt(intro);
    final halo = Paint();

    // Halos sit behind the bar so only their soft edge shows around it.
    for (final x in _ticks) {
      if (fraction < x || intro >= 1) continue;
      final t = (intro - _crossingTime(x)) / _pulse;
      if (t <= 0 || t >= 1) continue;
      final a = math.sin(math.pi * t);
      halo.color = fill.withValues(alpha: 0.22 * a);
      canvas.drawCircle(Offset(w * x, cy), 4 + 4 * a, halo);
    }
    final at = glowAt;
    if (at != null && glow > 0 && glow < 1) {
      final a = math.sin(math.pi * glow);
      halo.color = fill.withValues(alpha: 0.32 * a);
      canvas.drawCircle(Offset(w * at, cy), 6 + 8 * a, halo);
    }

    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, _barHeight),
      const Radius.circular(_barHeight / 2),
    );
    canvas.drawRRect(bar, Paint()..color = track);
    if (shown > 0) {
      canvas.save();
      canvas.clipRRect(bar);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, math.max(w * shown, _barHeight), _barHeight),
          const Radius.circular(_barHeight / 2),
        ),
        Paint()..color = fill,
      );
      canvas.restore();
    }

    for (final x in _ticks) {
      final passed = w * shown >= w * x + 1;
      canvas.drawRect(
        Rect.fromCenter(center: Offset(w * x, cy), width: 2, height: _barHeight),
        Paint()..color = passed ? cut : tickIdle,
      );
    }

    final style = TextStyle(
      fontFamily: AppTheme.sansFontName,
      fontSize: _labelSize,
      height: 1.2,
      fontWeight: FontWeight.w500,
      color: labelColor,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    for (final x in const [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final painter = TextPainter(
        text: TextSpan(text: x == 0 ? '0' : '${(x * 100).round()}%', style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      final dx = (w * x - painter.width / 2)
          .clamp(0.0, math.max(0.0, w - painter.width))
          .toDouble();
      painter.paint(canvas, Offset(dx, _barHeight + _labelGap));
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(_MilestoneBarPainter old) =>
      old.fraction != fraction ||
      old.intro != intro ||
      old.glow != glow ||
      old.glowAt != glowAt ||
      old.track != track ||
      old.fill != fill ||
      old.cut != cut ||
      old.tickIdle != tickIdle ||
      old.labelColor != labelColor ||
      old.textScaler != textScaler;
}
