import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'pressable.dart';

/// One option of a [SegmentedTrack]: a plain [label], or a [builder] for
/// anything richer (a glyph, a sample, an icon over a caption).
///
/// The builder gets the colour its content should be drawn in - accent when
/// selected, muted otherwise. The same colour is also set as the ambient
/// [DefaultTextStyle] and [IconTheme], so a bare `Text` or `Icon` picks it up
/// without reading it.
class SegmentedTrackSegment {
  const SegmentedTrackSegment({this.label, this.builder, this.semanticLabel})
      : assert(label != null || builder != null, 'a segment needs a label or a builder');

  final String? label;
  final Widget Function(BuildContext context, bool selected, Color color)? builder;

  /// What a screen reader announces. Falls back to [label].
  final String? semanticLabel;
}

/// A full-width segmented control: a sunken track with a raised thumb that
/// slides to the chosen option, whose content turns accent.
///
/// Unlike [AppSegmentedControl] (a compact pill that sits beside a title) this
/// one fills its row and splits it evenly, so it also carries richer segments
/// such as type samples. Every segment is at least [minHeight] tall, which is
/// kept at the 44px tap target or above.
class SegmentedTrack extends StatelessWidget {
  const SegmentedTrack({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.minHeight = 44,
  }) : assert(segments.length > 1, 'a segmented control needs two or more segments');

  final List<SegmentedTrackSegment> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final count = segments.length;
    final selected = selectedIndex.clamp(0, count - 1);
    // Light: white thumb on the grey page tone. Dark: the page tone is darker
    // than the card, so the track still reads as sunken and the thumb as lifted.
    final thumbColor =
        AppTheme.isDark ? AppTheme.darkPaperSunkenStrong : AppTheme.lightPaperRaised;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment(-1 + 2 * selected / (count - 1), 0),
              child: FractionallySizedBox(
                widthFactor: 1 / count,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: thumbColor,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm + 1),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow,
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < count; i++)
                  Expanded(child: _segment(context, i, i == selected)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, int index, bool isSelected) {
    final segment = segments[index];
    final color = isSelected ? AppTheme.teal : AppTheme.inkMuted;
    final content = segment.builder != null
        ? segment.builder!(context, isSelected, color)
        : Text(
            segment.label!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          );

    return Semantics(
      button: true,
      selected: isSelected,
      label: segment.semanticLabel ?? segment.label,
      excludeSemantics: segment.semanticLabel != null || segment.label != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (index != selectedIndex) AppHaptics.selection();
          onChanged(index);
        },
        child: ConstrainedBox(
          // The track's 3px inset counts towards the tap target.
          constraints: BoxConstraints(minHeight: minHeight - 6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Center(
              child: IconTheme.merge(
                data: IconThemeData(color: color, size: 18),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    fontFamily: AppTheme.sansFontName,
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                  ),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
