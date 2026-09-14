import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Lucide icons copied verbatim from the website (`lucide-react`), so the tabs
/// wear the same faces as its navigation in `components/shell/nav.ts`.
///
/// Only the path data is stored; [LucideIcon] wraps it in Lucide's standard
/// 24x24 stroked frame and paints it in the given color.
abstract final class LucideIcons {
  /// `House` - the website's Dashboard item, our Start tab.
  static const house = '<path d="M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8"/>'
      '<path d="M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>';

  /// `BookMarked` - the website's Lezen item, our Bijbel tab.
  static const bookMarked = '<path d="M10 2v8l3-3 3 3V2"/>'
      '<path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H19a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H6.5a1 1 0 0 1 0-5H20"/>';

  /// `NotebookPen` - the website's Notities item.
  static const notebookPen =
      '<path d="M13.4 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-7.4"/>'
      '<path d="M2 6h4"/><path d="M2 10h4"/><path d="M2 14h4"/><path d="M2 18h4"/>'
      '<path d="M21.378 5.626a1 1 0 1 0-3.004-3.004l-5.01 5.012a2 2 0 0 0-.506.854l-.837 2.87a.5.5 0 0 0 .62.62l2.87-.837a2 2 0 0 0 .854-.506z"/>';
}

class LucideIcon extends StatelessWidget {
  const LucideIcon(
    this.paths, {
    super.key,
    required this.size,
    required this.color,
    this.strokeWidth = 2,
  });

  /// One of the [LucideIcons] path strings.
  final String paths;
  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
      'stroke="currentColor" stroke-width="$strokeWidth" stroke-linecap="round" '
      'stroke-linejoin="round">$paths</svg>',
      width: size,
      height: size,
      theme: SvgTheme(currentColor: color),
    );
  }
}
