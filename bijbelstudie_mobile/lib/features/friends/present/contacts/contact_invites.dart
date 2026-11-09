import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'address_book.dart';
import 'contact_discovery_providers.dart';
import 'contact_hashing.dart';
import 'contacts_source.dart' show contactsSourceProvider;

/// "Nodig uit": people from the reader's own address book who do not use
/// BijbelStudie yet, and the one tap that asks them to.
///
/// Everything here happens on the phone. The names and numbers are read from
/// the address book into memory and drawn in a row; nothing about them is sent
/// to the server - the match call before this carried salted hashes only - and
/// the invite itself goes out through WhatsApp, the SMS app or the share sheet,
/// written and sent by the reader. The only thing kept on disk is which rows
/// were invited, as the OS's own contact ids (`ContactDiscoveryStore`).

/// One person who could be invited.
@immutable
class InviteCandidate {
  const InviteCandidate({
    required this.entryId,
    required this.name,
    required this.phone,
    required this.isMobile,
    this.starred = false,
  });

  /// The OS contact id, for "Uitgenodigd".
  final String entryId;

  /// As the address book holds it; may be empty.
  final String name;

  /// E.164, `+31612345678`.
  final String phone;

  /// A mobile number, so WhatsApp and SMS can reach it.
  final bool isMobile;

  /// Starred in the address book (Android).
  final bool starred;

  /// What the row says when the contact has no name.
  String get displayName => name.trim().isEmpty ? phone : name.trim();

  /// For "Hoi Anna," - null when there is no real name to greet.
  String? get firstName {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final first = trimmed.split(RegExp(r'\s+')).first;
    // Not a number, not an e-mail, not a whole sentence.
    if (first.contains('@') || RegExp(r'^[+\d]').hasMatch(first) || first.length > 20) return null;
    return first;
  }

  /// The international number without its plus, as wa.me wants it.
  String get waDigits => phone.replaceAll(RegExp(r'\D'), '');
}

/// Whether [e164] is a mobile number, from the number itself where the
/// country makes that certain, and from the address book's label elsewhere.
bool isMobileNumber(String e164, {bool mobileLabel = false}) {
  // Netherlands: 06. Belgium: 04. Germany: 015, 016, 017. UK: 07.
  // South Africa: 06, 07, 08.
  const byPrefix = ['+316', '+324', '+4915', '+4916', '+4917', '+447', '+276', '+277', '+278'];
  for (final prefix in byPrefix) {
    if (e164.startsWith(prefix)) return true;
  }
  // A number in one of those countries that is not a mobile is a landline,
  // whatever its label says; anywhere else the label is all there is.
  const knownCountries = ['+31', '+32', '+49', '+44', '+27'];
  if (knownCountries.any(e164.startsWith)) return false;
  return mobileLabel;
}

/// Lowercase and without the common accents, so "Ellen" finds "Élise" and
/// "jose" finds "José".
String foldForSearch(String value) {
  const from = 'áàâäãåéèêëíìîïóòôöõúùûüýÿçñ';
  const to = 'aaaaaaeeeeiiiiooooouuuuyycn';
  final lower = value.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    out.write(index >= 0 ? to[index] : char);
  }
  return out.toString();
}

/// Every address-book entry with a usable phone number that is not in
/// [exclude] (the entries a match said already use the app), one row per
/// person and one person per number.
///
/// Ordered as "Nodig uit" shows them: starred first, then contacts with a
/// mobile number, then alphabetically by name, nameless rows last.
List<InviteCandidate> inviteCandidatesFrom(
  AddressBook book, {
  Set<String> exclude = const {},
  String country = defaultContactCountry,
}) {
  final seenNumbers = <String>{};
  final out = <InviteCandidate>[];
  for (final entry in book.entries) {
    if (exclude.contains(entry.id)) continue;
    String? best;
    var bestIsMobile = false;
    for (final phone in entry.phones) {
      final e164 = normaliseContactPhone(phone.number, country: country);
      if (e164 == null) continue;
      final mobile = isMobileNumber(e164, mobileLabel: phone.mobileLabel);
      if (best == null || (mobile && !bestIsMobile)) {
        best = e164;
        bestIsMobile = mobile;
      }
      if (bestIsMobile) break;
    }
    if (best == null || !seenNumbers.add(best)) continue;
    out.add(
      InviteCandidate(
        entryId: entry.id,
        name: entry.name,
        phone: best,
        isMobile: bestIsMobile,
        starred: entry.starred,
      ),
    );
  }

  int rank(InviteCandidate c) => (c.starred ? 0 : 2) + (c.isMobile ? 0 : 1);
  out.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    final aNamed = a.name.trim().isNotEmpty;
    final bNamed = b.name.trim().isNotEmpty;
    if (aNamed != bNamed) return aNamed ? -1 : 1;
    return foldForSearch(a.displayName).compareTo(foldForSearch(b.displayName));
  });
  return out;
}

/// The short list under "Nodig uit": mobile numbers only - the two ways an
/// invite goes out both need one - starred first, then alphabetical.
List<InviteCandidate> suggestedInvitees(List<InviteCandidate> all, {int count = 10}) {
  return [
    for (final candidate in all)
      if (candidate.isMobile && candidate.name.trim().isNotEmpty) candidate,
  ].take(count).toList(growable: false);
}

/// The search field: any word of the name starting with the query, or the
/// digits of the number containing it.
List<InviteCandidate> searchInvitees(
  List<InviteCandidate> all,
  String query, {
  int limit = 30,
}) {
  final folded = foldForSearch(query.trim());
  if (folded.isEmpty) return const [];
  final digits = query.replaceAll(RegExp(r'\D'), '');
  final out = <InviteCandidate>[];
  for (final candidate in all) {
    final name = foldForSearch(candidate.name);
    final byName = name.startsWith(folded) ||
        name.split(RegExp(r'\s+')).any((word) => word.startsWith(folded));
    // A national 06 and the stored +316 are the same number.
    final byNumber = digits.length >= 3 &&
        (candidate.waDigits.contains(digits) ||
            (digits.startsWith('0') && candidate.waDigits.contains(digits.substring(1))));
    if (byName || byNumber) out.add(candidate);
    if (out.length >= limit) break;
  }
  return out;
}

/// The message an invite carries: a greeting, then the reader's own invite
/// line with their personal link (the server's `shareText`, so the reward it
/// promises is the one the server will actually give).
String inviteMessage({String? firstName, String? shareText}) {
  final greeting = firstName == null ? 'Hoi,' : 'Hoi $firstName,';
  return '$greeting\n\n${inviteLine(shareText)}';
}

/// The reader's own invite line, or a plain one when the server's could not be
/// fetched (offline, an older deployment): the invite still goes out, just
/// without the personal link.
String inviteLine(String? shareText) => (shareText == null || shareText.trim().isEmpty)
    ? 'Ik gebruik BijbelStudie voor mijn bijbelstudie. Doe je mee? https://www.bijbelstudie.io'
    : shareText.trim();

/// How an invite went out.
enum InviteChannel { whatsapp, sms, share, none }

/// Opens the reader's own messaging app with the invite filled in. Behind an
/// interface so a widget test can count what would have been opened.
abstract class InviteLauncher {
  Future<InviteChannel> send(InviteCandidate candidate, String message, {Rect? origin});
}

/// WhatsApp straight to the contact, then the SMS app, then the share sheet.
///
/// WhatsApp only for a mobile number, because WhatsApp accounts are mobile
/// numbers. On iPhone `wa.me` is tried as a universal link that only an
/// installed WhatsApp may answer (`externalNonBrowserApplication`), so a phone
/// without it falls through instead of opening a web page; the `whatsapp://`
/// scheme is the second try. Android has no such guarantee for `wa.me` (it
/// would open the browser), so it uses the scheme. A launch that fails returns
/// false on iOS and throws on Android, so every attempt is wrapped.
class DeviceInviteLauncher implements InviteLauncher {
  const DeviceInviteLauncher();

  static Future<bool> _open(Uri uri, LaunchMode mode) async {
    try {
      return await launchUrl(uri, mode: mode);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<InviteChannel> send(InviteCandidate candidate, String message, {Rect? origin}) async {
    final text = Uri.encodeComponent(message);
    final ios = defaultTargetPlatform == TargetPlatform.iOS;

    if (candidate.isMobile) {
      final digits = candidate.waDigits;
      if (ios &&
          await _open(
            Uri.parse('https://wa.me/$digits?text=$text'),
            LaunchMode.externalNonBrowserApplication,
          )) {
        return InviteChannel.whatsapp;
      }
      if (await _open(
        Uri.parse('whatsapp://send?phone=$digits&text=$text'),
        LaunchMode.externalApplication,
      )) {
        return InviteChannel.whatsapp;
      }
    }

    // iOS reads the body after `&`, Android after `?`.
    final sms = Uri.parse('sms:${candidate.phone}${ios ? '&' : '?'}body=$text');
    if (await _open(sms, LaunchMode.externalApplication)) return InviteChannel.sms;

    try {
      await Share.share(message, sharePositionOrigin: origin);
      return InviteChannel.share;
    } catch (_) {
      return InviteChannel.none;
    }
  }
}

final inviteLauncherProvider = Provider<InviteLauncher>((ref) => const DeviceInviteLauncher());

/// The address book and what is known about it, for the app session.
@immutable
class ContactInvitesState {
  const ContactInvitesState({
    this.book,
    this.matchedEntryIds = const {},
    this.invitedEntryIds = const {},
  });

  /// Null until the book was read in this session.
  final AddressBook? book;

  /// Entries a match said already use BijbelStudie.
  final Set<String> matchedEntryIds;

  /// Entries the reader already sent an invite to.
  final Set<String> invitedEntryIds;

  ContactInvitesState copyWith({
    AddressBook? book,
    Set<String>? matchedEntryIds,
    Set<String>? invitedEntryIds,
  }) => ContactInvitesState(
    book: book ?? this.book,
    matchedEntryIds: matchedEntryIds ?? this.matchedEntryIds,
    invitedEntryIds: invitedEntryIds ?? this.invitedEntryIds,
  );
}

class ContactInvitesController extends Notifier<ContactInvitesState> {
  bool _loading = false;

  @override
  ContactInvitesState build() {
    Future.microtask(_restore);
    return const ContactInvitesState();
  }

  Future<void> _restore() async {
    try {
      final store = await ref.read(contactDiscoveryStoreProvider.future);
      state = state.copyWith(
        matchedEntryIds: state.matchedEntryIds.isEmpty ? store.matchedEntryIds : null,
        invitedEntryIds: {...store.invitedEntryIds, ...state.invitedEntryIds},
      );
    } catch (_) {
      // No preferences: nothing remembered, nothing broken.
    }
  }

  /// A book read by a match run.
  void putBook(AddressBook book) => state = state.copyWith(book: book);

  /// What a match run said about the book's entries.
  Future<void> putMatchedEntries(Set<String> ids) async {
    state = state.copyWith(matchedEntryIds: ids);
    try {
      final store = await ref.read(contactDiscoveryStoreProvider.future);
      await store.setMatchedEntryIds(ids);
    } catch (_) {}
  }

  /// Reads the book when the reader already connected their contacts, never
  /// showing a dialog. For a screen that opens after a restart.
  Future<void> loadIfConnected() async {
    if (state.book != null || _loading) return;
    _loading = true;
    try {
      final store = await ref.read(contactDiscoveryStoreProvider.future);
      if (store.disclosureAcceptedAt == null) return;
      final source = ref.read(contactsSourceProvider);
      if (!await source.hasAccess()) return;
      state = state.copyWith(book: await source.read());
    } catch (_) {
      // Unreadable now: the list stays as it was and the screen says so.
    } finally {
      _loading = false;
    }
  }

  /// Send one invite and remember the row as "Uitgenodigd" when something
  /// actually opened.
  Future<InviteChannel> invite(InviteCandidate candidate, {String? shareText, Rect? origin}) async {
    final message = inviteMessage(firstName: candidate.firstName, shareText: shareText);
    final channel = await ref.read(inviteLauncherProvider).send(candidate, message, origin: origin);
    if (channel == InviteChannel.none) return channel;
    state = state.copyWith(invitedEntryIds: {...state.invitedEntryIds, candidate.entryId});
    try {
      final store = await ref.read(contactDiscoveryStoreProvider.future);
      await store.markInvited(candidate.entryId);
    } catch (_) {}
    return channel;
  }

  /// "Contacten vergeten": nothing of the book stays in memory either.
  void clear() => state = const ContactInvitesState();
}

final contactInvitesProvider =
    NotifierProvider<ContactInvitesController, ContactInvitesState>(ContactInvitesController.new);

/// Everyone who could be invited, in "Nodig uit" order. Empty until the book
/// is read.
final inviteCandidatesProvider = Provider<List<InviteCandidate>>((ref) {
  final invites = ref.watch(contactInvitesProvider);
  final book = invites.book;
  if (book == null) return const [];
  return inviteCandidatesFrom(
    book,
    exclude: invites.matchedEntryIds,
    country: ref.watch(contactCountryProvider),
  );
});
