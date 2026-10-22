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

  /// The disclosure was never shown and accepted. The OS prompt is
  /// unreachable from here - see [ContactDiscoveryController.startMatch].
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
    this.offerSettings = false,
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

  /// Whether a failure is one the Settings app can fix, so the screen can
  /// offer "Open instellingen" beside "Opnieuw proberen".
  ///
  /// True for the states where asking the OS again is pointless: iOS turns a
  /// single refusal into a permanent one, and a platform that cannot answer at
  /// all will not answer a second time either.
  final bool offerSettings;

  bool get isBusy => stage == ContactDiscoveryStage.working;

  ContactDiscoveryState copyWith({
    ContactDiscoveryStage? stage,
    List<FriendSummary>? found,
    String? message,
    bool clearMessage = false,
    Set<String>? invited,
    bool? offerSettings,
  }) {
    return ContactDiscoveryState(
      stage: stage ?? this.stage,
      found: found ?? this.found,
      message: clearMessage ? null : (message ?? this.message),
      invited: invited ?? this.invited,
      offerSettings: offerSettings ?? this.offerSettings,
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
  /// cannot appear - until something has recorded that the disclosure was
  /// shown and accepted. That makes the ordering Play asks for structural
  /// rather than a convention somebody can forget: the only thing that opens
  /// the gate is [acceptDisclosureAndStart], and the only caller of that is
  /// the "Verbind Contacten" card, which has the three disclosure lines
  /// printed under the button the reader taps.
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
        state = const ContactDiscoveryState(
          stage: ContactDiscoveryStage.permissionDenied,
          // Asking again is worth a try on Android, and on iOS it is not: the
          // screen offers both buttons and lets the reader pick.
          offerSettings: true,
        );
        return;
      case ContactsAccess.blocked:
        state = const ContactDiscoveryState(
          stage: ContactDiscoveryStage.permissionBlocked,
          offerSettings: true,
        );
        return;
      // The platform could not answer. Not a refusal, so it must not read as
      // one - and never as "niemand gevonden" either.
      case ContactsAccess.unavailable:
        state = const ContactDiscoveryState(
          stage: ContactDiscoveryStage.failed,
          message:
              'We konden je contacten niet openen. Kijk in de instellingen van je '
              'telefoon of BijbelStudie toegang heeft tot je contacten.',
          offerSettings: true,
        );
        return;
      case ContactsAccess.granted:
        break;
    }

    final AddressBook book;
    try {
      book = await source.read();
    } on ContactsReadException {
      // Granted and still unreadable: iOS does that, and an empty book here
      // would tell the reader their address book is empty, which is the one
      // thing it is not.
      state = const ContactDiscoveryState(
        stage: ContactDiscoveryStage.failed,
        message:
            'We konden je contacten niet lezen. Controleer de toegang tot contacten '
            'in de instellingen van je telefoon en probeer het nog eens.',
        offerSettings: true,
      );
      return;
    } catch (_) {
      state = const ContactDiscoveryState(
        stage: ContactDiscoveryStage.failed,
        message: 'We konden je contacten nu niet controleren. Probeer het zo nog eens.',
      );
      return;
    }
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
    await store.markMatched();
    // The same people also belong under "Mensen die je misschien kent", so
    // the Vrienden tab does not have to spend a second match call on them.
    ref.read(contactSuggestionsProvider.notifier).put(result.found);
    state = ContactDiscoveryState(
      stage: ContactDiscoveryStage.matched,
      found: result.found,
      message: result.message,
    );
  }

  /// What "Verbind Contacten" calls: record that the disclosure was on screen
  /// and accepted, then run. The only thing that opens the gate.
  ///
  /// The three facts Play wants said - what is read, what is sent, what is
  /// kept - are printed under that button (`ConnectContactsButton`), so they
  /// are in view at the moment of the tap. The bookkeeping is unchanged: the
  /// store still records when the disclosure was accepted, which is the
  /// question store review asks.
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
    ref.read(contactSuggestionsProvider.notifier).put(const []);
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
  ///
  /// The number is normalised to E.164 **here**, with the same function the
  /// address book is hashed with, before it goes up. That way the stored hash
  /// is of exactly the string a friend's phone will compute for this reader,
  /// whatever the server's own normaliser makes of the raw input (an older
  /// deploy did not know `+31 (0)6`, for one). A number that does not
  /// normalise is sent as typed and the server drops it.
  Future<bool> setFindable(bool value, {String? phone, String? email}) async {
    final repo = ref.read(friendsRepositoryProvider);
    final store = await ref.read(contactDiscoveryStoreProvider.future);
    final country = ref.read(contactCountryProvider);
    final typed = phone?.trim();
    final e164 = typed == null || typed.isEmpty
        ? null
        : normaliseContactPhone(typed, country: country);

    final bool ok;
    if (value) {
      ok = await repo.saveOwnContactIdentifiers(
        OwnContactIdentifiers(
          phone: e164 ?? (typed == null || typed.isEmpty ? null : typed),
          email: email,
          country: country,
          discoverable: true,
        ),
      );
    } else {
      // Off is a deletion, not a flag: the stored hashes go with it.
      ok = await repo.forgetContactDiscovery();
    }

    if (ok) {
      await store.setDiscoverable(value);
      if (!value) {
        await store.setHasOwnPhone(false);
      } else if (e164 != null) {
        await store.setHasOwnPhone(true);
      }
      state = value;
    }
    return ok;
  }

  /// The "Laat vrienden jou ook vinden" step of the contacts flow: become
  /// findable by [phone] (and, server-side, the account's e-mail).
  ///
  /// Null when the number does not read as one, so the caller can say so
  /// before anything is sent; otherwise whether the server took it.
  Future<bool?> saveOwnPhone(String phone) async {
    final e164 = normaliseContactPhone(phone.trim(), country: ref.read(contactCountryProvider));
    if (e164 == null) return null;
    return setFindable(true, phone: e164);
  }
}

/// Whether the contacts flow should still ask for the reader's own number:
/// true until they are findable **with** a phone number. Findable by e-mail
/// alone does not count, because people keep each other by number.
final ownPhoneNeededProvider = FutureProvider.autoDispose<bool>((ref) async {
  // Rebuilt when findability flips, so the card folds away once it lands.
  ref.watch(findableProvider);
  final store = await ref.watch(contactDiscoveryStoreProvider.future);
  return !(store.isDiscoverable && store.hasOwnPhone);
});

/// [AppConfig.contactMatchingEnabled], as a provider so a test can switch the
/// background re-check on without a dart-define.
final contactMatchingBuildFlagProvider = Provider<bool>(
  (ref) => AppConfig.contactMatchingEnabled,
);

/// How long a background re-check waits after the previous match, by hand or
/// not. The route allows 5 an hour per account; this spends at most two.
const Duration contactRecheckInterval = Duration(minutes: 30);

/// The first re-check of an app session waits only this long, so a reader
/// who reopens the app shortly after a match does not spend another call.
const Duration contactSessionRecheckInterval = Duration(minutes: 2);

/// People from the reader's address book who use BijbelStudie and chose to be
/// findable - the contacts half of "Mensen die je misschien kent".
///
/// Matching both ways needs both people to have run it *after* the other one
/// became findable, so a single run from the disclosure screen is not enough:
/// whoever connected first would never see whoever came second. This re-runs
/// the same match quietly, only when the reader already passed the disclosure
/// and already granted access (it never shows the OS dialog), at most once per
/// [contactRecheckInterval]. Every failure reads as "nothing new": it is a
/// suggestion list, not a screen of its own.
///
/// Held for the app session and never written to disk beyond the user ids the
/// store already keeps (plan §6 step 5).
class ContactSuggestionsController extends AsyncNotifier<List<FriendSummary>> {
  bool _running = false;

  /// What [put] last handed in, so a [build] still in flight when it arrives
  /// does not land afterwards and wipe it.
  List<FriendSummary>? _handed;

  @override
  Future<List<FriendSummary>> build() async {
    return await _match(contactSessionRecheckInterval) ?? _handed ?? const [];
  }

  /// The result of a run made elsewhere (the disclosure flow), or an empty
  /// list after the reader forgot their contacts.
  void put(List<FriendSummary> found) {
    _handed = List.unmodifiable(found);
    state = AsyncData(_handed!);
  }

  /// Re-run the match if the last one is older than [contactRecheckInterval].
  /// Fire-and-forget: the state only changes when a run actually lands.
  Future<void> recheckIfStale() async {
    final found = await _match(contactRecheckInterval);
    if (found != null) state = AsyncData(found);
  }

  /// Null when nothing ran (throttled, not consented, off, failed).
  Future<List<FriendSummary>?> _match(Duration minimumGap) async {
    if (_running || !ref.read(contactMatchingBuildFlagProvider)) return null;
    _running = true;
    try {
      final store = await ref.read(contactDiscoveryStoreProvider.future);
      if (store.disclosureAcceptedAt == null) return null;
      final last = store.lastMatchAt;
      if (last != null && DateTime.now().difference(last) < minimumGap) return null;

      final source = ref.read(contactsSourceProvider);
      if (!await source.hasAccess()) return null;

      final repo = ref.read(friendsRepositoryProvider);
      final pepper = await repo.getContactPepper();
      if (pepper == null) return null;

      final book = await source.read();
      if (book.isEmpty) return null;
      final hashes = hashAddressBook(
        phoneNumbers: book.phoneNumbers,
        emailAddresses: book.emailAddresses,
        pepper: pepper,
        country: ref.read(contactCountryProvider),
      );
      if (hashes.isEmpty) return null;

      // Stamped before the call, so a run that fails still waits its turn
      // instead of retrying into the rate limit on every rebuild.
      await store.markMatched();
      final result = await repo.matchContacts(hashes);
      if (!result.available || (result.found.isEmpty && result.message != null)) return null;
      await store.setMatchedUserIds(result.found.map((friend) => friend.userId));
      return List.unmodifiable(result.found);
    } catch (_) {
      return null;
    } finally {
      _running = false;
    }
  }
}

final contactSuggestionsProvider =
    AsyncNotifierProvider<ContactSuggestionsController, List<FriendSummary>>(
      ContactSuggestionsController.new,
    );

final findableProvider = NotifierProvider<FindableController, bool>(
  FindableController.new,
);
