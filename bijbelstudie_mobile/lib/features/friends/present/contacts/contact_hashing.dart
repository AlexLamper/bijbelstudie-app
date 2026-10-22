import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../data/friend_models.dart';

/// On-device normalisation and hashing for contact matching
/// (`VRIENDENKRING_PLAN.md` §6).
///
/// This is a line-for-line port of the website's `lib/friends/discovery.ts`
/// (`normalisePhone`, `normaliseEmail`, `hashIdentifier`, `COUNTRY_PREFIX`).
/// It has to agree with that file digit for digit: the two sides never compare
/// numbers, only hashes, so a single character of disagreement means nobody
/// ever matches and there is nothing on screen to tell you why. Change one,
/// change both.
///
/// One deliberate asymmetry, and only one: this side cleans a phone number
/// harder than the website does, because it reads an address book rather than a
/// form (see [_notPhoneCharacter]). It is a strict superset - every input the
/// website normalises comes out the same here - so the hashes still agree.
///
/// No Flutter import here on purpose - the whole module is pure functions, so
/// `test/contact_hashing_test.dart` can check the three ways a Dutch number is
/// written without a widget tree.
///
/// The pepper is the server's (`GET /friends/discovery/pepper`), held in memory
/// for the length of one matching run and never written to disk.

/// Everything that is not a digit and not a plus.
///
/// Wider than the website's noise class on purpose, and the one place the two
/// files are deliberately not identical. The website only ever sees a number a
/// human typed into a form; an address book hands back whatever the OS stored,
/// and iOS in particular returns directional marks (U+200E in front of a `+` is
/// common on an imported vCard), narrow no-break spaces, a true minus sign
/// (U+2212, outside the U+2011..U+2015 dash range the old class knew) and the
/// odd stray letter. One invisible character in front of the `+` was enough to
/// make `+31612345678` read as a *national* number and hash as `+313161234...`,
/// which matches nobody and says nothing on screen.
///
/// Keeping only digits and `+` cannot change the outcome for any input the
/// website also handles - those come out of both files the same - it only
/// rescues the ones this side used to get wrong.
final RegExp _notPhoneCharacter = RegExp(r'[^0-9+]');

/// The bracketed trunk zero of `+31 (0)6 12345678`, the way Dutch business
/// cards and e-mail signatures write a number. It has to go before the
/// brackets do, or the zero survives as a digit and `+310612345678` never
/// matches `+31612345678`.
final RegExp _bracketedTrunkZero = RegExp(r'\(\s*0\s*\)');

final RegExp _nonDigit = RegExp(r'\D');

/// Zero-width and bidi marks: no meaning in an identifier, but they change its
/// bytes and so its hash. Stripped from e-mail addresses too, because
/// [_emailShape] happily accepts one and the address then hashes to something
/// the server will never compute.
/// A raw string, so the escapes stay escapes: the characters themselves would
/// reorder this source line in every editor that renders it.
final RegExp _invisible = RegExp(
  r'[\u00ad\u200b-\u200f\u202a-\u202e\u2060\u2066-\u2069\ufeff]',
);

/// Deliberately not a full address validator: a thing with an `@` and a dot
/// after it is enough to hash, and anything stricter silently drops addresses
/// that work. Same expression as `normaliseEmail` server-side.
final RegExp _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Only the countries the app actually ships in; NL is the fallback.
/// `COUNTRY_PREFIX` in `lib/friends/discovery.ts`.
const Map<String, String> contactCountryPrefixes = {
  'NL': '31',
  'BE': '32',
  'DE': '49',
  'GB': '44',
  'US': '1',
  'ZA': '27',
};

/// The fallback country for a national number without a dialling prefix.
const String defaultContactCountry = 'NL';

/// [raw] in E.164, or null when there is not enough of a number to match on.
///
/// Dutch numbers are the common case, so the fallback country is NL and a
/// number already in international form is left alone. `06 12345678`,
/// `+31 6 12345678`, `0031612345678` and `06-12345678` all have to come out as
/// `+31612345678`, or two people who have each other in their contacts will
/// not match.
String? normaliseContactPhone(String raw, {String country = defaultContactCountry}) {
  if (raw.isEmpty) return null;
  // The bracketed trunk zero first, while its brackets are still there.
  final value = raw
      .trim()
      .replaceAll(_bracketedTrunkZero, '')
      .replaceAll(_notPhoneCharacter, '');
  if (value.isEmpty) return null;

  // A `+` only means anything in front, and by now nothing can sit in front of
  // it but a digit, so this test is no longer fooled by an invisible mark.
  final international = value.startsWith('+');
  final digits = value.replaceAll(_nonDigit, '');
  if (digits.isEmpty) return null;

  // 00 31 ... is the same as +31 ... . Checked on the digits rather than on
  // the raw string, so `+0031...` cannot be read twice.
  if (!international && digits.startsWith('00')) {
    final rest = digits.substring(2);
    return rest.length >= 8 ? '+$rest' : null;
  }

  if (international) {
    return digits.length >= 8 ? '+$digits' : null;
  }

  // The US has no trunk zero, so a national number that starts with one cannot
  // be American: it is a Dutch number on a phone whose locale says en_US,
  // which is common. Read it as NL rather than minting +1 6... .
  final upper = country.toUpperCase();
  final effective = upper == 'US' && digits.startsWith('0') ? defaultContactCountry : upper;
  final prefix =
      contactCountryPrefixes[effective] ?? contactCountryPrefixes[defaultContactCountry]!;
  // A national number written with its trunk zero: 0612345678 -> +31612345678.
  final national = digits.startsWith('0') ? digits.substring(1) : digits;
  if (national.length < 8) return null;
  return '+$prefix$national';
}

/// [raw] trimmed and lower-cased, or null when it is not shaped like an
/// address at all.
String? normaliseContactEmail(String raw) {
  if (raw.isEmpty) return null;
  final value = raw.replaceAll(_invisible, '').trim().toLowerCase();
  if (value.isEmpty) return null;
  return _emailShape.hasMatch(value) ? value : null;
}

/// HMAC-SHA256 under the server's pepper, truncated to [contactHashLength] hex
/// characters (16 bytes). `hashIdentifier` server-side.
String hashContactIdentifier(String value, String pepper) {
  final mac = Hmac(sha256, utf8.encode(pepper));
  return mac.convert(utf8.encode(value)).toString().substring(0, contactHashLength);
}

/// A phone number straight to its hash, or null when it does not normalise.
String? hashContactPhone(
  String raw,
  String pepper, {
  String country = defaultContactCountry,
}) {
  final normalised = normaliseContactPhone(raw, country: country);
  return normalised == null ? null : hashContactIdentifier(normalised, pepper);
}

/// An e-mail address straight to its hash, or null when it does not normalise.
String? hashContactEmail(String raw, String pepper) {
  final normalised = normaliseContactEmail(raw);
  return normalised == null ? null : hashContactIdentifier(normalised, pepper);
}

/// Which of [contactCountryPrefixes] a locale country code belongs to, or
/// [defaultContactCountry] for a locale the app does not ship in.
///
/// The device locale is the only country the client knows: nothing in the
/// account carries one. A reader in a country outside the map almost certainly
/// has their numbers stored in international form already, and those are
/// passed through untouched, so NL as the fallback costs them nothing.
String contactCountryFor(String? localeCountryCode) {
  final code = localeCountryCode?.trim().toUpperCase();
  if (code == null || code.isEmpty) return defaultContactCountry;
  return contactCountryPrefixes.containsKey(code) ? code : defaultContactCountry;
}

/// Everything in an address book, hashed and ready for
/// `POST /friends/discovery/match`.
///
/// [phoneNumbers] and [emailAddresses] are raw strings read from the device.
/// They are normalised, hashed, de-duplicated and capped here and nothing but
/// the resulting hex ever leaves this function - the caller holds the raw lists
/// for the length of one call and then drops them.
ContactDiscoveryHashes hashAddressBook({
  required Iterable<String> phoneNumbers,
  required Iterable<String> emailAddresses,
  required String pepper,
  String country = defaultContactCountry,
}) {
  // The device locale is only a guess at the country (a Dutch reader with an
  // en_GB phone is not rare), so a national number is also read as Dutch -
  // NL being where nearly every account is. A number already in international
  // form comes out the same both ways and the set folds it to one hash.
  final readings = {country.toUpperCase(), defaultContactCountry};
  final phoneHashes = <String>{};
  for (final number in phoneNumbers) {
    for (final reading in readings) {
      final hash = hashContactPhone(number, pepper, country: reading);
      if (hash != null) phoneHashes.add(hash);
    }
    if (phoneHashes.length >= maxContactMatchHashes) break;
  }

  final emailHashes = <String>{};
  for (final address in emailAddresses) {
    final hash = hashContactEmail(address, pepper);
    if (hash != null) emailHashes.add(hash);
    if (emailHashes.length >= maxContactMatchHashes) break;
  }

  // `ContactDiscoveryHashes` sanitises again in its constructor - the same
  // rules the match route applies - which costs nothing and means a future
  // change to either side cannot quietly send malformed hex.
  return ContactDiscoveryHashes(phoneHashes: phoneHashes, emailHashes: emailHashes);
}
