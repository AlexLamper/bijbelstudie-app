import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/bible_models.dart';
import '../domain/version_catalog.dart';

/// The short code of a translation, drawn as a fixed square.
///
/// This is the picker's visual anchor: a reader looking for the
/// Statenvertaling is looking for `SV`, and type is a better handle for that
/// than any icon would be.
///
/// Fixed on purpose: `SV` and `HS1917` sit in the same box, so the column of
/// badges down the left of the picker stays a column. Long codes shrink to
/// fit rather than widening the square, and the catalog caps the code length
/// so nothing has to shrink into illegibility.
class VersionBadge extends StatelessWidget {
  const VersionBadge({super.key, required this.code, this.selected = false, this.size = 40});

  VersionBadge.forVersion(BibleSource version, {super.key, this.selected = false, this.size = 40})
      : code = VersionCatalog.shortCode(version);

  final String code;

  /// The currently open translation gets the solid accent, matching the check
  /// mark on its card.
  ///
  /// Solid rather than tinted: the selected card is itself tinted now, and a
  /// tinted badge on a tinted card is a badge you cannot see.
  final bool selected;

  final double size;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final foreground = selected ? Colors.white : AppTheme.inkSoft;

    return Semantics(
      label: 'Afkorting $code',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? AppTheme.teal : AppTheme.paperSunken,
          border: Border.all(color: selected ? AppTheme.tealStrong : AppTheme.rule),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            code,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontFamily: AppTheme.sansFontName,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              height: 1,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

/// The heading above a language group of translations: the language name and
/// how many translations are under it.
///
/// Type only. Two things went: the grey band, which made a heading look like
/// one more tappable row in a list of tappable rows, and the globe, which said
/// nothing the word `Nederlands` had not already said. What is left is the
/// app's own group-label treatment - uppercase teal, the same heading the
/// reader's canon groups carry - sitting on whatever the sheet's background
/// is, with the count behind it in the quietest ink the palette has.
class LanguageSectionHeader extends StatelessWidget {
  const LanguageSectionHeader({super.key, required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Semantics(
      header: true,
      label: '$label, $count vertalingen',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 16, 2, 10),
        child: Row(
          children: [
            Text(label.toUpperCase(), style: AppTheme.groupLabel),
            const SizedBox(width: 8),
            Text(
              count == 1 ? '1 vertaling' : '$count vertalingen',
              style: AppTheme.metaLabel.copyWith(letterSpacing: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
