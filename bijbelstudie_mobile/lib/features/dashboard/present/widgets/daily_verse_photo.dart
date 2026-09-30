import 'package:flutter/material.dart';

/// How many photos ship in `assets/images/daytext/` (`001.jpg` .. `100.jpg`).
/// Pexels photos under the Pexels License; see `CREDITS.md` beside them.
const int kDailyVersePhotoCount = 100;

/// The photo for a day, from its `yyyymmdd` key (`VerseScene.key`).
///
/// Picked from the calendar day rather than at random, so the card, the full
/// screen view and the share image all show the same photo, it stays put
/// across rebuilds and it changes from one day to the next.
String dailyVersePhotoAsset(String dayKey) {
  var index = 0;
  if (dayKey.length == 8) {
    final year = int.tryParse(dayKey.substring(0, 4));
    final month = int.tryParse(dayKey.substring(4, 6));
    final day = int.tryParse(dayKey.substring(6, 8));
    if (year != null && month != null && day != null) {
      final days = DateTime.utc(year, month, day)
          .difference(DateTime.utc(1970))
          .inDays;
      index = days % kDailyVersePhotoCount;
    }
  }
  return 'assets/images/daytext/${(index + 1).toString().padLeft(3, '0')}.jpg';
}

/// The day's photo, cover-cropped, under a light wash of its own.
///
/// The photos are picked mid-bright rather than dark, so this wash (on top of
/// whatever scrim the caller lays over everything) is what keeps white text
/// readable on the lightest skies and dunes.
class DailyVersePhoto extends StatelessWidget {
  const DailyVersePhoto({super.key, required this.dayKey});

  /// `yyyymmdd`, see [dailyVersePhotoAsset].
  final String dayKey;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          dailyVersePhotoAsset(dayKey),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF3B4A52)),
        ),
        const ColoredBox(color: Color(0x2E000000)),
      ],
    );
  }
}
