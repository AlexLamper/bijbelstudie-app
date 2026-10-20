import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'contacts/contact_discovery_providers.dart';
import 'contacts/contacts_source.dart';
import 'friends_providers.dart';

/// The state around the way into Vriendenkring: whether the address book is
/// connected, whether the screen should show only the "Verbind Contacten"
/// invitation, and whether the Start tab's header button wears its red dot.
///
/// Everything here reads; nothing asks the OS for anything. The permission
/// prompt stays behind `ContactsDisclosureScreen`, as before.

/// Whether the reader has connected their contacts: the disclosure was passed
/// once and the OS permission is still granted, in full or (iOS 18+) limited.
/// [ContactsSource.hasAccess] only reads the status, so this never shows a
/// dialog.
///
/// Revoking access in Settings makes this false again, so the invitation comes
/// back - the screen re-reads it when the app returns to the foreground.
/// Watches the matching run's stage, so a finished run updates it at once.
final contactsConnectedProvider = FutureProvider<bool>((ref) async {
  final stage = ref.watch(contactDiscoveryProvider.select((state) => state.stage));
  if (stage == ContactDiscoveryStage.matched) return true;
  final store = await ref.watch(contactDiscoveryStoreProvider.future);
  if (store.disclosureAcceptedAt == null) return false;
  return ref.read(contactsSourceProvider).hasAccess();
});

/// True while contact matching is on but the reader has not connected their
/// contacts and has no kring yet: Vriendenkring then shows the "Verbind
/// Contacten" invitation instead of an empty feed, and Start leaves out its
/// friends card altogether.
///
/// A reader who already has friends (through a code or a link) keeps their
/// feed either way: hiding a kring they built would take away something that
/// works, and the contacts are meant to stay optional.
///
/// False while anything is still unknown, so nothing flashes away and back.
final friendsContactsGateProvider = Provider<bool>((ref) {
  if (ref.watch(contactDiscoveryOfferedProvider).value != true) return false;
  if (ref.watch(contactsConnectedProvider).value != false) return false;
  final feed = ref.watch(friendsFeedProvider);
  final value = feed.value;
  if (value == null) return feed.hasError;
  return !value.hasFriends;
});

/// What the reader has already seen of Vriendenkring, kept on the device.
class FriendsEntrySeen {
  const FriendsEntrySeen({this.openedAt, this.suggestionIds = const {}});

  /// When Vriendenkring was last opened, or null if never.
  final DateTime? openedAt;

  /// The "Mensen die je misschien kent" people already shown once.
  final Set<String> suggestionIds;
}

class FriendsEntrySeenNotifier extends AsyncNotifier<FriendsEntrySeen> {
  static const _openedAtKey = 'friends.entry.openedAt';
  static const _suggestionIdsKey = 'friends.entry.seenSuggestionIds';

  /// Enough for every suggestion the server sends (`maxFriendSuggestions`) a
  /// few times over, without the list growing for ever.
  static const _maxRemembered = 200;

  @override
  Future<FriendsEntrySeen> build() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_openedAtKey);
    return FriendsEntrySeen(
      openedAt: millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis),
      suggestionIds: (prefs.getStringList(_suggestionIdsKey) ?? const <String>[]).toSet(),
    );
  }

  /// Vriendenkring was opened, with these suggestions on screen.
  Future<void> markOpened({Iterable<String> suggestionIds = const []}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final seen = await future;
    final ids = _merge(seen.suggestionIds, suggestionIds);
    await prefs.setInt(_openedAtKey, now.millisecondsSinceEpoch);
    await prefs.setStringList(_suggestionIdsKey, ids.toList(growable: false));
    state = AsyncData(FriendsEntrySeen(openedAt: now, suggestionIds: ids));
  }

  /// Suggestions that arrived while the screen was already open.
  Future<void> markSuggestionsSeen(Iterable<String> suggestionIds) async {
    final seen = await future;
    if (suggestionIds.every(seen.suggestionIds.contains)) return;
    final ids = _merge(seen.suggestionIds, suggestionIds);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_suggestionIdsKey, ids.toList(growable: false));
    state = AsyncData(FriendsEntrySeen(openedAt: seen.openedAt, suggestionIds: ids));
  }

  static Set<String> _merge(Set<String> old, Iterable<String> added) {
    // Newest last, and the oldest dropped first once the cap is reached.
    final merged = <String>{...old.where((id) => !added.contains(id)), ...added}
      ..removeWhere((id) => id.trim().isEmpty);
    if (merged.length <= _maxRemembered) return merged;
    return merged.skip(merged.length - _maxRemembered).toSet();
  }
}

final friendsEntrySeenProvider =
    AsyncNotifierProvider<FriendsEntrySeenNotifier, FriendsEntrySeen>(
      FriendsEntrySeenNotifier.new,
    );

/// How long after a visit the "connect your contacts" dot may come back.
///
/// The dot is a nudge, not a nag: it shows while the contacts are not
/// connected, goes out when Vriendenkring is opened, and returns a week later
/// if they still are not.
const contactsNudgeInterval = Duration(days: 7);

/// The red dot on the Start tab's Vriendenkring button.
///
/// On when any of these holds, and off once the screen has been opened and
/// none is left:
///
/// * contact matching is on, the contacts are not connected, and Vriendenkring
///   was not opened in the last [contactsNudgeInterval];
/// * a verzoek is waiting for an answer (it stays until it is answered);
/// * "Mensen die je misschien kent" holds someone not shown before.
///
/// The count badge for new posts ([friendsBadgeProvider]) is separate and
/// wins: a number already says "go there".
///
/// Only builds with contact matching on read the kring and the suggestions
/// from Start for this; elsewhere the button behaves exactly as before and
/// costs no extra request.
final friendsEntryDotProvider = Provider<bool>((ref) {
  if (ref.watch(contactDiscoveryOfferedProvider).value != true) return false;
  final seen = ref.watch(friendsEntrySeenProvider).value;
  if (seen == null) return false;

  final connected = ref.watch(contactsConnectedProvider).value;
  if (connected == false) {
    final opened = seen.openedAt;
    if (opened == null || DateTime.now().difference(opened) >= contactsNudgeInterval) {
      return true;
    }
  }

  if ((ref.watch(friendsKringProvider).value?.pendingIncoming ?? 0) > 0) return true;

  final suggestions =
      ref.watch(friendSuggestionsProvider).value?.suggestions ?? const [];
  return suggestions.any((person) => !seen.suggestionIds.contains(person.userId));
});
