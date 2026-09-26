import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../domain/bronnen_models.dart';

/// The table of contents of a work: a compact grid of numbers when every
/// section is numbered and there are many (52 zondagen), otherwise a list with
/// the section titles (the three algemene belijdenissen, the formulieren).
class BronToc extends StatelessWidget {
  const BronToc({
    super.key,
    required this.sections,
    required this.onOpen,
    this.currentId,
  });

  final List<BronSectionHead> sections;
  final ValueChanged<String> onOpen;
  final String? currentId;

  static bool usesGrid(List<BronSectionHead> sections) =>
      sections.length > 8 && sections.every((s) => s.number != null);

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    if (usesGrid(sections)) return _grid(context);
    return RuleGrid(
      children: [
        for (final s in sections)
          RuleListTile(
            showRule: false,
            onTap: () => onOpen(s.id),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.label,
                        style: AppTheme.bodyStrong.copyWith(
                          color: s.id == currentId ? AppTheme.teal : AppTheme.ink,
                        ),
                      ),
                      if (s.title != null)
                        Text(
                          s.title!,
                          style: AppTheme.caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: AppTheme.inkFaint),
              ],
            ),
          ),
      ],
    );
  }

  Widget _grid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        // As many 44-point cells as fit, stretched to fill the row exactly.
        final perRow = ((constraints.maxWidth + gap) / (44 + gap)).floor().clamp(4, 12);
        final cell = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in sections)
              _NumberCell(
                size: cell,
                number: s.number!,
                label: s.title == null ? s.label : '${s.label}, ${s.title}',
                current: s.id == currentId,
                onTap: () => onOpen(s.id),
              ),
          ],
        );
      },
    );
  }
}

class _NumberCell extends StatelessWidget {
  const _NumberCell({
    required this.size,
    required this.number,
    required this.label,
    required this.current,
    required this.onTap,
  });

  final double size;
  final int number;
  final String label;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: current ? AppTheme.tealTint : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          side: BorderSide(color: current ? AppTheme.teal : scheme.outline),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: SizedBox(
            width: size,
            height: 44,
            child: Center(
              child: Text(
                '$number',
                style: AppTheme.bodyStrong.copyWith(
                  color: current ? AppTheme.teal : AppTheme.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The contents as a bottom sheet, from the reader's app bar.
Future<String?> showBronTocSheet(
  BuildContext context, {
  required String title,
  required List<BronSectionHead> sections,
  String? currentId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
    ),
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          24 + MediaQuery.paddingOf(sheetContext).bottom,
        ),
        children: [
          Row(
            children: [
              Expanded(child: Eyebrow('Inhoud · $title')),
              IconButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Sluiten',
                color: AppTheme.inkMuted,
              ),
            ],
          ),
          const SizedBox(height: 8),
          BronToc(
            sections: sections,
            currentId: currentId,
            onOpen: (id) => Navigator.of(sheetContext).pop(id),
          ),
        ],
      ),
    ),
  );
}
