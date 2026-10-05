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
/// `test/contacts_disclosure_test.dart` proves the OS prompt is unreachable
/// without passing the disclosure screen.
enum ContactsAccess {
  /// Granted, in full or (iOS 18+) for a selection of contacts.
  granted,

  /// Refused, but the OS will ask again.
  denied,

  /// Refused for good, or disallowed by policy. Only the Settings app can
  /// change this, so the UI offers that route instead of asking again.
  blocked,
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
  /// **Never call this before the disclosure screen has been passed.** Play's
  /// "Personal and sensitive data" policy wants a prominent in-app disclosure
  /// first, and `ContactDiscoveryController` enforces the ordering.
  Future<ContactsAccess> requestAccess();

  /// Phone numbers and e-mail addresses, nothing else.
  Future<AddressBook> read();

  /// The Settings app, for the permanently denied case.
  Future<void> openSettings();
}

class DeviceContactsSource implements ContactsSource {
  const DeviceContactsSource();

  @override
  Future<ContactsAccess> requestAccess() async {
    try {
      final status = await fc.FlutterContacts.permissions.request(fc.PermissionType.read);
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
    } catch (_) {
      // A concurrent request, or no plugin on this platform. Either way there
      // is no permission to work with and nothing worth an error card.
      return ContactsAccess.denied;
    }
  }

  @override
  Future<AddressBook> read() async {
    try {
      final contacts = await fc.FlutterContacts.getAll(
        properties: const {fc.ContactProperty.phone, fc.ContactProperty.email},
      );
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
    } catch (_) {
      return AddressBook.empty;
    }
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
