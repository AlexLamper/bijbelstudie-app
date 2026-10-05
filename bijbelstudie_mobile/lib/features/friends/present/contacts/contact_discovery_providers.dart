import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../data/friend_models.dart';
import '../../data/friends_repository.dart';
import 'contact_discovery_store.dart';
import 'contact_hashing.dart';
import 'contacts_source.dart';

/// State and providers for contact matching (`VRIENDENKRING_PLAN.md` §6).
///
/// The shape of the whole flow: disclosure screen -> OS permission -> read the
/// address book -> normalise and hash on-device -> `POST
/// /friends/discovery/match` -> a list with an "Uitnodigen" per row. Nothing is
/// sent on the reader's behalf at any point (plan principle 3), and nothing but
/// the matched user ids is written to disk.

/// Where the flow has got to. One enum rather than a handful of booleans so
/// the screen is a `switch` and no two states can be true at once.
enum ContactDiscoveryStage {
  /// Nothing has happened yet.
  idle,

  /// The disclosure screen has not been passed. The OS prompt is unreachable
  /// from here - see [ContactDiscoveryController.startMatch].
  needsDisclosure,

  /// The OS dialog is up, or the address book is being read and hashed.
  working,

  /// `/friends/discovery/*` answered 503: the feature is off server-side.
  /// Not an error, and never shown as one.
  unavailable,

  /// Refused, but askable again.
  permissionDenied,

  /// Refused for good. Only the Settings app can undo it.
  permissionBlocked,

  /// Permission granted and the address book has no usable number or address
  /// in it at all.
  emptyAddressBook,

  /// The match ran. [ContactDiscoveryState.found] may still be empty - that is
  /// "niemand gevonden", not a failure.
  matched,

  /// Something actually went wrong, and [ContactDiscoveryState.message] says
  /// what. The rate limiter's own Dutch line lands here too.
  failed,
}

class ContactDiscoveryState {
  const ContactDiscoveryState({
    this.stage = ContactDiscoveryStage.idle,
    this.found = const [],
    this.message,
    this.invited = const {},
  });

  static const idle = ContactDiscoveryState();

  final ContactDiscoveryStage stage;

  /// Accounts that chose to be findable. Existing friends and anyone blocked
  /// either way are already filtered out server-side, so every row can be
  /// offered an "Uitnodigen".
  final List<FriendSummary> found;

  /// The server's own line when it sent one, or the reason a run failed.
  final String? message;

  /// User ids this run has already sent a verzoek to, so a row does not offer
  /// "Uitnodigen" twice.
  final Set<String> invited;

  bool get isBusy => stage == ContactDiscoveryStage.working;

  ContactDiscoveryState copyWith({
    ContactDiscoveryStage? stage,
    List<FriendSummary>? found,
    String? message,
    bool clearMessage = false,
    Set<String>? invited,
  }) {
    return ContactDiscoveryState(
      stage: stage ?? this.stage,
      found: found ?? this.found,
      message: clearMessage ? null : (message ?? this.message),
      invited: invited ?? this.invited,
    );
  }
}

/// The preferences-backed store, opened once.
final contactDiscoveryStoreProvider = FutureProvider<ContactDiscoveryStore>((ref) {
  return ContactDiscoveryStore.open();
});

/// The ISO country used to read a national phone number, from the device
/// locale and narrowed to the countries `lib/friends/discovery.ts` knows.
///
/// Nothing in the account carries a country, so the locale is the only honest
/// guess; a number already in international form ignores it anyway. Overridden
/// in tests.
final contactCountryProvider = Provider<String>((ref) {
  // `PlatformDispatcher.instance` rather than the binding's: it needs no
  // `WidgetsBinding`, so this provider also answers in a pure Dart test.
  return contactCountryFor(PlatformDispatcher.instance.locale.countryCode);
});

/// Whether to offer contact matching at all.
///
/// Both switches have to be on: the build's own dart-define
/// ([AppConfig.contactMatchingEnabled]) and the server's pepper. A false here
/// means the entry point renders nothing - not an error card - because a
/// feature that is simply off is not a fault
/// (`FriendsRepository.isContactDiscoveryAvailable` never throws).
final contactDiscoveryOfferedProvider = FutureProvider<bool>((ref) async {
  if (!AppConfig.contactMatchingEnabled) return false;
  return ref.watch(friendsRepositoryProvider).isContactDiscoveryAvailable();
});

class ContactDiscoveryController extends Notifier<ContactDiscoveryState> {
  @override
  ContactDiscoveryState build() => ContactDiscoveryState.idle;

  /// Read the address book, hash it, match it.
  ///
  /// **The gate.** It refuses to touch [ContactsSource] - so the OS dialog
  /// cannot appear - until the disclosure screen has recorded that it was
  /// passed. That makes the ordering Play asks for structural rather than a
  /// convention somebody can forget: there is no path from a button to the
  /// permission prompt that does not go through
  /// `ContactsDisclosureScreen`.
  Future<void> startMatch() async {
    if (state.isBusy) return;

    final store = await ref.read(contactDiscoveryStoreProvider.future);
    if (store.disclosureAcceptedAt == null) {
      state = const ContactDiscoveryState(stage: ContactDiscoveryStage.needsDisclosure);
      return;
    }

    state = const ContactDiscoveryState(stage: ContactDiscoveryStage.working);

    final repo = ref.read(friendsRepositoryProvider);
    final source = ref.read(contactsSourceProvider);

    // The pepper first: if contact matching is off server-side there is no
    // reason to have asked for anything.
    final String? pepper;
    try {
      pepper = await repo.getContactPepper();
    } catch (_) {
      state = const ContactDiscoveryState(
        stage: ContactDiscoveryStage.failed,
        message: 'We konden je contacten nu niet controleren. Probeer het zo nog eens.',
      );
      return;
    }
    if (pepper == null) {
      state = const ContactDiscoveryState(stage: ContactDiscoveryStage.unavailable);
      return;
    }

    final access = await source.requestAccess();
    switch (access) {
      case ContactsAccess.denied:
        state = const ContactDiscoveryState(stage: ContactDiscoveryStage.permissionDenied);
        return;
      case ContactsAccess.blocked:
        state = const ContactDiscoveryState(stage: ContactDiscoveryStage.permissionBlocked);
        return;
      case ContactsAccess.granted:
        break;
    }

    final book = await source.read();
    if (book.isEmpty) {
      state = const ContactDiscoveryState(stage: ContactDiscoveryStage.emptyAddressBook);
      return;
    }

    final hashes = hashAddressBook(
      phoneNumbers: book.phoneNumbers,
      emailAddresses: book.emailAddresses,
      pepper: pepper,
      country: ref.read(contactCountryProvider),
    );
    if (hashes.isEmpty) {
      state = const ContactDiscoveryState(stage: ContactDiscoveryStage.emptyAddressBook);
      return;
    }

    final result = await repo.matchContacts(hashes);
    if (!result.available) {
      state = const ContactDiscoveryState(stage: ContactDiscoveryStage.unavailable);
      return;
    }
    if (result.found.isEmpty && result.message != null) {
      // A rate limit, or a server that said no. Its own Dutch line is better
      // than anything written here.
      state = ContactDiscoveryState(
        stage: ContactDiscoveryStage.failed,
        message: result.message,
      );
      return;
    }

    await store.setMatchedUserIds(result.found.map((friend) => friend.userId));
    state = ContactDiscoveryState(
      stage: ContactDiscoveryStage.matched,
      found: result.found,
      message: result.message,
    );
  }

  /// What the disclosure screen's "Doorgaan" calls: record that the disclosure
  /// was shown and accepted, then run. The only thing that opens the gate.
  Future<void> acceptDisclosureAndStart() async {
    final store = await ref.read(contactDiscoveryStoreProvider.future);
    await store.markDisclosureAccepted();
    await startMatch();
  }

  /// Send a verzoek to one match. Nothing here is automatic - this runs on a
  /// tap, one row at a time (plan principle 3).
  Future<FriendActionResult> inviteMatch(FriendSummary match) async {
    final result = await ref
        .read(friendsRepositoryProvider)
        .invite(userId: match.userId, source: 'contacts');
    if (result.ok) {
      state = state.copyWith(invited: {...state.invited, match.userId});
    }
    return result;
  }

  Future<void> openSystemSettings() {
    return ref.read(contactsSourceProvider).openSettings();
  }

  /// `DELETE /friends/discovery` plus the local half: forget the hashes on the
  /// server, stop being findable, and clear everything stored here.
  ///
  /// Both halves run even when one fails, because half-forgotten is the one
  /// outcome nobody can explain. Returns whether the server confirmed.
  Future<bool> forget() async {
    final ok = await ref.read(friendsRepositoryProvider).forgetContactDiscovery();
    final store = await ref.read(contactDiscoveryStoreProvider.future);
    await store.forget();
    state = ContactDiscoveryState.idle;
    return ok;
  }
}

final contactDiscoveryProvider =
    NotifierProvider<ContactDiscoveryController, ContactDiscoveryState>(
      ContactDiscoveryController.new,
    );

/// The reader's own findability: the second consent, separate from reading an
/// address book (plan principle 1).
class FindableController extends Notifier<bool> {
  @override
  bool build() => false;

  /// Reads the stored mirror. Called once when the switch mounts; the server
  /// holds the real answer and `GET /friends/settings` carries it as
  /// `hasContactHashes`.
  Future<void> load() async {
    final store = await ref.read(contactDiscoveryStoreProvider.future);
    state = store.isDiscoverable;
  }

  /// Switch on: the reader's own phone and e-mail go up **in the clear** to
  /// `POST /friends/discovery/hashes`, which normalises and hashes them
  /// server-side. That is the right way round and not a slip: the server
  /// already knows the account's e-mail, so hashing one's own two identifiers
  /// client-side would buy nothing, while somebody *else's* address book never
  /// leaves the phone unhashed.
  ///
  /// `discoverable` is always sent explicitly, because it defaults to true
  /// server-side when it is absent.
  Future<bool> setFindable(bool value, {String? phone, String? email}) async {
    final repo = ref.read(friendsRepositoryProvider);
    final store = await ref.read(contactDiscoveryStoreProvider.future);

    final bool ok;
    if (value) {
      ok = await repo.saveOwnContactIdentifiers(
        OwnContactIdentifiers(
          phone: phone,
          email: email,
          country: ref.read(contactCountryProvider),
          discoverable: true,
        ),
      );
    } else {
      // Off is a deletion, not a flag: the stored hashes go with it.
      ok = await repo.forgetContactDiscovery();
    }

    if (ok) {
      await store.setDiscoverable(value);
      state = value;
    }
    return ok;
  }
}

final findableProvider = NotifierProvider<FindableController, bool>(
  FindableController.new,
);
