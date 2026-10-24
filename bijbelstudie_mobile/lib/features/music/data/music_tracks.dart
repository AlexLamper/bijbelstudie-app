import '../../../core/config/app_config.dart';
import '../domain/music_models.dart';

/// Every track, grouped by playlist: piano, lofi, organ. The order within a
/// playlist is the order it plays in; the list index is what the player state
/// holds and the id is what is persisted, so ids never change.
///
/// Piano and organ come from Wikimedia Commons and the Internet Archive, the
/// lofi from HoliznaCC0 on the Free Music Archive; each licence (public domain,
/// CC0 or CC BY) was checked on the page in its credit. Prepared once by hand:
/// silence trimmed, faded in and out, levelled to -20 LUFS (lofi -19), AAC
/// 96 kbps in .m4a. One track per playlist ships in `assets/music/`; the rest
/// stream from the site's `public/audio/` (the website repo).
const List<MusicTrack> kMusicTracks = [
  MusicTrack(
    id: 'piano_bach_prelude_c',
    title: 'Prelude in C',
    artist: 'J.S. Bach',
    category: MusicCategory.piano,
    file: 'piano_bach_prelude_c.m4a',
    bundled: true,
    credit: MusicCredit(
      performer: 'Kimiko Ishizaka',
      licence: 'CC0',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Kimiko_Ishizaka_-_Bach_-_Well-'
          'Tempered_Clavier,_Book_1_-_01_Prelude_No._1_in_C_major,_BWV_846.ogg',
    ),
  ),
  MusicTrack(
    id: 'piano_satie_gymnopedie_1',
    title: 'Gymnopédie No. 1',
    artist: 'Erik Satie',
    category: MusicCategory.piano,
    file: 'piano_satie_gymnopedie_1.m4a',
    credit: MusicCredit(
      performer: 'Robin Alciatore (Musopen)',
      licence: 'Publiek domein',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Erik_Satie_-_gymnopedies_-'
          '_la_1_ere._lent_et_douloureux.ogg',
    ),
  ),
  MusicTrack(
    id: 'piano_bach_goldberg_aria',
    title: 'Aria (Goldberg-Variationen)',
    artist: 'J.S. Bach',
    category: MusicCategory.piano,
    file: 'piano_bach_goldberg_aria.m4a',
    credit: MusicCredit(
      performer: 'Kimiko Ishizaka',
      licence: 'CC0',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Kimiko_Ishizaka_-_01_-_Aria.ogg',
    ),
  ),
  MusicTrack(
    id: 'piano_debussy_clair_de_lune',
    title: 'Clair de lune (Suite bergamasque)',
    artist: 'Claude Debussy',
    category: MusicCategory.piano,
    file: 'piano_debussy_clair_de_lune.m4a',
    credit: MusicCredit(
      performer: 'Laurens Goedhart',
      licence: 'CC BY 3.0',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Clair_de_lune_(Claude_Debussy)_'
          'Suite_bergamasque.ogg',
    ),
  ),
  MusicTrack(
    id: 'piano_chopin_nocturne_op9_2',
    title: 'Nocturne in Es',
    artist: 'Frédéric Chopin',
    category: MusicCategory.piano,
    file: 'piano_chopin_nocturne_op9_2.m4a',
    credit: MusicCredit(
      performer: 'Frank Lévy (Musopen)',
      licence: 'Publiek domein',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Chopin_-_Nocturne_No._2_in_'
          'E-flat_major,_Op._9_No._2_(Frank_Levy).flac',
    ),
  ),
  MusicTrack(
    id: 'piano_schumann_traumerei',
    title: 'Träumerei (Kinderszenen)',
    artist: 'Robert Schumann',
    category: MusicCategory.piano,
    file: 'piano_schumann_traumerei.m4a',
    credit: MusicCredit(
      performer: 'Musopen',
      licence: 'Publiek domein',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Robert_Schumann_-_scenes_from_'
          'childhood,_op._15_-_vii._dreaming.ogg',
    ),
  ),
  MusicTrack(
    id: 'piano_beethoven_moonlight_1',
    title: 'Mondscheinsonate: I. Adagio sostenuto',
    artist: 'Ludwig van Beethoven',
    category: MusicCategory.piano,
    file: 'piano_beethoven_moonlight_1.m4a',
    credit: MusicCredit(
      performer: 'Paul Pitman (Musopen)',
      licence: 'Publiek domein',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Ludwig_van_Beethoven_-_sonata_'
          'no._14_in_c_sharp_minor_%27moonlight%27,_op._27_no._2_-_i._adagio_'
          'sostenuto.ogg',
    ),
  ),
  MusicTrack(
    id: 'piano_bach_prelude_e_flat_minor',
    title: 'Prelude in es',
    artist: 'J.S. Bach',
    category: MusicCategory.piano,
    file: 'piano_bach_prelude_e_flat_minor.m4a',
    credit: MusicCredit(
      performer: 'Kimiko Ishizaka',
      licence: 'CC0',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Kimiko_Ishizaka_-_Bach_-_Well-'
          'Tempered_Clavier,_Book_1_-_15_Prelude_No._8_in_E-flat_minor,_BWV_853.ogg',
    ),
  ),
  MusicTrack(
    id: 'piano_chopin_nocturne_op72_1',
    title: 'Nocturne in e',
    artist: 'Frédéric Chopin',
    category: MusicCategory.piano,
    file: 'piano_chopin_nocturne_op72_1.m4a',
    credit: MusicCredit(
      performer: 'Luke Faulkner (Musopen)',
      licence: 'Publiek domein',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Chopin_-_Nocturne_No._19_in_'
          'E_minor,_Op._72_No._1_(Luke_Faulkner).flac',
    ),
  ),
  MusicTrack(
    id: 'piano_schubert_d664_andante',
    title: 'Sonate in A: II. Andante',
    artist: 'Franz Schubert',
    category: MusicCategory.piano,
    file: 'piano_schubert_d664_andante.m4a',
    credit: MusicCredit(
      performer: 'Paul Pitman (Musopen)',
      licence: 'Publiek domein',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Schubert_-_Piano_Sonata_No._'
          '13_in_A_major,_D664_-_II._Andante_(Paul_Pitman).flac',
    ),
  ),
  MusicTrack(
    id: 'piano_bach_prelude_b_minor',
    title: 'Prelude in b',
    artist: 'J.S. Bach',
    category: MusicCategory.piano,
    file: 'piano_bach_prelude_b_minor.m4a',
    credit: MusicCredit(
      performer: 'Kimiko Ishizaka',
      licence: 'CC0',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Kimiko_Ishizaka_-_Bach_-_Well-'
          'Tempered_Clavier,_Book_1_-_47_Prelude_No._24_in_B_minor,_BWV_869.ogg',
    ),
  ),
  MusicTrack(
    id: 'piano_chopin_prelude_e_minor',
    title: 'Prélude in e',
    artist: 'Frédéric Chopin',
    category: MusicCategory.piano,
    file: 'piano_chopin_prelude_e_minor.m4a',
    credit: MusicCredit(
      performer: 'Ivan Ilić',
      licence: 'CC BY 3.0',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Ivan_Ili%C4%87-Chopin_Prelude_'
          'Opus_28_n.4.ogg',
    ),
  ),
  MusicTrack(
    id: 'lofi_holizna_morning_coffee',
    title: 'Morning Coffee',
    artist: 'Holizna',
    category: MusicCategory.lofi,
    file: 'lofi_holizna_morning_coffee.m4a',
    bundled: true,
    credit: MusicCredit(
      performer: 'HoliznaCC0',
      licence: 'CC0',
      sourceUrl: 'https://freemusicarchive.org/music/holiznacc0/lo-fi-and-chill/morning-coffee/',
    ),
  ),
  MusicTrack(
    id: 'lofi_holizna_something_in_the_air',
    title: 'Something In the Air',
    artist: 'Holizna',
    category: MusicCategory.lofi,
    file: 'lofi_holizna_something_in_the_air.m4a',
    credit: MusicCredit(
      performer: 'HoliznaCC0',
      licence: 'CC0',
      sourceUrl: 'https://freemusicarchive.org/music/holiznacc0/lo-fi-and-chill/something-'
          'in-the-air/',
    ),
  ),
  MusicTrack(
    id: 'lofi_holizna_a_little_shade',
    title: 'A Little Shade',
    artist: 'Holizna',
    category: MusicCategory.lofi,
    file: 'lofi_holizna_a_little_shade.m4a',
    credit: MusicCredit(
      performer: 'HoliznaCC0',
      licence: 'CC0',
      sourceUrl: 'https://freemusicarchive.org/music/holiznacc0/lo-fi-and-chill/a-little-shade/',
    ),
  ),
  MusicTrack(
    id: 'lofi_holizna_clouds',
    title: 'Clouds',
    artist: 'Holizna',
    category: MusicCategory.lofi,
    file: 'lofi_holizna_clouds.m4a',
    credit: MusicCredit(
      performer: 'HoliznaCC0',
      licence: 'CC0',
      sourceUrl: 'https://freemusicarchive.org/music/holiznacc0/lo-fi-and-chill/clouds-6/',
    ),
  ),
  MusicTrack(
    id: 'lofi_holizna_plants',
    title: 'Plants',
    artist: 'Holizna',
    category: MusicCategory.lofi,
    file: 'lofi_holizna_plants.m4a',
    credit: MusicCredit(
      performer: 'HoliznaCC0',
      licence: 'CC0',
      sourceUrl: 'https://freemusicarchive.org/music/holiznacc0/lo-fi-and-chill/plantsmp3/',
    ),
  ),
  MusicTrack(
    id: 'lofi_holizna_ocean_memory',
    title: 'Ocean Memory',
    artist: 'Holizna',
    category: MusicCategory.lofi,
    file: 'lofi_holizna_ocean_memory.m4a',
    credit: MusicCredit(
      performer: 'HoliznaCC0',
      licence: 'CC0',
      sourceUrl: 'https://freemusicarchive.org/music/holiznacc0/ocean-memory-lo-fi-chill/'
          'ocean-memory/',
    ),
  ),
  MusicTrack(
    id: 'lofi_holizna_roof_tops',
    title: 'Roof Tops',
    artist: 'Holizna',
    category: MusicCategory.lofi,
    file: 'lofi_holizna_roof_tops.m4a',
    credit: MusicCredit(
      performer: 'HoliznaCC0',
      licence: 'CC0',
      sourceUrl: 'https://freemusicarchive.org/music/holiznacc0/summer-air-lo-fi/roof-tops/',
    ),
  ),
  MusicTrack(
    id: 'lofi_holizna_faded_in_the_sunlight',
    title: 'Faded in the Sunlight',
    artist: 'Holizna',
    category: MusicCategory.lofi,
    file: 'lofi_holizna_faded_in_the_sunlight.m4a',
    credit: MusicCredit(
      performer: 'HoliznaCC0',
      licence: 'CC0',
      sourceUrl: 'https://freemusicarchive.org/music/holiznacc0/summer-air-lo-fi/faded-'
          'in-the-sunlight/',
    ),
  ),
  MusicTrack(
    id: 'lofi_holizna_fire_place',
    title: 'Fire Place',
    artist: 'Holizna',
    category: MusicCategory.lofi,
    file: 'lofi_holizna_fire_place.m4a',
    credit: MusicCredit(
      performer: 'HoliznaCC0',
      licence: 'CC0',
      sourceUrl: 'https://freemusicarchive.org/music/holiznacc0/winter-lofi/fire-place/',
    ),
  ),
  MusicTrack(
    id: 'lofi_holizna_first_snow',
    title: 'First Snow',
    artist: 'Holizna',
    category: MusicCategory.lofi,
    file: 'lofi_holizna_first_snow.m4a',
    credit: MusicCredit(
      performer: 'HoliznaCC0',
      licence: 'CC0',
      sourceUrl: 'https://freemusicarchive.org/music/holiznacc0/winter-lofi/first-snowmp3/',
    ),
  ),
  MusicTrack(
    id: 'lofi_holizna_creature_comforts',
    title: 'Creature Comforts',
    artist: 'Holizna',
    category: MusicCategory.lofi,
    file: 'lofi_holizna_creature_comforts.m4a',
    credit: MusicCredit(
      performer: 'HoliznaCC0',
      licence: 'CC0',
      sourceUrl: 'https://freemusicarchive.org/music/holiznacc0/lo-fi-and-chill/creature-'
          'comforts/',
    ),
  ),
  MusicTrack(
    id: 'lofi_holizna_blue_skies',
    title: 'Blue Skies',
    artist: 'Holizna',
    category: MusicCategory.lofi,
    file: 'lofi_holizna_blue_skies.m4a',
    credit: MusicCredit(
      performer: 'HoliznaCC0',
      licence: 'CC0',
      sourceUrl: 'https://freemusicarchive.org/music/holiznacc0/lazy-summer-lofi-1/blue-'
          'skiesmp3/',
    ),
  ),
  MusicTrack(
    id: 'orgel_bach_bwv639',
    title: 'Ich ruf zu dir, Herr Jesu Christ',
    artist: 'J.S. Bach',
    category: MusicCategory.organ,
    file: 'orgel_bach_bwv639.m4a',
    bundled: true,
    credit: MusicCredit(
      performer: 'Yeonju Sarah Kim',
      licence: 'CC0',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Heilig-Geist-Orgel_-_J_S_Bach-'
          '_Ich_ruf_zu_dir,_Herr_Jesu_Christ_BWV_639,_gespielt_von_Yeonju_Sarah_'
          'Kim,_Registrierung_u_a_Cornet_2_2_3%E2%80%B2_-_Teilausschnitt_aus_'
          'STE-015.ogg',
    ),
  ),
  MusicTrack(
    id: 'orgel_bach_bwv622',
    title: 'O Mensch, bewein dein Sünde groß',
    artist: 'J.S. Bach',
    category: MusicCategory.organ,
    file: 'orgel_bach_bwv622.m4a',
    credit: MusicCredit(
      performer: 'Anthony Mark LaMort',
      licence: 'CC BY 3.0',
      sourceUrl: 'https://archive.org/details/OMenschBeweinDeinSuendeGross-Bwv622',
    ),
  ),
  MusicTrack(
    id: 'orgel_schopfer_o_haupt_voll_blut',
    title: 'O Haupt voll Blut und Wunden',
    artist: 'Hans Leo Hassler (melodie)',
    category: MusicCategory.organ,
    file: 'orgel_schopfer_o_haupt_voll_blut.m4a',
    credit: MusicCredit(
      performer: 'Volker Schöpfer',
      licence: 'CC BY 4.0',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Volker_Sch%C3%B6pfer_-_O_Haupt_'
          'voll_Blut_und_Wunden_EG_85.mp3',
    ),
  ),
  MusicTrack(
    id: 'orgel_bach_bwv616',
    title: 'Mit Fried und Freud ich fahr dahin',
    artist: 'J.S. Bach',
    category: MusicCategory.organ,
    file: 'orgel_bach_bwv616.m4a',
    credit: MusicCredit(
      performer: 'Anthony Mark LaMort',
      licence: 'CC BY 3.0',
      sourceUrl: 'https://archive.org/details/TwoVersionsOfJ.s.BachsmitFriedUndFreudIchFahrDahinFrom',
    ),
  ),
  MusicTrack(
    id: 'orgel_buxtehude_auf_meinen_lieben_gott',
    title: 'Auf meinen lieben Gott',
    artist: 'Dieterich Buxtehude',
    category: MusicCategory.organ,
    file: 'orgel_buxtehude_auf_meinen_lieben_gott.m4a',
    credit: MusicCredit(
      performer: 'Anthony Mark LaMort',
      licence: 'CC BY 3.0',
      sourceUrl: 'https://archive.org/details/OrganWorksByKaufmannZachauBoehmBuxtehudeBachelbel',
    ),
  ),
  MusicTrack(
    id: 'orgel_schopfer_o_welt',
    title: 'O Welt, sieh hier dein Leben',
    artist: 'Heinrich Isaac (melodie)',
    category: MusicCategory.organ,
    file: 'orgel_schopfer_o_welt.m4a',
    credit: MusicCredit(
      performer: 'Volker Schöpfer',
      licence: 'CC BY 4.0',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Volker_Sch%C3%B6pfer_-_O_Welt,'
          '_sieh_hier_dein_Leben_EG_84.mp3',
    ),
  ),
  MusicTrack(
    id: 'orgel_walther_herzlich_tut_mich_verlangen',
    title: 'Herzlich tut mich verlangen (Vers 1)',
    artist: 'Johann Gottfried Walther',
    category: MusicCategory.organ,
    file: 'orgel_walther_herzlich_tut_mich_verlangen.m4a',
    credit: MusicCredit(
      performer: 'Anthony Mark LaMort',
      licence: 'CC BY 3.0',
      sourceUrl: 'https://archive.org/details/OrganPiecesByJohannGottfriedWalther',
    ),
  ),
  MusicTrack(
    id: 'orgel_schopfer_herzliebster_jesu',
    title: 'Herzliebster Jesu, was hast du verbrochen',
    artist: 'Johann Crüger (melodie)',
    category: MusicCategory.organ,
    file: 'orgel_schopfer_herzliebster_jesu.m4a',
    credit: MusicCredit(
      performer: 'Volker Schöpfer',
      licence: 'CC BY 4.0',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Volker_Sch%C3%B6pfer_-_Herzliebster_'
          'Jesu_EG_81.mp3',
    ),
  ),
  MusicTrack(
    id: 'orgel_bach_bwv596_largo',
    title: 'Concerto in d (naar Vivaldi): Largo e spiccato',
    artist: 'J.S. Bach / Antonio Vivaldi',
    category: MusicCategory.organ,
    file: 'orgel_bach_bwv596_largo.m4a',
    credit: MusicCredit(
      performer: 'Metzner (Link-Orgel Feuchtwangen)',
      licence: 'CC BY 3.0',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:J.S.Bach_-_Transcription_for_'
          'organ_of_Vivaldi_Concerto_Op._3,_No._11,_BWV_596_%E2%80%93_2._Largo_'
          'spiccato.oga',
    ),
  ),
  MusicTrack(
    id: 'orgel_pachelbel_ach_gott_vom_himmel',
    title: 'Ach Gott, vom Himmel sieh darein',
    artist: 'Johann Pachelbel',
    category: MusicCategory.organ,
    file: 'orgel_pachelbel_ach_gott_vom_himmel.m4a',
    credit: MusicCredit(
      performer: 'Anthony Mark LaMort',
      licence: 'CC BY 3.0',
      sourceUrl: 'https://archive.org/details/OrganWorksByKaufmannZachauBoehmBuxtehudeBachelbel',
    ),
  ),
];

/// What the player loads for [track]: the asset path for a bundled track, the
/// site URL for the rest.
String musicSourceOf(MusicTrack track) =>
    track.bundled ? 'music/${track.file}' : '${AppConfig.siteUrl}/audio/${track.file}';

/// The indexes of [category]'s tracks, in playing order.
List<int> musicPlaylist(MusicCategory category) => [
  for (var i = 0; i < kMusicTracks.length; i++)
    if (kMusicTracks[i].category == category) i,
];

/// The track [step] places from [index] in its own playlist, wrapping round.
int musicStep(int index, int step) {
  final list = musicPlaylist(kMusicTracks[index].category);
  final at = list.indexOf(index);
  return list[(at + step) % list.length];
}

/// The playlist's track that ships with the app, for when streaming fails.
int musicBundledIn(MusicCategory category) =>
    musicPlaylist(category).firstWhere((i) => kMusicTracks[i].bundled);
