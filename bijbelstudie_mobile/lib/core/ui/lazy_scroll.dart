import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Scrolls a lazily built list so row [index] ends up in view.
///
/// `Scrollable.ensureVisible` only works on a row that has been built, and a
/// `ListView` only builds the rows near the viewport - so a jump to verse 150
/// from the top of a chapter used to find no `BuildContext` and silently do
/// nothing. This estimates where the row must be from the rows that *are*
/// built, jumps there, waits a frame for the list to build around it and
/// tries again, up to [maxAttempts] times. Once the row exists it moves to its
/// exact offset: animated when [animate] is true, instant otherwise (reduced
/// motion, or a pane that is not on screen and so has its tickers muted).
///
/// [contextFor] returns the row's context (usually a `GlobalKey`'s), or null
/// while it is not built. [alignment] is as for `ensureVisible`: 0 puts the
/// row's top at the top of the viewport. [leadingPadding] leaves that much
/// room above it.
///
/// Returns true when the row was reached.
Future<bool> scrollToLazyItem({
  required ScrollController controller,
  required int index,
  required int itemCount,
  required BuildContext? Function(int index) contextFor,
  double alignment = 0,
  double leadingPadding = 0,
  bool animate = true,
  Duration duration = const Duration(milliseconds: 380),
  Curve curve = Curves.easeOutCubic,
  int maxAttempts = 4,
}) async {
  if (itemCount <= 0 || index < 0 || index >= itemCount) return false;

  for (var attempt = 0; attempt <= maxAttempts; attempt++) {
    if (!controller.hasClients) return false;
    final position = controller.position;

    final target = _rowBox(contextFor(index));
    if (target != null) {
      final offset = _revealOffset(target, position, alignment, leadingPadding);
      if (animate && (offset - position.pixels).abs() > 1) {
        await controller.animateTo(offset, duration: duration, curve: curve);
      } else {
        controller.jumpTo(offset);
      }
      // The rows passed on the way may have measured differently from the
      // estimate the list laid out with; settle on the real position once.
      if (controller.hasClients) {
        final settled = _rowBox(contextFor(index));
        if (settled != null) {
          final exact = _revealOffset(
            settled,
            controller.position,
            alignment,
            leadingPadding,
          );
          if ((exact - controller.position.pixels).abs() > 2) {
            controller.jumpTo(exact);
          }
        }
      }
      return true;
    }

    if (attempt == maxAttempts) break;
    controller.jumpTo(_estimateOffset(position, index, itemCount, contextFor));
    await SchedulerBinding.instance.endOfFrame;
  }
  return false;
}

RenderBox? _rowBox(BuildContext? context) {
  if (context == null || !context.mounted) return null;
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  if (RenderAbstractViewport.maybeOf(box) == null) return null;
  return box;
}

/// Scroll offset of the top of [box], in the list's own coordinates.
double _rowTop(RenderBox box) =>
    RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;

double _revealOffset(
  RenderBox box,
  ScrollPosition position,
  double alignment,
  double leadingPadding,
) {
  final raw = RenderAbstractViewport.of(
    box,
  ).getOffsetToReveal(box, alignment).offset;
  return (raw - leadingPadding).clamp(
    position.minScrollExtent,
    position.maxScrollExtent,
  );
}

/// Where row [index] probably starts: the nearest built row's offset plus the
/// average height of the built rows for each row in between.
double _estimateOffset(
  ScrollPosition position,
  int index,
  int itemCount,
  BuildContext? Function(int index) contextFor,
) {
  int? nearest;
  double nearestTop = 0;
  int? firstBuilt;
  int? lastBuilt;
  double spanTop = double.infinity;
  double spanBottom = double.negativeInfinity;

  for (var i = 0; i < itemCount; i++) {
    final box = _rowBox(contextFor(i));
    if (box == null) continue;
    final top = _rowTop(box);
    firstBuilt ??= i;
    lastBuilt = i;
    if (top < spanTop) spanTop = top;
    if (top + box.size.height > spanBottom) spanBottom = top + box.size.height;
    if (nearest == null || (i - index).abs() < (nearest - index).abs()) {
      nearest = i;
      nearestTop = top;
    }
  }

  final double estimate;
  if (nearest == null || firstBuilt == null || lastBuilt == null) {
    final max = position.maxScrollExtent;
    estimate = itemCount <= 1 ? 0 : max * index / (itemCount - 1);
  } else {
    final average = (spanBottom - spanTop) / (lastBuilt - firstBuilt + 1);
    estimate = nearestTop + (index - nearest) * average;
  }
  return estimate.clamp(position.minScrollExtent, position.maxScrollExtent);
}
