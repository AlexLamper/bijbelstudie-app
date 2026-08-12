import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Site button.
///
/// Primary  : `h-12 rounded-xl bg-[#0D9488] px-5 text-white hover:opacity-90`
/// Secondary: `h-12 rounded-xl border border-gray-200 bg-white text-foreground
///             hover:bg-secondary`
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isSecondary;
  final Widget? leading;
  final double height;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isSecondary = false,
    this.leading,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bgColor = isSecondary ? scheme.surface : scheme.secondary;
    final fgColor = isSecondary ? scheme.onSurface : Colors.white;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          disabledBackgroundColor: isSecondary
              ? scheme.surfaceContainerHighest
              : scheme.secondary.withValues(alpha: 0.45),
          disabledForegroundColor: isSecondary
              ? scheme.onSurfaceVariant
              : Colors.white.withValues(alpha: 0.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            side: isSecondary
                ? BorderSide(color: scheme.outline)
                : BorderSide.none,
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: AppTheme.buttonLabel,
        ),
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(fgColor),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 10)],
                  Flexible(
                    child: Text(
                      text,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTheme.sansFontName,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
