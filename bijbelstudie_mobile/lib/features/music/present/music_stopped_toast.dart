import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/lucide_icon.dart';
import 'music_widgets.dart';

/// "Muziek gestopt - Ongedaan maken", for the four seconds after a stop.
///
/// Always in the tree while the overlay is, so it can animate out as well as
/// in; hidden it is transparent, ignores touches and says nothing to a screen
/// reader.
class MusicStoppedToast extends StatelessWidget {
  const MusicStoppedToast({
    super.key,
    required this.visible,
    required this.onUndo,
    required this.reduceMotion,
  });

  final bool visible;
  final VoidCallback onUndo;
  final bool reduceMotion;

  static const _curve = Cubic(0.2, 0.8, 0.2, 1);

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final text = TextStyle(
      fontFamily: AppTheme.sansFontName,
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
      color: AppTheme.ink,
    );

    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
          child: AnimatedSlide(
            offset: visible || reduceMotion ? Offset.zero : const Offset(0, 16 / 46),
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 350),
            curve: _curve,
            child: Semantics(
              liveRegion: true,
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppTheme.paperRaised,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.rule),
                  boxShadow: musicFloatShadow(),
                ),
                child: Row(
                  children: [
                    LucideIcon(MusicIcons.note, size: 16, color: AppTheme.teal),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Muziek gestopt',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text,
                      ),
                    ),
                    Semantics(
                      button: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onUndo,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                          child: Text(
                            'Ongedaan maken',
                            style: text.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.teal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
