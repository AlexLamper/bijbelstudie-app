import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../friends/data/friend_models.dart';
import '../../friends/data/friends_repository.dart';

/// Which switch in the Vriendenkring section was flipped.
///
/// One enum rather than four methods, because every switch does the same two
/// things - flip one named path, adopt the whole answer - and the mapping to
/// [FriendSettingsUpdate] is the only part that differs.
enum VriendenkringSwitch { discoverable, milestones, verses, notes }

/// The reader's own vriendenkring settings, and the writes back.
///
/// Instellingen needs more than the kring's own read-only
/// `friendsSettingsProvider`: it writes. `PATCH /friends/settings` answers with
/// the complete settings object, so a flip adopts [FriendSettingsResult.settings]
/// wholesale instead of patching its own copy - that is how turning on "verzen"
/// cannot leave this screen believing something stale about "mijlpalen".
///
/// The switch does move before the server answers, or a tap would sit there
/// doing nothing for a round trip; that optimistic value is replaced by the
/// server's answer, or put back when the write failed.
class VriendenkringSettingsNotifier extends AsyncNotifier<FriendSettings> {
  @override
  Future<FriendSettings> build() {
    return ref.watch(friendsRepositoryProvider).getSettings();
  }

  /// Flips one switch. Returns the result so the screen can print the server's
  /// own line when it did not land.
  Future<FriendSettingsResult> setSwitch(
    VriendenkringSwitch which,
    bool value,
  ) async {
    final current = state.value;
    if (current != null) state = AsyncData(_optimistic(current, which, value));

    final result = await ref
        .read(friendsRepositoryProvider)
        .updateSettings(_update(which, value));

    final settled = result.settings;
    if (result.ok && settled != null) {
      state = AsyncData(settled);
    } else if (!result.ok && current != null) {
      // The switch goes back where it was; the screen says why.
      state = AsyncData(current);
    }
    return result;
  }

  /// Throws away the contact hashes. On success the settings are refetched:
  /// `hasContactHashes` is what the row is gated on, and the server also turns
  /// findability off with it, so neither value may be guessed here.
  Future<bool> forgetContacts() async {
    final ok = await ref.read(friendsRepositoryProvider).forgetContactDiscovery();
    if (ok) ref.invalidateSelf();
    return ok;
  }

  static FriendSettings _optimistic(
    FriendSettings from,
    VriendenkringSwitch which,
    bool value,
  ) {
    final share = from.autoShare;
    return switch (which) {
      VriendenkringSwitch.discoverable => from.copyWith(discoverable: value),
      VriendenkringSwitch.milestones => from.copyWith(
        autoShare: FriendAutoShare(
          milestones: value,
          verses: share.verses,
          notes: share.notes,
        ),
      ),
      VriendenkringSwitch.verses => from.copyWith(
        autoShare: FriendAutoShare(
          milestones: share.milestones,
          verses: value,
          notes: share.notes,
        ),
      ),
      VriendenkringSwitch.notes => from.copyWith(
        autoShare: FriendAutoShare(
          milestones: share.milestones,
          verses: share.verses,
          notes: value,
        ),
      ),
    };
  }

  /// One named path per switch - never the whole `autoShare` object, which
  /// would reset the two switches the reader did not touch.
  static FriendSettingsUpdate _update(VriendenkringSwitch which, bool value) {
    return switch (which) {
      VriendenkringSwitch.discoverable =>
        FriendSettingsUpdate(discoverable: value),
      VriendenkringSwitch.milestones =>
        FriendSettingsUpdate(autoShareMilestones: value),
      VriendenkringSwitch.verses => FriendSettingsUpdate(autoShareVerses: value),
      VriendenkringSwitch.notes => FriendSettingsUpdate(autoShareNotes: value),
    };
  }
}

final vriendenkringSettingsProvider =
    AsyncNotifierProvider<VriendenkringSettingsNotifier, FriendSettings>(
      VriendenkringSettingsNotifier.new,
    );
