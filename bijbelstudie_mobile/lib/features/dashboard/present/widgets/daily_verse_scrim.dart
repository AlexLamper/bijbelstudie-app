import 'package:flutter/material.dart';

import '../../../levensboom/domain/palette.dart' show DayPhase, timeOfDayForHour;

/// The dark wash between photo and text.
///
/// A top-and-bottom gradient keeps the eyebrow and the action row legible over
/// a light patch at either edge. Under it sits a flat layer that follows the
/// clock, because the backdrop does: the painted sky is bright through the
/// day and the white serif washed out over it, while at night the sky is dark
/// enough on its own and more wash would only cost the scene.
///
/// Two layers on purpose. This used to be one [BoxDecoration] with both a
/// `color` and a `gradient`, and a gradient silently replaces the colour - so
/// the flat layer, the part meant to carry contrast, was never painted.
///
/// Daytime composes to roughly 66% dark at the eyebrow, 51% across the middle
/// where the verse sits and 70% behind the action row; night is the gradient
/// alone (50 / 28 / 56).
class DailyVersePhotoScrim extends StatelessWidget {
  const DailyVersePhotoScrim({super.key});

  static double _flatAlpha(DayPhase phase) => switch (phase) {
    DayPhase.day => 0.32,
    DayPhase.dawn || DayPhase.dusk => 0.18,
    DayPhase.night => 0,
  };

  @override
  Widget build(BuildContext context) {
    final flat = _flatAlpha(timeOfDayForHour(DateTime.now().hour));
    return Stack(
      fit: StackFit.expand,
      children: [
        if (flat > 0) ColoredBox(color: Colors.black.withValues(alpha: flat)),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.50),
                Colors.black.withValues(alpha: 0.28),
                Colors.black.withValues(alpha: 0.56),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),
      ],
    );
  }
}
