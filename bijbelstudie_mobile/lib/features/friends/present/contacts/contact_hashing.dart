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
/// No Flutter import here on purpose - the whole module is pure functions, so
/// `test/contact_hashing_test.dart` can check the three ways a Dutch number is
/// written without a widget tree.
///
/// The pepper is the server's (`GET /friends/discovery/pepper`), held in memory
/// for the length of one matching run and never written to disk.

/// Everything a human or an address book sprinkles through a phone number:
/// whitespace, hyphens, brackets, dots, a non-breaking space, and the typographic
/// dashes (U+2011 figure dash through U+2015 horizontal bar) that a paste from a
/// web page brings with it.
final RegExp _phoneNoise = RegExp(r'[\s\-(). ‑-―]');

final RegExp _nonDigit = RegExp(r'\D');

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
  var value = raw.trim().replaceAll(_phoneNoise, '');
  if (value.isEmpty) return null;

  // 00 31 ... is the same as +31 ...
  if (value.startsWith('00')) value = '+${value.substring(2)}';

  if (value.startsWith('+')) {
    final digits = value.substring(1).replaceAll(_nonDigit, '');
    return digits.length >= 8 ? '+$digits' : null;
  }

  final digits = value.replaceAll(_nonDigit, '');
  if (digits.isEmpty) return null;

  final prefix =
      contactCountryPrefixes[country.toUpperCase()] ??
      contactCountryPrefixes[defaultContactCountry]!;
  // A national number written with its trunk zero: 0612345678 -> +31612345678.
  final national = digits.startsWith('0') ? digits.substring(1) : digits;
  if (national.length < 8) return null;
  return '+$prefix$national';
}

/// [raw] trimmed and lower-cased, or null when it is not shaped like an
/// address at all.
String? normaliseContactEmail(String raw) {
  if (raw.isEmpty) return null;
  final value = raw.trim().toLowerCase();
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
  final phoneHashes = <String>{};
  for (final number in phoneNumbers) {
    final hash = hashContactPhone(number, pepper, country: country);
    if (hash != null) phoneHashes.add(hash);
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
