import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../settings/data/reading_settings.dart';

/// The reader's own typography controls, reachable from the reader bar.
///
/// Everything here also lives on the full Instellingen screen; this sheet is
/// the in-context copy so a reader can size the text while looking at it. Every
/// change is written straight through [ReadingSettingsController], so the
/// reader behind the sheet reflows live and the choice is already persisted
/// when the sheet closes.
Future<void> showReaderSettingsSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusLg),
      ),
    ),
    builder: (_) => const _ReaderSettingsSheet(),
  );
}

class _ReaderSettingsSheet extends ConsumerWidget {
  const _ReaderSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Eyebrow('Weergave'),
            ),
          ),
          const RuleLine(),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              shrinkWrap: true,
              children: const [ReaderTypographyControls()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The typography controls themselves, without a sheet around them.
///
/// Split out so the study flow can offer the same controls from its own
/// settings sheet. Reading a lesson is reading, and a reader who has sized the
/// text once should not have to leave the lesson to do it again - but nor
/// should the study flow grow a second, slightly different copy of these five
/// controls that then drifts from this one.
///
/// Every change writes straight through [ReadingSettingsController], so
/// whatever is behind the sheet reflows live and the choice is already
/// persisted when the sheet closes.
class ReaderTypographyControls extends ConsumerWidget {
  const ReaderTypographyControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readingSettingsProvider);
    final controller = ref.read(readingSettingsProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Preview(settings: settings),
        const SizedBox(height: 20),
        _ChipRow<ReaderFontSize>(
          label: 'Tekstgrootte',
          values: ReaderFontSize.values,
          selected: settings.fontSize,
          labelOf: (v) => v.label,
          onChanged: controller.setFontSize,
        ),
        const SizedBox(height: 14),
        _ChipRow<ReaderFontFamily>(
          label: 'Lettertype',
          values: ReaderFontFamily.values,
          selected: settings.fontFamily,
          labelOf: (v) => v.label,
          onChanged: controller.setFontFamily,
        ),
        const SizedBox(height: 14),
        _ChipRow<ReaderLineHeight>(
          label: 'Regelafstand',
          values: ReaderLineHeight.values,
          selected: settings.lineHeight,
          labelOf: (v) => v.label,
          onChanged: controller.setLineHeight,
        ),
        const SizedBox(height: 14),
        _ChipRow<ReaderLetterSpacing>(
          label: 'Letterafstand',
          values: ReaderLetterSpacing.values,
          selected: settings.letterSpacing,
          labelOf: (v) => v.label,
          onChanged: controller.setLetterSpacing,
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Versnummers tonen'),
          value: settings.showVerseNumbers,
          onChanged: controller.setShowVerseNumbers,
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.settings});

  final ReadingSettings settings;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Text.rich(
        TextSpan(
          children: [
            if (settings.showVerseNumbers)
              TextSpan(
                text: '1 ',
                style: TextStyle(
                  fontFamily: AppTheme.sansFontName,
                  fontSize: settings.fontSize.points * 0.62,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.inkMuted,
                ),
              ),
            const TextSpan(
              text: 'In den beginne schiep God den hemel en de aarde.',
            ),
          ],
        ),
        style: TextStyle(
          fontFamily: settings.fontFamily.fontName,
          fontSize: settings.fontSize.points,
          height: settings.lineHeight.factor,
          letterSpacing: settings.letterSpacing.points,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
    );
  }
}

class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.bodyMuted.copyWith(fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in values)
              ChoiceChip(
                label: Text(labelOf(value)),
                selected: value == selected,
                onSelected: (_) => onChanged(value),
              ),
          ],
        ),
      ],
    );
  }
}
