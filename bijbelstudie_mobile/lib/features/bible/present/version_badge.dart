import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/bible_models.dart';
import '../domain/version_catalog.dart';

/// The short code of a translation, drawn as a fixed square.
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

  /// The currently open translation gets the accent treatment, matching the
  /// check mark on its row.
  final bool selected;

  final double size;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppTheme.lapis : AppTheme.inkSoft;

    return Semantics(
      label: 'Afkorting $code',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: selected ? AppTheme.lapisTint : AppTheme.paperSunken,
          border: Border.all(color: selected ? AppTheme.lapis : AppTheme.rule),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            code,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontFamily: AppTheme.sansFontName,
              fontSize: 13,
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

/// A real section header for a language group: globe, language name, and how
/// many translations are in it.
///
/// Replaces the hairline-with-a-word separator, which read as a divider
/// rather than as the start of a section. The count is deliberately quieter
/// than the name — it is a detail of the section, not a second heading.
class LanguageSectionHeader extends StatelessWidget {
  const LanguageSectionHeader({super.key, required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: '$label, $count vertalingen',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        color: AppTheme.paperSunken,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Icon(Icons.language, size: 16, color: AppTheme.inkMuted),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.sansFontName,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: AppTheme.sansFontName,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
