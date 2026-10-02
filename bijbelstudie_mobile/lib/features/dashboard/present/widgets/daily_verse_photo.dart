import 'package:flutter/material.dart';

/// How many photos ship in `assets/images/daytext/` (`001.jpg` .. `365.jpg`),
/// one for every day of the year, so a date never shares its photo with
/// another date in the same year. Pexels photos under the Pexels License;
/// see `CREDITS.md` beside them.
const int kDailyVersePhotoCount = 365;

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

/// Pexels photo ids of `001.jpg` .. `365.jpg`, in order (see `CREDITS.md`).
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
  28911994, 29266778, 31503146, 30923401, 37040051, 27990818, 10875403,
  39931367, 23533506, 9499494, 2106223, 5098216, 35382332, 30520816, 13464740,
  29158480, 30907310, 9076557, 28578392, 11089921, 34387507, 13258030,
  12346372, 14635958, 36576221, 35285739, 36671721, 37438599, 11681893,
  33931095, 7753797, 9893930, 30169843, 29379998, 16252909, 28310049, 38351370,
  29233617, 7350421, 3970396, 20775830, 39256732, 5331819, 12573635, 11584779,
  28458012, 6746531, 5799234, 16549060, 3708615, 15589144, 34238085, 12997071,
  30016151, 34346941, 37040538, 18508975, 38439383, 2844093, 12838041,
  13624070, 8042541, 16625681, 28986376, 28448927, 11467524, 34084660,
  11326620, 11438879, 10764293, 17914589, 38602784, 29147668, 29061547,
  37827591, 8933075, 28840873, 14383012, 10770234, 30016586, 18368730,
  24354631, 29370023, 19684175, 35637269, 38399970, 36526787, 37200096,
  10150958, 39862888, 30234960, 37109411, 30027590, 17129553, 34649171,
  7349658, 9185457, 32944972, 34598771, 36899229, 16047659, 39411381, 4671685,
  14714994, 7694094, 36819700, 12981951, 39128521, 12109209, 36136865,
  18555425, 12051619, 4527358, 21207375, 20607392, 18536420, 20516335,
  36197331, 29256713, 31341658, 38335940, 9058167, 8964331, 39812815, 14868838,
  38741825, 8890414, 6713233, 19269744, 11634399, 35220061, 14636481, 35421363,
  15261000, 11870605, 38706146, 13433980, 28849092, 21370639, 34649187,
  4930098, 9229410, 27906665, 39001350, 18863547, 11478118, 19847520, 19884626,
  17193060, 13049618, 34219275, 4859369, 8869239, 39622641, 5481584, 30737706,
  12193744, 35836385, 37747907, 18501117, 9202125, 36012566, 13714888,
  11689598, 14374226, 35317870, 26180308, 10336022, 31904923, 26583128,
  20517613, 10097506, 33542243, 1128124, 12611725, 11200685, 18642592,
  12650858, 13492114, 38877853, 6635906, 11301701, 30860985, 32827065,
  37919727, 31633139, 35842324, 38267729, 6535173, 8850213, 26417214, 8869343,
  33999892, 16545416, 14746532, 15667736, 4339340, 7967164, 13049879, 15475948,
  14891612, 38678806, 27996748, 13563699, 13695930, 29162225, 31787510,
  15008603, 34346947, 37082289, 5939945, 19997290, 28883730, 34567444, 8180041,
  19151778, 38175109, 33841560, 39595856, 33393870, 19062959, 29006541,
  8013906, 33274752, 9152297, 30929497, 29640753, 33693757, 14424044, 8849682,
  39824929, 10819643, 6866472, 15273857, 16831874, 15871346, 15213885,
  11332049, 32561223, 19537994, 12256489, 8469661, 18141981, 7978381, 17173413,
  15778112, 632327, 33072120, 16475310, 20216412, 33561762, 25392043, 28915987,
  25185015, 36096732, 11873090, 20257729, 16277830, 12640196, 15485704,
  33783265, 33484257, 28485435, 35880543, 6145533, 36969109,
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
