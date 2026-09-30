import 'package:shared_preferences/shared_preferences.dart';

/// Scopes on-device data to the reader it belongs to.
///
/// Favourites, study plans, search history and the offline write queue are a
/// reader's own, not the phone's: a second account signing in on the same
/// device must not see (or sync) the first one's. Reading preferences - font
/// size, translation, theme - stay per device on purpose.
///
/// Prefs-backed stores key their data `<base>.<accountId>` ([keyFor]). Builds
/// from before this wrote the bare `<base>`; the first account to sign in on
/// the device inherits that data ([claim]) and the bare key is removed, so
/// nobody who updates loses their favourites or plans. [ContentCache] hands its
/// untagged rows over the same way, to [kLegacyOwnerKey].
class AccountScope {
  AccountScope._();

  /// The last account that signed in on this device. Sticky across sign-out,
  /// like `sessionAccountProvider`, and what an offline launch falls back to:
  /// there the profile fetch fails, so the auth state never names a user even
  /// though the stored token is still this reader's.
  static const kAccountKey = 'session.account';

  /// The account that inherited the data written before scoping existed.
  static const kLegacyOwnerKey = 'session.legacy_owner';

  /// Bare prefs keys holding a reader's own data, moved on the first [claim].
  static const legacyKeys = <String>[
    'daytext.likes',
    'daytext.liked',
    'studies.plans',
  ];

  /// `<base>.<account>`, or the bare [base] while no account has ever signed
  /// in on this device (the first one to do so inherits it).
  static String keyFor(String base, String? account) =>
      account == null || account.isEmpty ? base : '$base.$account';

  /// The account whose data should be read and written: [live] (the
  /// signed-in user, from `sessionAccountProvider`) when known, otherwise the
  /// last account that signed in here. Null only before any sign-in.
  static Future<String?> resolve(String? live) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (live != null && live.isNotEmpty) {
        await claim(live, prefs: prefs);
        return live;
      }
      return prefs.getString(kAccountKey);
    } catch (_) {
      // No preferences plugin (tests, an unusual platform).
      return live;
    }
  }

  /// Records [account] as this device's current account. The first account
  /// ever recorded also takes over the bare [legacyKeys].
  ///
  /// Every check and write below lands in the preferences' in-memory cache
  /// before the first await, so two stores claiming at once cannot both
  /// migrate.
  static Future<void> claim(String account, {SharedPreferences? prefs}) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    if (p.getString(kAccountKey) == account) return;
    final writes = <Future<bool>>[];
    if (p.getString(kLegacyOwnerKey) == null) {
      writes.add(p.setString(kLegacyOwnerKey, account));
      for (final base in legacyKeys) {
        final value = p.get(base);
        if (value == null) continue;
        final key = keyFor(base, account);
        if (!p.containsKey(key)) {
          if (value is String) {
            writes.add(p.setString(key, value));
          } else if (value is List) {
            writes.add(p.setStringList(key, value.cast<String>()));
          }
        }
        writes.add(p.remove(base));
      }
    }
    writes.add(p.setString(kAccountKey, account));
    await Future.wait(writes);
  }

  /// The account that inherited the pre-scoping data, if one has signed in.
  static Future<String?> legacyOwner() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(kLegacyOwnerKey);
    } catch (_) {
      return null;
    }
  }
}
