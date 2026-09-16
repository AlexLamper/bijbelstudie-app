/// What Pro unlocks, as (title, body) pairs.
///
/// One list for every surface that names the benefits - the paywall sells
/// them and the post-purchase celebration confirms them - so the welcome
/// screen can never promise something the paywall did not.
const List<(String, String)> kProBenefits = [
  ('Offline lezen', 'Bewaar hele bijbelboeken op je toestel en lees zonder verbinding.'),
  ('Alle commentaren', 'Matthew Henry en Dachsel bij elk hoofdstuk.'),
  ('Grondtekst', 'Hebreeuws en Grieks met transliteratie en Strong-nummers.'),
  // Not "Onbeperkt notities": the app's /api/v1 notes have no free limit, so
  // selling that would be a paid benefit free readers already have - exactly
  // what store review rejects as a misleading subscription.
  ('Meer AI-vragen', 'Tot 200 vragen per dag in plaats van 5.'),
];
