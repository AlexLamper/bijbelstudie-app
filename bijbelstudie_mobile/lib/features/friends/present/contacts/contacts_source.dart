import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The device address book, behind an interface two functions wide.
///
/// `flutter_contacts` asks for the contacts permission itself - it ships its
/// own `permissions` API with an "open settings" route for the permanently
/// denied case - so the plan's one new dependency really is the only one and
/// there is no `permission_handler` here (`VRIENDENKRING_PLAN.md` §3).
///
/// Wrapped rather than called directly for two reasons: a widget test can hand
/// the flow a fake address book instead of a method channel, and the fake can
/// *count* permission requests, which is how
/// `test/contact_matching_test.dart` proves the OS prompt is only reached
/// through the inline disclosure on the Vriendenkring screen.
enum ContactsAccess {
  /// Granted, in full or (iOS 18+) for a selection of contacts.
  granted,

  /// Refused, but the OS will ask again. On Android a first "Deny" lands
  /// here; on iOS almost nothing does, because iOS turns a single refusal
  /// into [blocked] straight away.
  denied,

  /// Refused for good, or disallowed by policy. Only the Settings app can
  /// change this, so the UI offers that route instead of asking again.
  blocked,

  /// The platform could not answer at all: no plugin on this build, a method
  /// channel error, another permission request already in flight.
  ///
  /// Deliberately **not** folded into [denied]. It used to be, and that is
  /// the kind of thing that makes a feature "work on Android but not on
  /// iPhone" without a word on screen: the reader is told they refused
  /// something they were never asked, and the only button offered asks the OS
  /// again, which iOS will never show twice.
  unavailable,
}

/// Reading the address book failed, with permission already granted.
///
/// Its own exception rather than an empty [AddressBook], because "er staat
/// niets in je contacten" and "we konden je contacten niet lezen" are
/// different sentences and only one of them is ever true. iOS throws here for
/// real reasons (a key that was not fetched, a contact store that lost its
/// authorisation, limited access with nothing picked) and swallowing that into
/// an empty book is what made the flow look like it simply found nobody.
class ContactsReadException implements Exception {
  ContactsReadException(this.detail);

  /// The platform's own words. Never shown to the reader - the screens have
  /// their own Dutch - but worth carrying for a log or a test.
  final String detail;

  @override
  String toString() => 'ContactsReadException: $detail';
}

/// Raw identifiers read off the device, held for the length of one matching
/// run and then dropped. Names are deliberately not read: the matches come
/// back from the server with their own names, so the address book's names
/// serve no purpose and the app does not ask for them.
class AddressBook {
  const AddressBook({this.phoneNumbers = const [], this.emailAddresses = const []});

  static const empty = AddressBook();

  final List<String> phoneNumbers;
  final List<String> emailAddresses;

  bool get isEmpty => phoneNumbers.isEmpty && emailAddresses.isEmpty;
}

abstract class ContactsSource {
  /// Shows the OS permission dialog, unless it has already been answered.
  ///
  /// **Never call this before the disclosure has been shown.** Play's
  /// "Personal and sensitive data" policy wants a prominent in-app disclosure
  /// first, and `ContactDiscoveryController` enforces the ordering.
  Future<ContactsAccess> requestAccess();

  /// Whether access is already granted, **without** ever showing a dialog.
  /// What the background re-check asks: it may only read a book the reader
  /// already opened through the disclosure and the OS prompt.
  Future<bool> hasAccess();

  /// Phone numbers and e-mail addresses, nothing else.
  ///
  /// Throws [ContactsReadException] when the platform refused to hand them
  /// over. An empty [AddressBook] means the book really is empty.
  Future<AddressBook> read();

  /// The Settings app, for the permanently denied case.
  Future<void> openSettings();
}

class DeviceContactsSource implements ContactsSource {
  const DeviceContactsSource();

  /// One plugin status to one of ours.
  ///
  /// `notDetermined` is grouped with `denied` on purpose: it is "no, but you
  /// may ask again", which is exactly what [ContactsAccess.denied] means.
  /// iOS's `permanentlyDenied` (what a single "Don't Allow" produces there)
  /// and `restricted` (parental controls) both mean "only Settings can change
  /// this", so both are [ContactsAccess.blocked].
  static ContactsAccess _accessFor(fc.PermissionStatus status) {
    switch (status) {
      case fc.PermissionStatus.granted:
      case fc.PermissionStatus.limited:
        return ContactsAccess.granted;
      case fc.PermissionStatus.denied:
      case fc.PermissionStatus.notDetermined:
        return ContactsAccess.denied;
      case fc.PermissionStatus.permanentlyDenied:
      case fc.PermissionStatus.restricted:
        return ContactsAccess.blocked;
    }
  }

  @override
  Future<ContactsAccess> requestAccess() async {
    final fc.PermissionStatus status;
    try {
      status = await fc.FlutterContacts.permissions.request(fc.PermissionType.read);
    } catch (error) {
      // No plugin on this platform, a channel error, or a concurrent request
      // ("CONCURRENT_REQUEST"). None of those is a refusal.
      return ContactsAccess.unavailable;
    }

    final access = _accessFor(status);
    if (access != ContactsAccess.denied) return access;

    // `denied` here can also be iOS answering `notDetermined` while its own
    // sheet is still settling - the iOS 18 "Selecteer contacten" pick comes
    // back before the selection is stored. Read the status once more before
    // telling the reader they refused; on Android the second read is the same
    // answer, so this costs nothing there.
    try {
      final again = _accessFor(
        await fc.FlutterContacts.permissions.check(fc.PermissionType.read),
      );
      return again == ContactsAccess.granted ? again : access;
    } catch (_) {
      return access;
    }
  }

  @override
  Future<bool> hasAccess() async {
    try {
      final status = await fc.FlutterContacts.permissions.check(fc.PermissionType.read);
      return _accessFor(status) == ContactsAccess.granted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<AddressBook> read() async {
    final List<fc.Contact> contacts;
    try {
      // `properties` has to name phone *and* email explicitly: without it the
      // plugin fetches neither, and on iOS the keys that were not asked for
      // are not merely empty but unreadable.
      contacts = await fc.FlutterContacts.getAll(
        properties: const {fc.ContactProperty.phone, fc.ContactProperty.email},
      );
    } catch (error) {
      throw ContactsReadException(error.toString());
    }

    final phoneNumbers = <String>[];
    final emailAddresses = <String>[];
    for (final contact in contacts) {
      for (final phone in contact.phones) {
        if (phone.number.trim().isNotEmpty) phoneNumbers.add(phone.number);
      }
      for (final email in contact.emails) {
        if (email.address.trim().isNotEmpty) emailAddresses.add(email.address);
      }
    }
    return AddressBook(phoneNumbers: phoneNumbers, emailAddresses: emailAddresses);
  }

  @override
  Future<void> openSettings() async {
    try {
      await fc.FlutterContacts.permissions.openSettings();
    } catch (_) {
      // Nothing to do if the OS will not open its own settings.
    }
  }
}

/// Overridden in tests with a fake that counts [ContactsSource.requestAccess]
/// calls.
final contactsSourceProvider = Provider<ContactsSource>((ref) {
  return const DeviceContactsSource();
});
