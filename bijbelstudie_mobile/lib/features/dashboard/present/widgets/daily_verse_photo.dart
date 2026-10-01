import 'package:flutter/material.dart';

/// How many photos ship in `assets/images/daytext/` (`001.jpg` .. `100.jpg`).
/// Pexels photos under the Pexels License; see `CREDITS.md` beside them.
const int kDailyVersePhotoCount = 100;

/// Which of the [kDailyVersePhotoCount] photos a `yyyymmdd` key gets, 0-based.
///
/// Picked from the calendar day rather than at random, so the card, the full
/// screen view and the share image all show the same photo, it stays put
/// across rebuilds and it changes from one day to the next.
int _photoIndex(String dayKey) {
  if (dayKey.length != 8) return 0;
  final year = int.tryParse(dayKey.substring(0, 4));
  final month = int.tryParse(dayKey.substring(4, 6));
  final day = int.tryParse(dayKey.substring(6, 8));
  if (year == null || month == null || day == null) return 0;
  final days = DateTime.utc(year, month, day)
      .difference(DateTime.utc(1970))
      .inDays;
  return days % kDailyVersePhotoCount;
}

/// The photo for a day, from its `yyyymmdd` key (`VerseScene.key`).
String dailyVersePhotoAsset(String dayKey) =>
    'assets/images/daytext/${(_photoIndex(dayKey) + 1).toString().padLeft(3, '0')}.jpg';

/// Pexels photo ids of `001.jpg` .. `100.jpg`, in order (see `CREDITS.md`).
const List<int> _pexelsIds = [
  15946482, 17361969, 33383932, 33306222, 15008544, 14464006, 6441066,
  19405179, 38478448, 4761770, 32663258, 37919725, 4366005, 38281045, 34741061,
  29111511, 11975905, 14567482, 15649037, 19173219, 6752437, 11186965, 4577838,
  11954778, 13476143, 17573933, 35634614, 12764452, 28963174, 16256013,
  19190939, 11370583, 14588370, 31496288, 10513109, 17789895, 9315369, 9007462,
  31742157, 11946207, 38231313, 706504, 11879413, 13415498, 6916172, 15213897,
  4052678, 26830924, 8937434, 10939816, 8602485, 10843693, 9910835, 5585183,
  21317429, 27212780, 33741719, 12276699, 14160422, 30289677, 7849814,
  14297554, 23825970, 24033314, 14741180, 16128143, 10480067, 13025019,
  9910886, 15448430, 19984922, 33316092, 5671012, 9325480, 17727442, 29585513,
  23383399, 4555136, 9982813, 15475873, 15442009, 12141495, 35752257, 37150651,
  4324351, 14641667, 1018805, 17146246, 36518548, 27597952, 17386270, 34349413,
  22940234, 36766325, 38778411, 29218798, 22710670, 32987899, 10116436,
  28911994,
];

/// The same photo as [dailyVersePhotoAsset], straight from the Pexels CDN at
/// [width] x [height] pixels, centre-cropped. The bundled copies are 900x1200
/// at q65, fine for a card but soft when blown up to a full-screen status
/// image; the share image fetches this instead and falls back to the asset.
Uri dailyVersePhotoUrl(String dayKey, {required int width, required int height}) {
  final id = _pexelsIds[_photoIndex(dayKey)];
  return Uri.https('images.pexels.com', '/photos/$id/pexels-photo-$id.jpeg', {
    'cs': 'srgb',
    'fit': 'crop',
    'w': '$width',
    'h': '$height',
  });
}

/// The day's photo, cover-cropped, under a light wash of its own.
///
/// The photos are picked mid-bright rather than dark, so this wash (on top of
/// whatever scrim the caller lays over everything) is what keeps white text
/// readable on the lightest skies and dunes.
class DailyVersePhoto extends StatelessWidget {
  const DailyVersePhoto({super.key, required this.dayKey, this.image});

  /// `yyyymmdd`, see [dailyVersePhotoAsset].
  final String dayKey;

  /// Overrides the bundled asset; the share image passes the full-size copy.
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: image ?? AssetImage(dailyVersePhotoAsset(dayKey)),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: image == null
              ? FilterQuality.medium
              : FilterQuality.high,
          errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF3B4A52)),
        ),
        const ColoredBox(color: Color(0x2E000000)),
      ],
    );
  }
}
