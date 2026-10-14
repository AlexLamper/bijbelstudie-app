/// Which commentaries a reader may carry out of the app, and which may only be
/// read on the screen they are read on.
///
/// The bible side of the same decision is `features/bible/domain/copy_policy.dart`
/// and that file carries the full reasoning. This is its commentary twin, with
/// one deliberate difference in shape, explained below.
///
/// The corpus the app may show is `MOBILE_ALLOWED_COMMENTARIES` in the
/// website's `lib/mobileLicensing.ts`, four sources:
///
///   - Matthew Henry (d. 1714), Dachsel (d. 1893) and Calvijn - our own
///     translation of the public-domain Calvin Translation Society edition -
///     are public domain. There is no rights holder to ask and nothing here
///     restricts them: they stay selectable and copyable exactly as before.
///   - KingComments (Ger de Koning), (c) Stichting Titus / Uitgeverij Daniel,
///     is not. It is licensed to us for free reading - the licence's own
///     condition is that it stays free for every reader - and for nothing
///     else. Re-cutting it or passing it on is redistribution, and no licence
///     we hold covers that.
///
/// ── Why this file is an allowlist ───────────────────────────────────────────
///
/// `copy_policy.dart` lists what is *restricted*, so an unknown bible id is
/// freely copyable. This file lists what is *free*, so an unknown commentary id
/// is restricted. That inversion is the owner's instruction, in his words:
/// "rather not being able to copy than being able to while not having
/// permission". A commentary added to the corpus tomorrow is therefore
/// read-only in this build until its id is named here, which is the failure
/// that costs nobody anything.
///
/// ── Who decides ─────────────────────────────────────────────────────────────
///
/// The server would, if it said anything. It does not yet: the bible chapter
/// envelope carries `copyRestricted`, but the commentary chapter envelope
/// (`getMobileCommentaryChapter` in the website's `lib/mobileContent.ts`)
/// carries only `id, book, chapter, verses, attribution, updatedAt`, plus the
/// paywall's `locked`. Its own type comment says the field is read as "true
/// means restricted", never "false means free" - which is exactly how
/// [isCommentaryCopyRestricted] takes [serverRestricted]: a `true` from the
/// envelope wins, and anything else falls through to the list below. The day
/// the commentary route starts sending the field, the callers already pass it.
library;

/// Commentary ids whose text is public domain and may be copied freely.
///
/// Mirror of the public-domain members of `MOBILE_ALLOWED_COMMENTARIES` in the
/// website's `lib/mobileLicensing.ts`. Exact match only - no case folding, no
/// trimming, no aliases - as on the bible side. A near-miss spelling reads as
/// unknown, and unknown is restricted.
const Set<String> publicDomainCommentaryIds = {
  'matthew_henry_nl',
  'dachsel',
  'calvijn_nl',
};

/// True when [commentaryId]'s text may not be copied, shared or selected.
///
/// [serverRestricted] is the envelope's flag when there is one. Only `true`
/// decides; `null` and `false` both fall through to [publicDomainCommentaryIds],
/// because the commentary envelope has no such field yet and a missing field
/// must not read as permission.
bool isCommentaryCopyRestricted(String? commentaryId, {bool? serverRestricted}) {
  if (serverRestricted == true) return true;
  if (commentaryId == null || commentaryId.isEmpty) return true;
  return !publicDomainCommentaryIds.contains(commentaryId);
}

/// Reader-facing names for the four commentaries, for the places that have an
/// id but no `BibleSource` to read the name off - the notice below, and a note
/// in the Notities list long after the chapter it was written in was closed.
const Map<String, String> commentaryDisplayNames = {
  'matthew_henry_nl': 'Matthew Henry',
  'dachsel': 'Dachsel',
  'calvijn_nl': 'Calvijn',
  'kingcomments_nl': 'KingComments',
};

/// The name to show for [commentaryId], falling back to the id itself so an
/// unmapped source still reads as something rather than as nothing.
String commentaryDisplayName(String? commentaryId) {
  if (commentaryId == null || commentaryId.isEmpty) return 'Commentaar';
  return commentaryDisplayNames[commentaryId] ?? commentaryId;
}

/// Said where a reader would otherwise reach for a selection handle. Names the
/// commentary, because "dit commentaar" means nothing to someone who has three
/// of them in a picker.
String commentaryCopyRestrictedNotice(String? commentaryId) {
  final name = commentaryDisplayNames[commentaryId];
  if (name == null) {
    return 'De tekst van dit commentaar is auteursrechtelijk beschermd en kan '
        'niet worden gekopieerd.';
  }
  return 'De tekst van $name is auteursrechtelijk beschermd en kan niet '
      'worden gekopieerd.';
}

/// Said in the note editor, where the reader keeps a quotation of restricted
/// text in their own note - which is fine - and might expect to get it back
/// out again, which is not.
const String commentaryNoteExcerptNotice =
    'Dit stukje commentaar wordt alleen in je eigen aantekening bewaard.';

/// How much of a restricted commentary a note may quote back to its author.
///
/// A note is the reader's own and a quotation that fits in a couple of lines
/// is what makes it findable again. Anything longer starts to be a copy of the
/// text rather than a pointer into it, so the excerpt is cut here and the
/// anchor - see `commentary_note_anchor.dart` - carries the way back to the
/// rest.
const int maxCommentaryExcerptChars = 240;

/// A quotation of [text] short enough to keep: whitespace collapsed, cut at a
/// word boundary, never longer than [maxCommentaryExcerptChars].
String commentaryExcerpt(String text) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= maxCommentaryExcerptChars) return flat;
  final cut = flat.substring(0, maxCommentaryExcerptChars);
  final lastSpace = cut.lastIndexOf(' ');
  final body = lastSpace > maxCommentaryExcerptChars ~/ 2
      ? cut.substring(0, lastSpace)
      : cut;
  return '${body.trimRight()}...';
}
