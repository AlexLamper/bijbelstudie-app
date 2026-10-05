import 'package:shared_preferences/shared_preferences.dart';

/// The only thing contact matching is allowed to keep on disk
/// (`VRIENDENKRING_PLAN.md` §6 step 5): the ids of the accounts a match
/// returned, plus the two consents.
///
/// Explicitly **not** here, and nowhere else either: the address book, the
/// names in it, the normalised numbers, the hashes, or the pepper. A match run
/// holds those in memory for the length of one call and drops them. Keeping
/// the ids is what lets the "Vrienden gevonden" list survive a rebuild without
/// spending one of the five match calls an hour.
///
/// [forget] is the counterpart to the consent and really deletes - the local
/// half of `DELETE /friends/discovery`.
class ContactDiscoveryStore {
  const ContactDiscoveryStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<ContactDiscoveryStore> open() async {
    return ContactDiscoveryStore(await SharedPreferences.getInstance());
  }

  static const _matchedIdsKey = 'friends.contacts.matchedUserIds';
  static const _consentedAtKey = 'friends.contacts.disclosureAcceptedAt';
  static const _discoverableKey = 'friends.contacts.discoverable';

  /// User ids a match returned, newest run first. Never names, never pictures:
  /// those are re-fetched, so nothing identifying sits in the preferences file.
  List<String> get matchedUserIds => _prefs.getStringList(_matchedIdsKey) ?? const [];

  Future<void> setMatchedUserIds(Iterable<String> ids) async {
    final clean = <String>{for (final id in ids) id.trim()}..removeWhere((id) => id.isEmpty);
    if (clean.isEmpty) {
      await _prefs.remove(_matchedIdsKey);
      return;
    }
    await _prefs.setStringList(_matchedIdsKey, clean.toList(growable: false));
  }

  /// When the reader last passed the disclosure screen, or null if never.
  ///
  /// Recorded for the audit question "was the disclosure shown before the OS
  /// prompt?", which is exactly what store review asks. It is never used to
  /// *skip* the screen: [ContactsDisclosureScreen] is the only route to the
  /// permission request, every time.
  DateTime? get disclosureAcceptedAt {
    final millis = _prefs.getInt(_consentedAtKey);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> markDisclosureAccepted() async {
    await _prefs.setInt(_consentedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Whether the reader asked to be findable by their own number and e-mail.
  ///
  /// The second consent, and the server holds the real answer; this is the
  /// local mirror so the switch renders in the right position before the
  /// settings response lands. Absent means never asked, which reads as off.
  bool get isDiscoverable => _prefs.getBool(_discoverableKey) ?? false;

  Future<void> setDiscoverable(bool value) async {
    await _prefs.setBool(_discoverableKey, value);
  }

  /// Forget everything contact matching ever stored.
  ///
  /// Called when the reader revokes access, alongside
  /// `forgetContactDiscovery()` which does the same on the server. Both halves
  /// run even if one fails, because half-forgotten is the one outcome nobody
  /// can explain.
  Future<void> forget() async {
    await _prefs.remove(_matchedIdsKey);
    await _prefs.remove(_consentedAtKey);
    await _prefs.remove(_discoverableKey);
  }
}
