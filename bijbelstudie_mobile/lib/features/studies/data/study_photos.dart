/// A study's cover photograph.
///
/// Mirrors `lib/studyPhotos.ts` in the website repo entry for entry: every
/// study in the catalogue - the 66 book studies and the authored person,
/// passage and theme studies - has one real landscape or still-life photograph
/// chosen for its subject, and no two studies share one. Both platforms must
/// agree, so when the website adds or swaps an entry, copy the line here and
/// copy both files from `public/images/study-photos/` into
/// `assets/images/study-photos/`. `test/study_photos_test.dart` keeps every
/// entry backed by both files.
///
/// The files are bundled rather than fetched, like the dagtekst library once
/// was: a card paints its photo on the first frame, offline included, and the
/// app never depends on a website deploy for a picture. They are the website's
/// own files, unchanged:
///   `u-<id>.webp`     800 px wide, q70 (banners, the detail header)
///   `u-<id>-sm.webp`  240 x 240 crop, q70 (square list thumbnails)
///
/// Licence: Unsplash License (free for commercial use, no attribution
/// required - credited in the comments anyway). Unsplash+ / `premium_photo`
/// results are a different, restricted licence and must never be added.
library;

/// Study id -> Unsplash photo id. Comment: what it shows - photographer.
const Map<String, String> kStudyPhotos = {
  // null
  'boek-genesis': 'K2jUGU6ttO0',
  // null
  'boek-exodus': 'pIL6duZR3yM',
  // null
  'boek-leviticus': 'AaZlf5FgUws',
  // null
  'boek-numeri': '-EJEaytR9fw',
  // null
  'boek-deuteronomium': 'QakqNbgJqwI',
  // null
  'boek-jozua': 'HmNWXPzRx1M',
  // null
  'boek-richteren': '3amCorLRlPk',
  // null
  'boek-ruth': 'aEJP6b-VMxY',
  // null
  'boek-1-samuel': 'dkrvlD1UC2s',
  // null
  'boek-2-samuel': 'hvMsIEo3CW0',
  // null
  'boek-1-koningen': '87IVr1pjoPM',
  // null
  'boek-2-koningen': 'P2Jr9B3J_MQ',
  // null
  'boek-1-kronieken': 'xUXGHzhIbN4',
  // null
  'boek-2-kronieken': '7a79GN3AZMM',
  // null
  'boek-ezra': 'JGp4wwYqM78',
  // null
  'boek-nehemia': 'se80dJ1xN6A',
  // null
  'boek-esther': 'L45JVcMegCg',
  // null
  'boek-job': 'I0X7BkEkCWk',
  // null
  'boek-psalmen': '9CfajiGQL0o',
  // null
  'boek-spreuken': '5bzMOpMTDRM',
  // null
  'boek-prediker': 'RwHv7LgeC7s',
  // null
  'boek-hooglied': '0AgtPoAARtE',
  // null
  'boek-jesaja': 'Vv1VCU6GcVM',
  // null
  'boek-jeremia': 'HQOA0LA91As',
  // null
  'boek-klaagliederen': 'MY4jRyrUZdQ',
  // null
  'boek-ezechiel': 'U_emIOrVQBY',
  // null
  'boek-hosea': '3TmLV0fLzfU',
  // null
  'boek-joel': 'EzJQlDo3oCk',
  // null
  'boek-amos': 'SqrZCO21V-Y',
  // null
  'boek-obadja': 'JnnOcB75lLs',
  // null
  'boek-jona': 'qKlD2QlK-CY',
  // null
  'boek-micha': '_6d1KujNzug',
  // null
  'boek-nahum': 'AdOeV-qlAs4',
  // null
  'boek-habakuk': 'pVV39dmFCEE',
  // null
  'boek-zefanja': 'jTcw4VlP-ac',
  // null
  'boek-haggai': '-3QVdNHz1AI',
  // null
  'boek-zacharia': '6gFxye8SVoY',
  // null
  'boek-maleachi': 'hpI18Ca87aE',
  // null
  'boek-mattheus': 'RzV8XqB7QT0',
  // null
  'boek-markus': 'Us_dv71f1bc',
  // null
  'boek-lukas': 'HiE1bIIoRqQ',
  // null
  'boek-johannes': 'gBdG886bLDY',
  // null
  'boek-handelingen': 'QYAojSRu82c',
  // null
  'boek-romeinen': 'bB6pr94w_EA',
  // null
  'boek-1-corinthiers': 'nESI7TqYBto',
  // null
  'boek-2-corinthiers': 'OVpUFAvwhNA',
  // null
  'boek-galaten': 'sBzqwzcY4tY',
  // null
  'boek-efeziers': 'WClG5w6GC9I',
  // null
  'boek-filippenzen': 'zUytXs3fusw',
  // null
  'boek-colossenzen': 'MskbR8VLNrA',
  // null
  'boek-1-thessalonicenzen': 'nv7WX42LKjU',
  // null
  'boek-2-thessalonicenzen': 'SHA85I0G8K4',
  // null
  'boek-1-timotheus': 'SDa3foPsj5o',
  // null
  'boek-2-timotheus': 'b3D8BfG1L8Y',
  // null
  'boek-titus': 'Qmhvd2LoKEc',
  // null
  'boek-filemon': 'yG1mlQ1Rqpc',
  // null
  'boek-hebreeen': 'iupXZ62DQBY',
  // null
  'boek-jakobus': 'lKILWySmEHs',
  // null
  'boek-1-petrus': 'Xne1N4yZuOY',
  // null
  'boek-2-petrus': 'pmUEwPKL5IE',
  // null
  'boek-1-johannes': 'xhD49fKOzw0',
  // null
  'boek-2-johannes': '74TufExdP3Y',
  // null
  'boek-3-johannes': '4SvxBUfT-_c',
  // null
  'boek-judas': 'IzsVq4gwQO4',
  // null
  'boek-openbaring': 'RbbdzZBKRDY',
  // null
  'opstanding': 'U9BStwKrP2c',
  // null
  'abraham': '6KQETG8J-zI',
  // null
  'mozes': 'RGR-7-G4Wvs',
  // null
  'geloof-in-storm': 'BLeKlh5je6k',
  // null
  'noach': 't02XukS9dUU',
  // null
  'intocht': 'TMxUnMAAwFA',
  // null
  'david': 'DNnxRx9Vkb4',
  // null
  'bergrede': 'EYyD5ZrxJpo',
  // null
  'paulus': '06BkQ54A3Zo',
  // null
  'psalmen': 'fps3SRiQqoQ',
  // null
  'daniel': 'hesJq5WhaSA',
};

/// The two bundled files behind one study's photograph.
class StudyPhoto {
  const StudyPhoto({required this.banner, required this.thumb});

  /// The 800 px banner asset.
  final String banner;

  /// The 240 px square thumbnail asset.
  final String thumb;
}

const String kStudyPhotoDir = 'assets/images/study-photos';

/// The photo for [studyId], or null when it has none and the painted banner
/// should show.
StudyPhoto? studyPhotoFor(String studyId) {
  final id = kStudyPhotos[studyId];
  if (id == null) return null;
  return StudyPhoto(
    banner: '$kStudyPhotoDir/u-$id.webp',
    thumb: '$kStudyPhotoDir/u-$id-sm.webp',
  );
}
