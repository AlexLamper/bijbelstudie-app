import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// ---------------------------------------------------------------------------
/// Building blocks copied from www.bijbel-studie.com.
///
/// The site is a shadcn/Tailwind system: white cards on a light grey page,
/// `border border-gray-200`, `rounded-xl` / `rounded-2xl`, Inter with bold
/// weights for hierarchy, and teal `#0D9488` as the only accent.
/// ---------------------------------------------------------------------------

/// `<p class="text-xs font-semibold uppercase tracking-widest text-gray-400">`
class Eyebrow extends StatelessWidget {
  const Eyebrow(
    this.label, {
    super.key,
    this.color,
    this.ruleColor,
    this.compact = false,
  });

  final String label;
  final Color? color;

  /// Retained for source compatibility — the site draws no rule any more.
  final Color? ruleColor;

  /// The 10px variant used above stat numbers.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = (compact ? AppTheme.overline : AppTheme.eyebrow).copyWith(
      color: color ?? AppTheme.inkFaint,
    );
    return Text(
      label.toUpperCase(),
      style: style,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Page intro — `text-xl font-bold` heading with a muted sub-line, exactly the
/// dashboard's `px-6 pt-7 pb-5 border-b border-border` header block.
class GradientHeader extends StatelessWidget {
  const GradientHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.accent = false,
    this.eyebrow,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final bool accent;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                Eyebrow(eyebrow!),
                const SizedBox(height: 8),
              ],
              Text(title, style: AppTheme.displaySmall),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: AppTheme.bodyMuted),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 16), trailing!],
      ],
    );
  }
}

/// Section heading — `text-sm font-bold` with an optional trailing link, the
/// pattern used above every dashboard card list.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.description,
    this.actionLabel,
    this.onAction,
    this.showRule = false,
    this.icon,
  });

  final String title;
  final String? eyebrow;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showRule;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              IconChip(icon: icon!),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.displayBase),
                  if (description != null) ...[
                    const SizedBox(height: 2),
                    Text(description!, style: AppTheme.caption),
                  ],
                ],
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: 12),
              InkWell(
                onTap: onAction,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        actionLabel!,
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.teal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: AppTheme.teal,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        if (showRule) ...[const SizedBox(height: 12), const RuleLine()],
      ],
    );
  }
}

/// A 1px hairline — `border-border`.
class RuleLine extends StatelessWidget {
  const RuleLine({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: color ?? Theme.of(context).colorScheme.outline,
    );
  }
}

/// `h-7 w-7 rounded-lg bg-[rgba(13,148,136,0.08)]` with a small teal glyph —
/// the icon chip that heads every card on the site.
class IconChip extends StatelessWidget {
  const IconChip({
    super.key,
    required this.icon,
    this.color,
    this.size = 28,
    this.iconSize = 14,
  });

  final IconData icon;

  /// Null means the brand accent, resolved at build time. It cannot be a
  /// default value: `AppTheme.teal` is brightness-resolved, so it is not a
  /// constant, and this constructor has to stay `const`.
  final Color? color;

  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? AppTheme.teal;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

/// `bg-white dark:bg-card border border-gray-200 dark:border-border
///  rounded-2xl` — the site never puts a shadow on a content card.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = AppTheme.radiusLg,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = color ?? scheme.surface;
    final line = borderColor ?? scheme.outline;

    if (onTap == null) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: line),
        ),
        clipBehavior: clip ? Clip.antiAlias : Clip.none,
        child: child,
      );
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        highlightColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        splashColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: line),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The teal hero panel — `rounded-2xl p-6` filled with
/// `linear-gradient(135deg,#0D9488,#0F766E)`. Used for "Ga verder waar je
/// gebleven was" on the dashboard and for every primary call to action.
class BrandHeroCard extends StatelessWidget {
  const BrandHeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: content,
      ),
    );
  }
}

/// White card whose children are separated by 1px rules — the site's list
/// card (`bg-white rounded-2xl border divide-y divide-border`).
class RuleGrid extends StatelessWidget {
  const RuleGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) items.add(const RuleLine());
      items.add(children[i]);
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      ),
    );
  }
}

/// One value in a [StatStrip].
class StatItem {
  const StatItem({
    required this.value,
    required this.label,
    this.ruleColor,
    this.icon,
    this.color,
  });

  final String value;
  final String label;

  /// Legacy name, still honoured as the icon tint.
  final Color? ruleColor;
  final IconData? icon;
  final Color? color;

  Color get tint => color ?? ruleColor ?? AppTheme.teal;
}

/// One `bg-white border rounded-xl` card holding the dashboard's stat trio
/// side by side, `divide-x divide-border` in Tailwind terms — icon and value
/// inline per column, a single-line label under each, thin vertical rules
/// between. Replaces the old one-card-per-stat grid, which wasted a border
/// and a row of vertical space on every tile for what is, on a phone, three
/// numbers the reader mostly skims.
class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.items, this.stacked = false});

  final List<StatItem> items;

  /// Retained for source compatibility; the strip only has the one layout.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      radius: AppTheme.radiusMd,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      // `stretch` needs a bounded cross axis; inside a ListView the Row's
      // height is unbounded, so the intrinsic pass is what makes the rule
      // between columns match the tallest column instead of asking for
      // infinity.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) ...[
                const SizedBox(width: 8),
                Container(width: 1, color: scheme.outline),
                const SizedBox(width: 8),
              ],
              Expanded(child: _StatColumn(item: items[i])),
            ],
          ],
        ),
      ),
    );
  }
}

/// One column of a [StatStrip] — icon beside the value, a tight one-line
/// label underneath, everything centred so the row reads as balanced.
class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.item});

  final StatItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Scales the icon+value pair down instead of truncating it, so a
        // wide value (e.g. "12 / 66") never overflows a narrow column on a
        // small phone.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(item.icon ?? Icons.circle, size: 15, color: item.tint),
              const SizedBox(width: 5),
              Text(
                item.value,
                style: AppTheme.statNumber.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item.label,
          style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// `inline-flex items-center gap-1.5 text-xs font-semibold px-2.5 py-1
///  rounded-full` on a tinted background — the streak pill and every tag.
class SiteBadge extends StatelessWidget {
  const SiteBadge(
    this.label, {
    super.key,
    this.background,
    this.foreground,
    this.borderColor,
    this.icon,
    this.solid = false,
  });

  final String label;
  final Color? background;
  final Color? foreground;
  final Color? borderColor;
  final IconData? icon;

  /// Filled with the accent instead of its 8% tint.
  final bool solid;

  // The tone shorthands cannot be const: their colours are brightness-resolved
  // getters now, and a const redirect may only pass constant arguments.

  SiteBadge.lapis(String label, {Key? key, IconData? icon})
    : this(label, key: key, foreground: AppTheme.teal, icon: icon);

  SiteBadge.teal(String label, {Key? key, IconData? icon})
    : this(label, key: key, foreground: AppTheme.teal, icon: icon);

  SiteBadge.positive(String label, {Key? key, IconData? icon})
    : this(label, key: key, foreground: AppTheme.positive, icon: icon);

  SiteBadge.vermilion(String label, {Key? key, IconData? icon})
    : this(label, key: key, foreground: AppTheme.flame, icon: icon);

  SiteBadge.neutral(String label, {Key? key, IconData? icon})
    : this(label, key: key, foreground: AppTheme.inkMuted, icon: icon);

  @override
  Widget build(BuildContext context) {
    final accent = foreground ?? AppTheme.teal;
    final fg = solid ? Colors.white : accent;
    final bg = background ?? (solid ? accent : accent.withValues(alpha: 0.10));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: AppTheme.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Primary action — teal fill, `rounded-xl`, `text-sm font-semibold text-white`.
class SiteButton extends StatelessWidget {
  const SiteButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.height = 48,
    this.expand = true,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final double height;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        // The theme sets `minimumSize: Size.fromHeight(48)`, i.e. an *infinite*
        // minimum width. Inside a Row that swallows the whole line and starves
        // the flexible siblings, so a non-expanding button must drop it.
        style: expand ? null : _compactStyle(height),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16),
                    const SizedBox(width: 8),
                  ],
                  Text(label),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: 8),
                    Icon(trailingIcon, size: 16),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Secondary action — `border border-gray-200 bg-white text-foreground`.
class SiteOutlineButton extends StatelessWidget {
  const SiteOutlineButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.height = 48,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: OutlinedButton(
        onPressed: onPressed,
        // See [SiteButton.build]: the theme's infinite minimum width has to go
        // when the button shares a Row with flexible content.
        style: expand ? null : _compactStyle(height),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16),
              const SizedBox(width: 8),
            ],
            Text(label),
          ],
        ),
      ),
    );
  }
}

/// The white pill button that sits on the teal hero — `bg-white rounded-xl
/// px-5 py-2.5 text-sm font-semibold text-[#0D9488]`.
class OnBrandButton extends StatelessWidget {
  const OnBrandButton({
    super.key,
    required this.label,
    this.onPressed,
    this.trailingIcon = Icons.arrow_forward,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTheme.buttonLabel.copyWith(color: AppTheme.teal),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 8),
                Icon(trailingIcon, size: 14, color: AppTheme.teal),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Style override for buttons that must size to their label instead of to the
/// full line. Only the properties that need to differ are set, so everything
/// else still comes from the theme.
ButtonStyle _compactStyle(double height) {
  return ButtonStyle(
    minimumSize: WidgetStatePropertyAll<Size>(Size(0, height)),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: 14),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

/// A rule-separated list row, as used by every settings and notes list.
class RuleListTile extends StatelessWidget {
  const RuleListTile({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.showRule = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool showRule;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Container(
      padding: padding,
      decoration: showRule
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outline)),
            )
          : null,
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        highlightColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        splashColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        child: content,
      ),
    );
  }
}

/// Thin rounded progress track — `h-1.5 rounded-full bg-gray-200` with a teal
/// fill, the bar under every plan and study card.
class SiteProgressBar extends StatelessWidget {
  const SiteProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.color,
  });

  final double value;
  final double height;

  /// Null means the brand accent; see [IconChip.color].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        color: color ?? AppTheme.teal,
      ),
    );
  }
}

/// Loading spinner — teal, matching `text-brand` on the site.
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
    );
  }
}

/// Empty / error state — a muted glyph, a bold title and a muted lead.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.action,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.teal.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Icon(icon, size: 22, color: AppTheme.teal),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.displayTitle.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: AppTheme.bodyMuted,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}
