import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/lucide_icon.dart';
import '../domain/music_models.dart';

/// The glyphs the music surfaces draw, on Lucide's 24x24 frame so they render
/// through [LucideIcon] like the tab bar's icons. Filled shapes carry their
/// own `fill`; the frame's default is a stroke.
abstract final class MusicIcons {
  static const note = '<path d="M9 18V6l10-2v12"/><circle cx="6.5" cy="18" r="2.5"/>'
      '<circle cx="16.5" cy="16" r="2.5"/>';
  static const play = '<path d="M8 5.5v13l10-6.5z" fill="currentColor" stroke="none"/>';
  static const pause =
      '<rect x="7" y="5.5" width="3.2" height="13" rx="1" fill="currentColor" stroke="none"/>'
      '<rect x="13.8" y="5.5" width="3.2" height="13" rx="1" fill="currentColor" stroke="none"/>';
  static const stop =
      '<rect x="6.5" y="6.5" width="11" height="11" rx="2.2" fill="currentColor" stroke="none"/>';
  static const close = '<path d="M6 6l12 12M18 6 6 18"/>';
  static const chevronDown = '<path d="m6 9 6 6 6-6"/>';
  static const search = '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m20 20-4.8-4.8"/>';
  static const clock = '<circle cx="12" cy="13" r="7"/><path d="M12 9.5V13l2.5 1.5M10 3h4"/>';
  static const volumeLow = '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z"/><path d="M15.5 9a4 4 0 0 1 0 6"/>';
  static const volumeHigh = '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z"/>'
      '<path d="M15.5 9a4 4 0 0 1 0 6"/><path d="M18.5 6.5a8 8 0 0 1 0 11"/>';
}

/// Natuur sounds sit on teal, music on grey - in the picker's tiles, the
/// menu's big circle and nowhere else.
Color musicTileFill(MusicTrack track) =>
    track.isNature ? AppTheme.tealTint : AppTheme.paperSunken;

Color musicTileInk(MusicTrack track) => track.isNature ? AppTheme.teal : AppTheme.inkSoft;

/// The small outlined "PRO" capsule in both sheet headers.
class MusicProBadge extends StatelessWidget {
  const MusicProBadge({super.key});

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.ruleStrong),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        'PRO',
        style: TextStyle(
          fontFamily: AppTheme.sansFontName,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          height: 1,
          color: AppTheme.tealStrong,
        ),
      ),
    );
  }
}

/// The 36x4 handle at the top of both sheets.
class MusicSheetGrabber extends StatelessWidget {
  const MusicSheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppTheme.rule,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// Opens one of the music sheets the same way: white, 22 top radius, a light
/// ink scrim.
Future<T?> showMusicSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppTheme.paperRaised,
    barrierColor: const Color(0x47111827),
    elevation: 12,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: builder,
  );
}

/// Light shadow plus a 1px ring - the pill, the bubble and the stopped
/// message all float on it.
List<BoxShadow> musicFloatShadow({double blur = 20, double y = 6, double alpha = 0.14}) => [
  BoxShadow(
    color: const Color(0xFF111827).withValues(alpha: alpha),
    blurRadius: blur,
    offset: Offset(0, y),
  ),
];
