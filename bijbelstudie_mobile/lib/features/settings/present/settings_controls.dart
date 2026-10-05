import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/segmented_track.dart';
import '../data/reading_settings.dart';

// The controls the Instellingen screen is built from, and with it the reader's
// Weergave sheet. Instellingen is where these were designed, so it owns the
// look; the sheet asks readingDisplayRows() for the very same rows instead of
// keeping a second copy that then drifts. Both write through
// ReadingSettingsController, so a choice made in either place is one choice.

/// Marker for widgets that render as a [SettingsRow]; [SettingsCard] only
/// draws a hairline between two neighbours that both carry it, so cards and
/// paragraphs inside a group are never underlined.
abstract interface class SettingsRowLike {}

/// The card a run of rows sits in: one rounded, outlined panel with hairlines
/// between consecutive [SettingsRowLike] children.
///
/// The settings list wraps this in a titled group; a bottom sheet uses it on
/// its own.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 &&
                children[i - 1] is SettingsRowLike &&
                children[i] is SettingsRowLike)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: RuleLine(),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// The five reading-display rows - text size, typeface, line height, letter
/// spacing and the verse-number switch - ready to drop into a [SettingsCard].
///
/// A list rather than a widget so the card can draw its hairlines between the
/// rows, and so the Instellingen screen can keep them in its own titled group.
List<Widget> readingDisplayRows({
  required ReadingSettings settings,
  required ReadingSettingsController controller,
}) {
  return [
    SettingsSegmentRow<ReaderFontSize>(
      label: 'Tekstgrootte',
      values: ReaderFontSize.values,
      selected: settings.fontSize,
      valueLabel: (v) => v.label,
      onChanged: controller.setFontSize,
      segment: (v, color) => Text(
        'A',
        style: TextStyle(
          fontFamily: AppTheme.sansFontName,
          fontSize: switch (v) {
            ReaderFontSize.small => 12,
            ReaderFontSize.base => 15,
            ReaderFontSize.large => 18,
            ReaderFontSize.xlarge => 21,
          },
          height: 1.2,
          color: color,
        ),
      ),
    ),
    SettingsSegmentRow<ReaderFontFamily>(
      label: 'Lettertype',
      values: ReaderFontFamily.values,
      selected: settings.fontFamily,
      valueLabel: (v) => v.label,
      onChanged: controller.setFontFamily,
      segment: (v, color) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Aa',
            style: TextStyle(
              fontFamily: v.fontName,
              fontSize: 18,
              height: 1.2,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            v.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    ),
    SettingsSegmentRow<ReaderLineHeight>(
      label: 'Regelafstand',
      values: ReaderLineHeight.values,
      selected: settings.lineHeight,
      valueLabel: (v) => v.label,
      onChanged: controller.setLineHeight,
      segment: (v, color) => LineSpacingGlyph(
        gap: switch (v) {
          ReaderLineHeight.snug => 2,
          ReaderLineHeight.normal => 3.5,
          ReaderLineHeight.relaxed => 5,
          ReaderLineHeight.loose => 6.5,
        },
        color: color,
      ),
    ),
    SettingsSegmentRow<ReaderLetterSpacing>(
      label: 'Letterafstand',
      values: ReaderLetterSpacing.values,
      selected: settings.letterSpacing,
      valueLabel: (v) => v.label,
      onChanged: controller.setLetterSpacing,
      // The stored steps, exaggerated so they can be told apart at
      // this size.
      segment: (v, color) => Text(
        'abc',
        maxLines: 1,
        style: TextStyle(
          fontFamily: AppTheme.sansFontName,
          fontSize: 14,
          letterSpacing: v.points * 2,
          color: color,
        ),
      ),
    ),
    SettingsRow(
      label: 'Versnummers tonen',
      switchValue: settings.showVerseNumbers,
      onSwitchChanged: controller.setShowVerseNumbers,
    ),
  ];
}

/// A Leesweergave row: label left, the current value right, and under both a
/// full-width [SegmentedTrack] whose segments show the choice rather than name
/// it.
class SettingsSegmentRow<T> extends StatelessWidget implements SettingsRowLike {
  const SettingsSegmentRow({
    super.key,
    required this.label,
    required this.values,
    required this.selected,
    required this.valueLabel,
    required this.onChanged,
    required this.segment,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T value) valueLabel;
  final ValueChanged<T> onChanged;
  final Widget Function(T value, Color color) segment;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTheme.bodyLead.copyWith(
                    color: AppTheme.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(valueLabel(selected), style: AppTheme.bodyMuted),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedTrack(
            segments: [
              for (final v in values)
                SegmentedTrackSegment(
                  semanticLabel: valueLabel(v),
                  builder: (context, _, color) => segment(v, color),
                ),
            ],
            selectedIndex: values.indexOf(selected),
            onChanged: (i) {
              if (values[i] != selected) onChanged(values[i]);
            },
          ),
        ],
      ),
    );
  }
}

/// Three short lines with [gap] between them - the Regelafstand glyph.
class LineSpacingGlyph extends StatelessWidget {
  const LineSpacingGlyph({super.key, required this.gap, required this.color});

  final double gap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget line() => Container(
      width: 20,
      height: 2,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [line(), SizedBox(height: gap), line(), SizedBox(height: gap), line()],
    );
  }
}

/// One row of a [SettingsCard]: label and optional subtitle on the left; on
/// the right - only the ones that apply, in this order - a custom trailing
/// widget, a switch or a chevron (rows that open something). A switch row flips
/// its switch when tapped.
class SettingsRow extends StatelessWidget implements SettingsRowLike {
  const SettingsRow({
    super.key,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.switchValue,
    this.onSwitchChanged,
  }) : assert(switchValue == null || onTap == null,
            'a switch row toggles on tap; it cannot also open something');

  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitchChanged;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final isSwitch = switchValue != null;
    final dimmed = isSwitch && onSwitchChanged == null;
    final tap = onTap ??
        (isSwitch && onSwitchChanged != null
            ? () => onSwitchChanged!(!switchValue!)
            : null);
    final showChevron =
        onTap != null && !isSwitch && trailing == null;
    final inkColor = dimmed ? AppTheme.inkFaint : AppTheme.ink;

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTheme.bodyLead.copyWith(
                      color: inkColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: AppTheme.caption),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            if (isSwitch) ...[
              const SizedBox(width: 8),
              Switch(
                value: switchValue!,
                onChanged: onSwitchChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
            if (showChevron) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: AppTheme.inkFaint),
            ],
          ],
        ),
      ),
    );

    if (tap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: tap, child: content),
    );
  }
}
