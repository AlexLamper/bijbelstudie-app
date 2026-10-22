import 'dart:convert';

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
///
/// [claim] runs once per device, so it cannot help a *later* change of id -
/// the one a deleted and recreated account brings. [sameReaderScope] and
/// [strandedScope] are how a store recovers from that without weakening the
/// rule above.
class AccountScope {
  AccountScope._();

  /// The last account that signed in on this device. Sticky across sign-out,
  /// like `sessionAccountProvider`, and what an offline launch falls back to:
  /// there the profile fetch fails, so the auth state never names a user even
  /// though the stored token is still this reader's.
  static const kAccountKey = 'session.account';

  /// The account that inherited the data written before scoping existed.
  static const kLegacyOwnerKey = 'session.legacy_owner';

  /// Reader fingerprints by account id, as JSON: `{"<account>": "<print>"}`.
  ///
  /// An account id is not the reader. Deleting an account and making it again
  /// hands the same person a new id, and from the device's side that looks
  /// exactly like a second reader signing in - same sign-out, same new id,
  /// same orphaned data. Only something about the person tells the two apart,
  /// and the e-mail is what the app has. It is kept as a [fingerprint] rather
  /// than itself: equality is all this needs, so there is no reason to write
  /// an address into plain preferences.
  static const kIdentitiesKey = 'session.identities';

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

  /// Records [account] as this device's current account, and the reader
  /// behind it when [email] is known. The first account ever recorded also
  /// takes over the bare [legacyKeys].
  ///
  /// The fingerprint is written even when the account is already the current
  /// one: an install that was signed in before this existed has to get its
  /// print recorded on some later launch, or nothing could ever be matched.
  ///
  /// Every check and write below lands in the preferences' in-memory cache
  /// before the first await, so two stores claiming at once cannot both
  /// migrate.
  static Future<void> claim(
    String account, {
    String? email,
    SharedPreferences? prefs,
  }) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    await _recordIdentity(p, account, email);
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

  /// A short, stable, one-way print of [email].
  ///
  /// FNV-1a, hand-rolled: `hashCode` is not promised to stay the same between
  /// SDK builds, and a print that changes under the app would turn every
  /// reader into a stranger. Empty in, empty out - an unknown reader never
  /// "matches" another unknown one.
  static String fingerprint(String? email) {
    final value = (email ?? '').trim().toLowerCase();
    if (value.isEmpty) return '';
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = (hash ^ unit) & 0xffffffff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static Map<String, String> _identities(SharedPreferences prefs) {
    final raw = prefs.getString(kIdentitiesKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return <String, String>{
          for (final entry in decoded.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
        };
      }
    } catch (_) {
      // Unreadable: every account counts as unrecorded, which is the cautious
      // answer - nothing is adopted on a match that cannot be made.
    }
    return const {};
  }

  /// The reader behind [account] as this device recorded them, or null when it
  /// never did: every account that signed in before [kIdentitiesKey] existed,
  /// and any sign-in that carried no e-mail.
  static String? identityOf(SharedPreferences prefs, String? account) {
    if (account == null || account.isEmpty) return null;
    final print = _identities(prefs)[account];
    return print == null || print.isEmpty ? null : print;
  }

  static Future<void> _recordIdentity(
    SharedPreferences p,
    String account,
    String? email,
  ) async {
    final print = fingerprint(email);
    if (print.isEmpty) return;
    final current = _identities(p);
    if (current[account] == print) return;
    await p.setString(
      kIdentitiesKey,
      jsonEncode(<String, String>{...current, account: print}),
    );
  }

  /// The account ids that hold data under [base] on this device, other than
  /// [account]'s own.
  ///
  /// Scoped keys are `<base>.<id>` and an account id carries no dot, so this
  /// is a plain prefix scan. The bare `<base>` is never one of them: [claim]
  /// hands that to the first account that signs in here.
  static List<String> otherScopeIds(
    SharedPreferences prefs,
    List<String> bases,
    String? account,
  ) {
    final ids = <String>{};
    for (final base in bases) {
      final prefix = '$base.';
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(prefix)) continue;
        final id = key.substring(prefix.length);
        if (id.isEmpty || id.contains('.')) continue;
        if (id == account) continue;
        ids.add(id);
      }
    }
    return ids.toList(growable: false)..sort();
  }

  /// The one other id under [bases] that this same reader signed in as, or
  /// null when there is none.
  ///
  /// Deleting an account and making it again leaves every `<base>.<id>` store
  /// reading empty while the reader's own data sits on disk under the id they
  /// lost - which is how a shelf of hearted verses can look deleted without
  /// anything having been deleted. A matching [identityOf] print says it is
  /// the same person, not a second reader, so that data may be taken over
  /// without asking and without weakening the per-account rule. Both prints
  /// have to be recorded: unknown never matches unknown.
  static String? sameReaderScope(
    SharedPreferences prefs,
    List<String> bases,
    String? account,
  ) {
    final mine = identityOf(prefs, account);
    if (mine == null) return null;
    final matching = otherScopeIds(prefs, bases, account)
        .where((id) => identityOf(prefs, id) == mine)
        .toList(growable: false);
    return matching.length == 1 ? matching.first : null;
  }

  /// The one other id under [bases] whose reader this device never recorded,
  /// or null when there is none or the device has had more than one.
  ///
  /// Data stranded before [kIdentitiesKey] existed. It may well be this
  /// reader's, under an id they lost; it may be the other person who used to
  /// hold this phone. Nothing on the device can tell, so a store must never
  /// take it silently - it offers it, and the reader says whether it is
  /// theirs. Two or more other ids mean the device has genuinely had several
  /// readers: then there is nothing to offer, because showing one reader's
  /// data to another is worse than showing an empty list.
  static String? strandedScope(
    SharedPreferences prefs,
    List<String> bases,
    String? account,
  ) {
    if (account == null || account.isEmpty) return null;
    final ids = otherScopeIds(prefs, bases, account);
    if (ids.length != 1) return null;
    return identityOf(prefs, ids.first) == null ? ids.first : null;
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
