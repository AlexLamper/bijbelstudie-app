/// Text tidying applied to anything the app did not author itself.
///
/// The app never shows an em dash. Two sources can still produce one: the
/// public-domain commentary texts, which use it freely, and an API response
/// cached before `lib/mobileAttribution.ts` on the server dropped it. Folding
/// it at the point of parsing is what makes the rule hold offline as well.
///
/// The en dash is deliberately left alone - it carries the year ranges in the
/// attributions, e.g. `Matthew Henry (1662-1714)`.
String normaliseDashes(String input) => input.replaceAll('—', '-');
