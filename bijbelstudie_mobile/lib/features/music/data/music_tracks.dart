import '../domain/music_models.dart';

/// The six sounds, in picker order. The order is also the index the player
/// state uses, so append rather than reorder.
///
/// The recordings come from Wikimedia Commons, each checked to be public
/// domain or CC0, and were prepared once by hand: silence trimmed, levelled to
/// -20 LUFS (music) and -24 LUFS (nature, which should sit further back),
/// music faded in and out so the loop point is soft, nature cross-faded into
/// its own start so the loop has no seam. AAC in .m4a, about 9 MB for all six.
const List<MusicTrack> kMusicTracks = [
  MusicTrack(
    id: 'stille_piano',
    name: 'Stille piano',
    category: MusicCategory.music,
    subtitle: 'Piano · zacht en traag',
    iconPaths: '<path d="M3 5h18v14H3z"/><path d="M8 5v8"/><path d="M12 5v14"/>'
        '<path d="M16 5v8"/>',
    asset: 'music/stille_piano.m4a',
    credit: MusicCredit(
      work: 'J.S. Bach - Prelude in C (BWV 846)',
      performer: 'Kimiko Ishizaka',
      licence: 'CC0',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Kimiko_Ishizaka_-_Bach_-_'
          'Well-Tempered_Clavier,_Book_1_-_01_Prelude_No._1_in_C_major,_BWV_846.ogg',
    ),
  ),
  MusicTrack(
    id: 'regen',
    name: 'Regen',
    category: MusicCategory.nature,
    subtitle: 'Natuur · zachte regen',
    iconPaths:
        '<path d="M7 15a4 4 0 0 1-.6-7.95A5.5 5.5 0 0 1 17 7.5a3.75 3.75 0 0 1 .5 7.5z"/>'
        '<path d="M8 18l-1 2.5"/><path d="M12 18l-1 2.5"/><path d="M16 18l-1 2.5"/>',
    asset: 'music/regen.m4a',
    credit: MusicCredit(
      work: 'Regen tegen het raam',
      performer: 'cori',
      licence: 'Publiek domein',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Rain_against_the_window.ogg',
    ),
  ),
  MusicTrack(
    id: 'strijkers',
    name: 'Strijkers',
    category: MusicCategory.music,
    subtitle: 'Ensemble · warme strijkers',
    iconPaths: '<path d="M3 12h2"/><path d="M7 8v8"/><path d="M11 5v14"/>'
        '<path d="M15 8v8"/><path d="M19 10v4"/>',
    asset: 'music/strijkers.m4a',
    credit: MusicCredit(
      work: 'J.S. Bach - Air (BWV 1068)',
      performer: 'Air Force Strings, United States Air Force Band',
      licence: 'Publiek domein',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Air_-_Air_Force_Strings_-_'
          'United_States_Air_Force_Band.mp3',
    ),
  ),
  MusicTrack(
    id: 'akoestisch',
    name: 'Akoestisch',
    category: MusicCategory.music,
    subtitle: 'Gitaar · fingerpicking',
    iconPaths: '<path d="M12 3v9"/><path d="M10 3h4"/>'
        '<path d="M12 12a4.5 4.5 0 1 0 0 9 4.5 4.5 0 0 0 0-9z"/><path d="M12 16.5h.01"/>',
    asset: 'music/akoestisch.m4a',
    credit: MusicCredit(
      work: 'Erik Satie - Gymnopédie nr. 1',
      performer: 'Michael Laucke',
      licence: 'Publiek domein',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Satie_Gymnopedie_No_1_'
          'performed_by_Michael_Laucke.flac',
    ),
  ),
  MusicTrack(
    id: 'beek',
    name: 'Beek in het bos',
    category: MusicCategory.nature,
    subtitle: 'Natuur · stromend water',
    iconPaths: '<path d="M3 9c2 0 2.5-2 4.5-2S10 9 12 9s2.5-2 4.5-2S19 9 21 9"/>'
        '<path d="M3 15c2 0 2.5-2 4.5-2S10 15 12 15s2.5-2 4.5-2S19 15 21 15"/>',
    asset: 'music/beek.m4a',
    credit: MusicCredit(
      work: 'Zacht stromende beek',
      performer: 'jackthemurray',
      licence: 'CC0',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:433589_jackthemurray_'
          'stream-river-water-up-close.wav',
    ),
  ),
  MusicTrack(
    id: 'orgel',
    name: 'Orgel',
    category: MusicCategory.music,
    subtitle: 'Orgel · ingetogen',
    iconPaths: '<path d="M5 20v-8"/><path d="M9 20V8"/><path d="M12 20V4"/>'
        '<path d="M15 20V8"/><path d="M19 20v-8"/><path d="M3 20h18"/>',
    asset: 'music/orgel.m4a',
    credit: MusicCredit(
      work: 'J.S. Bach - Ich ruf zu dir, Herr Jesu Christ (BWV 639)',
      performer: 'Yeonju Sarah Kim, opname Flo Sorg',
      licence: 'CC0',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Heilig-Geist-Orgel_-_J_S_Bach-_'
          'Ich_ruf_zu_dir,_Herr_Jesu_Christ_BWV_639,_gespielt_von_Yeonju_Sarah_Kim,_'
          'Registrierung_u_a_Cornet_2_2_3%E2%80%B2_-_Teilausschnitt_aus_STE-015.ogg',
    ),
  ),
];
