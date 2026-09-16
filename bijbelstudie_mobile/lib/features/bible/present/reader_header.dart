import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../commentary/present/commentary_jump.dart';
import '../../study/present/study_pane_controller.dart';
import 'bible_providers.dart';
import 'source_picker_sheet.dart';

/// The first row of the header both halves of `/studie` share: where you are,
/// and which half you are looking at.
///
/// The Bijbel ⇄ Studie switch used to be a full-width two-button bar of its own
/// above the panes, which cost 48px of reading height on every chapter. Folded
/// in beside the chapter title it costs nothing, and the title stays the first
/// thing on the screen.
class ReaderTitleBar extends ConsumerWidget {
  const ReaderTitleBar({
    super.key,
    required this.showMaterials,
    this.embedded = true,
  });

  /// Which segment reads as active. Only meaningful when [embedded] is true -
  /// see below.
  final bool showMaterials;

  /// True inside `/studie`, where both panes exist and the switch only flips
  /// [studyPaneProvider]. False for the standalone reader at `/read`, which
  /// has to go to `/studie` to show the other half.
  ///
  /// [studyPaneProvider] is global and sticky: leaving `/studie` on the
  /// Studie pane and then opening `/read` (e.g. from a note) would otherwise
  /// carry that flag over and light up "Studie" on a screen that is plainly
  /// showing bible text. `/read` IS the bible, so when not embedded this
  /// widget ignores [showMaterials] and always reads as "Bijbel" - tapping
  /// "Studie" still navigates to `/studie` as before.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final location = ref.watch(readerLocationProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Only the chapter: the translation has its own pill in the Bijbel
        // tool row, and a subtitle here would make this row taller than the
        // same row on the Studie side.
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showBookPickerSheet(context, ref),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Semantics(
                header: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        '${location.book} ${location.chapter}',
                        style: AppTheme.displayTitle.copyWith(
                          fontSize: 19,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 15,
                      color: AppTheme.inkMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        AppSegmentedControl(
          labels: const ['Bijbel', 'Studie'],
          selectedIndex: embedded && showMaterials ? 1 : 0,
          onChanged: (index) {
            final controller = ref.read(studyPaneProvider.notifier);
            if (index == 0) {
              controller.showReader();
              return;
            }
            // Line the commentary up with where the reader is - only if the
            // reader moved since the last time, so flipping back and forth
            // never pulls the commentary away from where it was left.
            if (!(embedded && showMaterials)) {
              ref.read(pendingCommentaryVerseProvider.notifier).syncToReader();
            }
            controller.showMaterials();
            // The standalone reader has no materials pane to reveal, so the
            // switch is the way into the split screen rather than a toggle.
            if (!embedded) context.push('/study');
          },
        ),
      ],
    );
  }
}
