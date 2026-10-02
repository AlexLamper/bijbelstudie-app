/// What Pro unlocks, as (title, body) pairs.
///
/// One list for every surface that names the benefits - the paywall sells
/// them and the post-purchase celebration confirms them - so the welcome
/// screen can never promise something the paywall did not.
const List<(String, String)> kProBenefits = [
  ('Offline lezen', 'Bewaar hele bijbelboeken op je toestel en lees zonder verbinding.'),
  ('Alle commentaren', 'Matthew Henry en Dachsel bij elk hoofdstuk.'),
  ('Grondtekst', 'De originele tekst in het Hebreeuws en Grieks, woord voor woord.'),
  ('Meer AI-vragen', 'Tot 200 vragen per dag in plaats van 3.'),
  // The free limit is real and server-side: `FREE_NOTE_LIMIT = 10` in the
  // website repo's `lib/entitlements.ts`, refused with `NOTE_LIMIT_REACHED`
  // on `/api/v1` as well as the web routes. This benefit was once left out on
  // the premise that /api/v1 notes were unlimited, which made the app promise
  // "onbeperkt notities" at the limit and then never mention notes on the
  // paywall the reader landed on.
  //
  // Only *writing a note* is limited - highlights and study answers do not
  // count, and existing notes above the limit stay readable and editable - so
  // the body says notes and nothing wider.
  ('Onbeperkt notities', 'Schrijf er zoveel als je wilt, in plaats van 10.'),
];
