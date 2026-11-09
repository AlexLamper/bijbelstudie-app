import 'package:shared_preferences/shared_preferences.dart';

/// What contact matching keeps on this phone: the ids of the accounts a match
/// returned, which address-book entries those were and which ones the reader
/// already invited (both as the OS's own opaque contact ids), and the
/// consents.
///
/// Explicitly **not** here, and nowhere else on disk either: the names in the
/// address book, its numbers, the hashes, or the pepper. A run holds those in
/// memory and drops them. Keeping the ids is what lets "In je contacten" and
/// "Uitgenodigd" survive a restart without spending one of the five match
/// calls an hour.
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
  static const _ownPhoneKey = 'friends.contacts.ownPhoneSaved';
  static const _lastMatchKey = 'friends.contacts.lastMatchAt';
  static const _disclosureVersionKey = 'friends.contacts.disclosureVersion';
  static const _matchedEntryIdsKey = 'friends.contacts.matchedEntryIds';
  static const _invitedEntryIdsKey = 'friends.contacts.invitedEntryIds';

  /// How many invited rows are remembered. The oldest go first.
  static const _maxInvited = 500;

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

  /// When the reader last accepted the disclosure, or null if never.
  ///
  /// Recorded for the audit question "was the disclosure shown before the OS
  /// prompt?", which is exactly what store review asks. It is never used to
  /// *skip* the disclosure: the three facts are printed on the "Verbind
  /// Contacten" card itself, so they are on screen every time, and this is
  /// only the gate `ContactDiscoveryController.startMatch` reads.
  DateTime? get disclosureAcceptedAt {
    final millis = _prefs.getInt(_consentedAtKey);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> markDisclosureAccepted({int version = 1}) async {
    await _prefs.setInt(_consentedAtKey, DateTime.now().millisecondsSinceEpoch);
    await _prefs.setInt(_disclosureVersionKey, version);
  }

  /// Which wording of the disclosure was accepted. 1 for every acceptance made
  /// before the version was recorded - the text that said nothing was kept -
  /// so a build may only ask the server to keep hashes once the reader saw the
  /// wording that says it will (`contactsDisclosureVersion`).
  int get disclosureVersion =>
      disclosureAcceptedAt == null ? 0 : (_prefs.getInt(_disclosureVersionKey) ?? 1);

  /// The address-book entries (OS contact ids) the last match said already use
  /// BijbelStudie, so "Nodig uit" leaves them out.
  Set<String> get matchedEntryIds =>
      (_prefs.getStringList(_matchedEntryIdsKey) ?? const <String>[]).toSet();

  Future<void> setMatchedEntryIds(Iterable<String> ids) async {
    final clean = {for (final id in ids) id.trim()}..removeWhere((id) => id.isEmpty);
    if (clean.isEmpty) {
      await _prefs.remove(_matchedEntryIdsKey);
      return;
    }
    await _prefs.setStringList(_matchedEntryIdsKey, clean.toList(growable: false));
  }

  /// Address-book entries the reader sent an invite to, for "Uitgenodigd".
  Set<String> get invitedEntryIds =>
      (_prefs.getStringList(_invitedEntryIdsKey) ?? const <String>[]).toSet();

  Future<Set<String>> markInvited(String entryId) async {
    final list = [
      ...(_prefs.getStringList(_invitedEntryIdsKey) ?? const <String>[]).where((id) => id != entryId),
      entryId,
    ];
    final kept = list.length > _maxInvited ? list.sublist(list.length - _maxInvited) : list;
    await _prefs.setStringList(_invitedEntryIdsKey, kept);
    return kept.toSet();
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

  /// Whether the reader's own phone number went up with their findability.
  ///
  /// Only a flag - never the number. It matters because people keep each
  /// other in their contacts by number far more often than by e-mail, so a
  /// reader who is findable by e-mail alone is, in practice, findable by
  /// nobody. The flow asks for the number again until this is true.
  bool get hasOwnPhone => _prefs.getBool(_ownPhoneKey) ?? false;

  Future<void> setHasOwnPhone(bool value) async {
    await _prefs.setBool(_ownPhoneKey, value);
  }

  /// When an address book was last matched, by hand or in the background.
  /// Spaces the background re-check out under the route's 5-an-hour limit.
  DateTime? get lastMatchAt {
    final millis = _prefs.getInt(_lastMatchKey);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> markMatched([DateTime? at]) async {
    await _prefs.setInt(_lastMatchKey, (at ?? DateTime.now()).millisecondsSinceEpoch);
  }

  /// Forget everything contact matching ever stored.
  ///
  /// Called when the reader revokes access, alongside
  /// `forgetContactDiscovery()` which does the same on the server. Both halves
  /// run even if one fails, because half-forgotten is the one outcome nobody
  /// can explain.
  Future<void> forget() async {
    await _prefs.remove(_matchedIdsKey);
    await _prefs.remove(_disclosureVersionKey);
    await _prefs.remove(_matchedEntryIdsKey);
    await _prefs.remove(_invitedEntryIdsKey);
    await _prefs.remove(_consentedAtKey);
    await _prefs.remove(_discoverableKey);
    await _prefs.remove(_ownPhoneKey);
    await _prefs.remove(_lastMatchKey);
  }
}
