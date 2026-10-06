/// Which translations a reader may carry out of the app, and how much.
///
/// The website's `lib/bibleCopyPolicy.ts` is the same file in TypeScript and
/// carries the full reasoning; the short version:
///
///   - Public-domain text (Statenvertaling, Canisius, De Heilige Schrift 1917,
///     KJV, ASV, WEB, Geneva, Coverdale) may be taken by the bucket. There is
///     no rights holder to ask, and nothing here restricts it.
///   - Licensed text may be read, and may be quoted a verse at a time, because
///     that is what a Bible reader does. It may not leave in chapter-sized
///     lumps: that is redistribution, and no licence we hold covers it.
///
/// In this app the limit costs the reader very little, because the reader
/// already cannot select scripture with a cursor: the verses in `read_screen`
/// are plain `Text.rich`, never `SelectableText` and never inside a
/// `SelectionArea`. **Keep it that way for restricted translations.** What this
/// file guards are the paths that hand text out deliberately:
///
///   - the verse sheet's "Kopiëren" row, which copies [maxCopyVerses] verse
///     with its reference and the translation's attribution - allowed, and the
///     reason the restriction is not a loss,
///   - whole-chapter share (`ChapterContent.shareText`), which for a restricted
///     translation returns null so the caller shares the reference and a link
///     instead of the words,
///   - the bulk offline download, which would put a whole book on the device.
///
/// ── Who decides ─────────────────────────────────────────────────────────────
///
/// The server does. Every bible chapter envelope carries `copyRestricted`, and
/// [ChapterContent.copyRestricted] prefers it over the list below, so a
/// translation the website restricts tomorrow is restricted in this build
/// without a release. The list is the fallback for a cached chapter stored
/// before the field existed, and the answer for screens that have an id but no
/// envelope (the offline download button, the source picker).
///
/// Builds too old to read the field at all never see these translations: the
/// client sends `X-Bs-Capabilities: copy-guard` (see `ApiClient`) and the API
/// only lists and serves a restricted translation to a request that carries it.
library;

/// How many verses a copy or share may put out at once.
const int maxCopyVerses = 1;

/// Header the client sends to say it honours this policy.
const String capabilitiesHeader = 'X-Bs-Capabilities';

/// The one capability named in that header today.
const String copyGuardCapability = 'copy-guard';

/// Bible version ids whose text may not be copied or shared in bulk.
///
/// Mirror of `RESTRICTED_BIBLE_IDS` in the website's `lib/bibleCopyPolicy.ts`,
/// including the spelling variants that exist because the data has not landed
/// yet. Exact match only - no case folding, no trimming, no aliases.
///
///   hsv                       Herziene Statenvertaling, (c) Stichting HSV.
///   statenvertaling_jongbloed Statenvertaling, Jongbloed-editie. The 1637 text
///                             is public domain; this edition is licensed. Not
///                             the same id as plain `statenvertaling`, which
///                             stays freely copyable.
///   ebv24                     EBV24, (c) its publisher.
const Set<String> restrictedBibleIds = {
  'hsv',
  'statenvertaling_jongbloed',
  'statenvertaling-jongbloed',
  'sv_jongbloed',
  'jongbloed',
  'ebv24',
  'ebv_24',
  'ebv-24',
  'ebv',
};

/// True when [versionId] is a translation that may not be copied wholesale.
bool isCopyRestricted(String? versionId) {
  if (versionId == null || versionId.isEmpty) return false;
  return restrictedBibleIds.contains(versionId);
}

/// Said once, where a reader runs into the limit. Names what is allowed first,
/// because that is the part they came for.
const String copyRestrictedNotice =
    'Deze vertaling is auteursrechtelijk beschermd. Je kunt losse verzen '
    'kopiëren; de hele tekst overnemen mag niet.';

/// Snackbar-length version of the same sentence.
const String copyRestrictedNoticeShort =
    'Van deze vertaling kun je losse verzen kopiëren, niet de hele tekst.';

/// Why the offline download is missing on a restricted translation.
const String copyRestrictedOfflineNotice =
    'Deze vertaling mag niet als heel boek op je toestel worden opgeslagen.';

/// What a copy puts on the clipboard: the words, then the reference and the
/// attribution. The attribution travels with the text - for a licensed
/// translation the citation is the condition the quotation rests on.
String formatVerseForCopy({
  required String text,
  required String reference,
  String? attribution,
}) {
  final cited = (attribution == null || attribution.isEmpty)
      ? reference
      : '$reference - $attribution';
  return '${text.trim()}\n\n$cited';
}
