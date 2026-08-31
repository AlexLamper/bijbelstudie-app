import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// ---------------------------------------------------------------------------
/// Skeleton loaders.
///
/// The app used to show a centred spinner for every pending request. A
/// skeleton — a greyed-out sketch of the layout that is coming — tells the
/// reader what is loading and where, and it does not spin in place while a
/// slow network keeps someone waiting. These are the primitives plus a few
/// screen-shaped compositions; every `.when(loading: …)` uses one of them.
/// ---------------------------------------------------------------------------

/// One shimmering block. Give it a [height]; [width] defaults to as wide as its
/// parent allows. A [circle] ignores [radius] and paints round.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    required this.height,
    this.radius = 6,
    this.circle = false,
  });

  const Skeleton.circle(double size, {Key? key})
    : this(key: key, width: size, height: size, circle: true);

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppTheme.paperSunken;
    final highlight = Color.alphaBlend(
      Colors.white.withValues(alpha: 0.55),
      base,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Sweeps a soft band of the highlight colour left-to-right.
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.circle
                ? null
                : BorderRadius.circular(widget.radius),
            shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
            gradient: LinearGradient(
              begin: Alignment(-1.0 - 2 * (1 - t), 0),
              end: Alignment(1.0 + 2 * t, 0),
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}

/// A stack of text-line skeletons. The last line is shortened so the block
/// reads as a paragraph rather than a rectangle.
class SkeletonText extends StatelessWidget {
  const SkeletonText({
    super.key,
    this.lines = 3,
    this.lineHeight = 12,
    this.gap = 9,
    this.lastLineFraction = 0.55,
  });

  final int lines;
  final double lineHeight;
  final double gap;
  final double lastLineFraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines; i++) ...[
              if (i > 0) SizedBox(height: gap),
              Skeleton(
                height: lineHeight,
                width: i == lines - 1 && lines > 1
                    ? maxWidth * lastLineFraction
                    : null,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// An [AppCard]-shaped skeleton — the same border and radius the real cards
/// use, so the page does not jump when the data lands.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.height,
  });

  final Widget child;
  final EdgeInsets padding;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      width: double.infinity,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: scheme.outline),
      ),
      child: child,
    );
  }
}

/// Rule-separated rows, each two short lines. Covers every plain list in the
/// app — notes, highlights, bookmarks, search hits, resources.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.rows = 7,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 0),
  });

  final int rows;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: padding,
      itemCount: rows,
      itemBuilder: (context, index) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Skeleton(height: 10, width: 90),
            SizedBox(height: 10),
            SkeletonText(lines: 2, lineHeight: 11),
          ],
        ),
      ),
    );
  }
}

/// The dashboard while `/dashboard` is in flight — greeting header, the stat
/// strip, and stand-ins for the cards below it.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(
            20,
            20 + MediaQuery.of(context).padding.top,
            20,
            18,
          ),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(bottom: BorderSide(color: scheme.outline)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Skeleton(height: 22, width: 200),
              SizedBox(height: 10),
              Skeleton(height: 12, width: 140),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
          child: Column(
            children: [
              SkeletonCard(
                height: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Skeleton(height: 10, width: 120),
                    SizedBox(height: 14),
                    Skeleton(height: 20, width: 180),
                    SizedBox(height: 20),
                    Skeleton(height: 38, width: 150, radius: 12),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SkeletonCard(
                padding: EdgeInsets.symmetric(vertical: 18, horizontal: 24),
                child: Row(
                  children: [
                    Expanded(child: Center(child: Skeleton(height: 34, width: 60))),
                    Expanded(child: Center(child: Skeleton(height: 34, width: 60))),
                    Expanded(child: Center(child: Skeleton(height: 34, width: 60))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SkeletonCard(height: 220, child: _cardHeader()),
              const SizedBox(height: 16),
              SkeletonCard(height: 170, child: _cardHeader()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cardHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Row(
          children: [
            Skeleton.circle(28),
            SizedBox(width: 10),
            Skeleton(height: 14, width: 130),
          ],
        ),
        SizedBox(height: 18),
        SkeletonText(lines: 3),
      ],
    );
  }
}

/// The reader while a chapter loads — a run of verse-like lines.
class ReaderSkeleton extends StatelessWidget {
  const ReaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < 9; i++) ...[
          SkeletonText(
            lines: 3,
            lineHeight: 13,
            gap: 11,
            lastLineFraction: 0.3 + (i % 3) * 0.2,
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

/// A vertical run of banner-topped cards — the studies list.
class SkeletonCardColumn extends StatelessWidget {
  const SkeletonCardColumn({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          SkeletonCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Skeleton(height: 96, radius: 0),
                Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(height: 15, width: 160),
                      SizedBox(height: 10),
                      SkeletonText(lines: 2, lineHeight: 10),
                      SizedBox(height: 14),
                      Skeleton(height: 38, radius: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
