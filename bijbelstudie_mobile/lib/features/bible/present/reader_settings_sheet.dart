import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../settings/data/reading_settings.dart';
import '../../settings/present/settings_controls.dart';

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
/// These are the very rows the Instellingen screen shows - [SettingsCard] over
/// [readingDisplayRows] - so the two places look the same and cannot drift
/// apart. Split out so the study flow can offer them from its own settings
/// sheet too: reading a lesson is reading, and a reader who has sized the text
/// once should not have to leave the lesson to do it again.
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
        // The sample verse on top: in the reader there is text behind the
        // sheet, but in a lesson sheet - and under a keyboard-height sheet -
        // there may be none to judge the choice by.
        _Preview(settings: settings),
        const SizedBox(height: 16),
        SettingsCard(
          children: readingDisplayRows(settings: settings, controller: controller),
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
