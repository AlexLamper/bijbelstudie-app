import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import 'commentary_jump.dart';

/// "Ga naar vers": every verse of the chapter as a grid, styled like the
/// chapter grid in the book picker.
///
/// A verse the commentator has no entry of their own for is dimmed, not
/// hidden - tapping it still goes somewhere useful, the entry before it,
/// which is usually where that verse is being discussed. Resolves to the
/// tapped verse number (0 for the introduction), or null when dismissed.
Future<int?> showVerseJumpSheet({
  required BuildContext context,
  required List<int> entryNumbers,
  required int verseCount,
  int? currentEntry,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusLg),
      ),
    ),
    builder: (sheetContext) => VerseJumpSheet(
      entryNumbers: entryNumbers,
      verseCount: verseCount,
      currentEntry: currentEntry,
    ),
  );
}

class VerseJumpSheet extends StatelessWidget {
  const VerseJumpSheet({
    super.key,
    required this.entryNumbers,
    required this.verseCount,
    this.currentEntry,
  });

  /// Verse numbers that have an entry, ascending; 0 is the introduction.
  final List<int> entryNumbers;

  /// The last verse number to offer.
  final int verseCount;

  /// The entry currently at the top of the commentary, marked in the grid.
  final int? currentEntry;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final hasEntry = entryNumbers.toSet();
    final hasIntro = hasEntry.contains(0);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Eyebrow('Ga naar vers'),
              ),
            ),
            const RuleLine(),
            Flexible(
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  color: AppTheme.paperSunken,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (hasIntro)
                        _VerseCell(
                          label: 'Inleiding',
                          semanticsLabel: 'Inleiding',
                          width: 88,
                          available: true,
                          current: currentEntry == 0,
                          onTap: () => Navigator.of(context).pop(0),
                        ),
                      for (var verse = 1; verse <= verseCount; verse++)
                        _cellFor(context, verse, hasEntry),
                    ],
                  ),
                ),
              ),
            ),
            if (hasEntry.length < verseCount + (hasIntro ? 1 : 0))
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                child: Text(
                  'Lichte nummers hebben geen eigen commentaar; je gaat dan naar '
                  'het commentaar ervoor.',
                  style: AppTheme.bodyMuted.copyWith(fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cellFor(BuildContext context, int verse, Set<int> hasEntry) {
    final available = hasEntry.contains(verse);
    final String semanticsLabel;
    if (available) {
      semanticsLabel = 'Vers $verse';
    } else {
      final index = commentaryEntryIndexFor(entryNumbers, verse);
      final fallback = index == null ? null : entryNumbers[index];
      semanticsLabel = fallback == null
          ? 'Vers $verse, geen commentaar'
          : 'Vers $verse, geen eigen commentaar. Toont '
                '${fallback == 0 ? 'de inleiding' : 'vers $fallback'}';
    }
    return _VerseCell(
      label: '$verse',
      semanticsLabel: semanticsLabel,
      available: available,
      current: available && currentEntry == verse,
      onTap: () => Navigator.of(context).pop(verse),
    );
  }
}

class _VerseCell extends StatelessWidget {
  const _VerseCell({
    required this.label,
    required this.semanticsLabel,
    required this.available,
    required this.current,
    required this.onTap,
    this.width = 40,
  });

  final String label;
  final String semanticsLabel;
  final bool available;
  final bool current;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color border;
    final Color text;
    if (current) {
      background = AppTheme.tealWash;
      border = AppTheme.teal;
      text = AppTheme.tealStrong;
    } else if (available) {
      background = AppTheme.paperRaised;
      border = AppTheme.rule;
      text = AppTheme.ink;
    } else {
      background = Colors.transparent;
      border = AppTheme.rule;
      text = AppTheme.inkFaint;
    }

    return Semantics(
      button: true,
      selected: current,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          width: width,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Text(
            label,
            style: AppTheme.caption.copyWith(
              color: text,
              fontWeight: current ? FontWeight.w600 : null,
            ),
          ),
        ),
      ),
    );
  }
}
