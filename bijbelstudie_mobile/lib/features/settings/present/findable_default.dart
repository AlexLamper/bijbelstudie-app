import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/data/account_scope.dart';
import '../../auth/present/auth_controller.dart'
    show authControllerProvider, sessionAccountProvider;
import '../../friends/present/contacts/contact_discovery_providers.dart'
    show contactDiscoveryStoreProvider, findableProvider;
import '../../friends/present/contacts/contacts_source.dart' show contactsSourceProvider;

/// Prefs key, scoped per account with [AccountScope.keyFor]: "the one-time
/// default has had its turn". Set once the default landed, or once the reader
/// is seen to have made the choice themselves, and never read again after
/// that - findability itself lives server-side, this only remembers that
/// nobody has to be nudged a second time.
const findableDefaultAppliedKey = 'friends.contacts.discoverableDefaultApplied';

/// `ContactDiscoveryStore`'s own key for the local findability mirror.
///
/// Repeated here on purpose rather than read through the store: the store
/// exposes `isDiscoverable`, which answers false both for "turned it off" and
/// for "never asked", and those two are exactly what this has to tell apart.
/// The *presence* of the key is the distinction - it is written only by an
/// explicit flip of the switch and removed only by "contacten vergeten".
const _discoverableMirrorKey = 'friends.contacts.discoverable';

/// Turns "Laat vrienden me vinden" on once, for a reader who already let the
/// app read their contacts.
///
/// Granting contacts access is itself a statement that being discoverable is
/// fine, so starting that switch off made the two consents disagree: the
/// reader had already connected their address book and still could not be
/// found by the people in it. This flips it on - **once**.
///
/// What keeps it a default rather than a forced value:
///
/// * it never runs for a reader who did not connect contacts (no accepted
///   disclosure, or access never actually granted);
/// * it never runs when the switch has been flipped by hand, in either
///   direction ([_discoverableMirrorKey] present);
/// * once it has run it records [findableDefaultAppliedKey] and stops, so a
///   reader who turns findability off afterwards stays off for good.
///
/// Failure is silence. The reader did not ask for this, so a server that says
/// no gets no error card; the marker simply stays unset and the next visit
/// tries again.
class FindableDefault {
  FindableDefault(this._ref);

  final Ref _ref;

  /// Applies the default if it is due. Returns whether findability was turned
  /// on by this call - for tests; no caller needs it.
  Future<bool> applyIfDue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final account = await AccountScope.resolve(_ref.read(sessionAccountProvider));
      final marker = AccountScope.keyFor(findableDefaultAppliedKey, account);
      if (prefs.getBool(marker) ?? false) return false;

      // An explicit choice outranks the default, including one made before
      // this code existed. Marked so it is not looked at again.
      if (prefs.containsKey(_discoverableMirrorKey)) {
        await prefs.setBool(marker, true);
        return false;
      }

      final store = await _ref.read(contactDiscoveryStoreProvider.future);
      // The signal the whole default rests on: the disclosure was accepted
      // and access really came through - a match ran, or the OS still says
      // the permission is granted. `hasAccess` never shows a dialog.
      if (store.disclosureAcceptedAt == null) return false;
      if (store.lastMatchAt == null && !await _ref.read(contactsSourceProvider).hasAccess()) {
        return false;
      }

      // Nothing to be found by yet: with no number and no known e-mail there
      // is no identifier to hash, so this waits for the profile instead of
      // spending a call that would promise nothing.
      final email = _ref.read(authControllerProvider).value?.email;
      if (email == null || email.trim().isEmpty) return false;

      // The same call the switch itself makes, so the stored hashes, the
      // local mirror and the switch's position all move together.
      final ok = await _ref.read(findableProvider.notifier).setFindable(true, email: email);
      if (ok) await prefs.setBool(marker, true);
      return ok;
    } catch (_) {
      // No preferences plugin, no network, no profile: all of them mean "not
      // today", never an error on screen.
      return false;
    }
  }
}

final findableDefaultProvider = Provider<FindableDefault>(FindableDefault.new);
