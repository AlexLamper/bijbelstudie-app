import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Small building blocks shared by the "Bijbel in een jaar" widgets - the
/// app's counterpart of the website's `components/bibleYear/parts.tsx`.

/// A square tick box with a real checkbox role.
class BibleYearTickBox extends StatelessWidget {
  const BibleYearTickBox({
    super.key,
    required this.checked,
    required this.onChanged,
    required this.label,
    this.disabled = false,
  });

  final bool checked;
  final ValueChanged<bool> onChanged;
  final String label;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Semantics(
      checked: checked,
      label: label,
      enabled: !disabled,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : () => onChanged(!checked),
        // 36pt hit area around a 24pt box.
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: checked ? AppTheme.teal : AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusXs),
              border: Border.all(color: checked ? AppTheme.teal : AppTheme.ruleStrong, width: 1.4),
            ),
            child: checked ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
          ),
        ),
      ),
    );
  }
}

/// Compact teal button ("Gelezen").
class BibleYearPrimaryButton extends StatelessWidget {
  const BibleYearPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.height = 36,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.tealFill,
        foregroundColor: Colors.white,
        minimumSize: Size(0, height),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
        textStyle: AppTheme.pillLabel.copyWith(fontSize: 13),
      ),
      child: Text(label),
    );
  }
}

/// Compact outlined button ("Bijlezen", "Schema verschuiven").
class BibleYearSecondaryButton extends StatelessWidget {
  const BibleYearSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.trailing,
    this.height = 36,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.inkSoft,
        backgroundColor: AppTheme.surface,
        side: BorderSide(color: AppTheme.rule),
        minimumSize: Size(0, height),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
        textStyle: AppTheme.pillLabel.copyWith(fontSize: 13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );
  }
}

/// The plan's share of the whole Bible as a thin bar.
class BibleYearProgressBar extends StatelessWidget {
  const BibleYearProgressBar({super.key, required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final p = percent.isFinite ? percent.clamp(0.0, 100.0) : 0.0;
    return Semantics(
      label: 'Deel van de Bijbel gelezen',
      value: '${p.round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: LinearProgressIndicator(
          value: p / 100,
          minHeight: 6,
          backgroundColor: AppTheme.rule,
          color: AppTheme.teal,
        ),
      ),
    );
  }
}

/// The small teal uppercase line above a card title.
class BibleYearEyebrow extends StatelessWidget {
  const BibleYearEyebrow(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Text(
      label.toUpperCase(),
      style: AppTheme.metaLabel.copyWith(color: AppTheme.tealStrong, letterSpacing: 1.1),
    );
  }
}

/// A two-button confirm dialog. Resolves true on confirm.
Future<bool> showBibleYearConfirm(
  BuildContext context, {
  required String title,
  required Widget content,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: content,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Annuleren'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: AppTheme.tealStrong),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
