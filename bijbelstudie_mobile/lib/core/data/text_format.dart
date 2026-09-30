/// Text tidying applied to anything the app did not author itself.
///
/// The app never shows an em dash. Two sources can still produce one: the
/// public-domain commentary texts, which use it freely, and an API response
/// cached before `lib/mobileAttribution.ts` on the server dropped it. Folding
/// it at the point of parsing is what makes the rule hold offline as well.
///
/// The en dash is folded too, so year ranges such as `(1662-1714)` and verse
/// ranges read with a plain hyphen.
String normaliseDashes(String input) =>
    input.replaceAll(RegExp('[—–]'), '-');
