/// The address book as the contacts flow holds it in memory: plain data, no
/// Flutter and no plugin, so hashing and the "Nodig uit" picks can be tested
/// as pure functions. Read by `DeviceContactsSource` in `contacts_source.dart`.
library;

/// One phone number on an address-book entry, as the OS stored it.
class AddressBookPhone {
  const AddressBookPhone(this.number, {this.mobileLabel = false});

  /// Raw, exactly as the address book holds it. Normalised only where it is
  /// hashed or dialled.
  final String number;

  /// Whether the OS labels it as a mobile (mobile, iPhone, work mobile). A
  /// hint only: a Dutch 06 is a mobile whatever its label says, and
  /// `contact_invites.dart` decides with both.
  final bool mobileLabel;
}

/// One person in the address book: what "Nodig uit" needs to draw a row and
/// open a chat, and what matching needs to tell which rows already use the
/// app.
///
/// The name is read for one purpose only - drawing that row on this phone -
/// and never leaves it: the request to the server carries salted hashes of the
/// numbers and addresses and nothing else (`contact_hashing.dart`).
class AddressBookEntry {
  const AddressBookEntry({
    required this.id,
    this.name = '',
    this.phones = const [],
    this.emails = const [],
    this.starred = false,
  });

  /// The OS's own identifier for the contact. Stays on the device.
  final String id;
  final String name;
  final List<AddressBookPhone> phones;
  final List<String> emails;

  /// Starred / favourite. Android only; iOS has no such flag for third-party
  /// apps, so it is always false there.
  final bool starred;
}

/// The address book as read off the device, held in memory for the app
/// session and never written to disk.
///
/// [entries] is the per-person view "Nodig uit" needs. [phoneNumbers] and
/// [emailAddresses] are the flat lists matching hashes; a book built from
/// entries derives them, and a book built from the two flat lists (a test, an
/// older caller) simply has no entries.
class AddressBook {
  const AddressBook({
    List<String> phoneNumbers = const [],
    List<String> emailAddresses = const [],
    this.entries = const [],
  }) : _phoneNumbers = phoneNumbers,
       _emailAddresses = emailAddresses;

  static const empty = AddressBook();

  final List<String> _phoneNumbers;
  final List<String> _emailAddresses;
  final List<AddressBookEntry> entries;

  List<String> get phoneNumbers => [
    ..._phoneNumbers,
    for (final entry in entries)
      for (final phone in entry.phones) phone.number,
  ];

  List<String> get emailAddresses => [
    ..._emailAddresses,
    for (final entry in entries) ...entry.emails,
  ];

  bool get isEmpty => phoneNumbers.isEmpty && emailAddresses.isEmpty;
}
