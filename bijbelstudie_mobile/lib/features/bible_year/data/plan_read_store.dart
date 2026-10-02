import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What this device ticked and unticked in "Bijbel in een jaar", as `readRefs`
/// keys ("GEN.1").
///
/// The API's enrollment DTO answers with counts only, never the `readRefs`
/// list (see [planReadRefKeys]), so a tick that the server accepted is gone
/// from the state the very next mutation response. This store keeps it: it is
/// the device's memory of its own marks, merged over the server's answer, and
/// it is what makes a tick stick at once, across a restart, and offline.
///
/// Both halves are kept. Without [unread] an untick would be undone on the
/// next frame by the dashboard's read map, which `POST /last-read` fills and
/// the plan cannot clear.
class PlanReadMarks {
  const PlanReadMarks({this.read = const {}, this.unread = const {}, this.loaded = false});

  final Set<String> read;
  final Set<String> unread;

  /// False until shared_preferences has answered, so a merge done before that
  /// is not mistaken for "nothing ticked here".
  final bool loaded;
}

final planReadStoreProvider =
    NotifierProvider<PlanReadStore, PlanReadMarks>(PlanReadStore.new);

class PlanReadStore extends Notifier<PlanReadMarks> {
  static const _readKey = 'bibleYear.deviceReadRefs';
  static const _unreadKey = 'bibleYear.deviceUnreadRefs';

  final Completer<void> _loaded = Completer<void>();

  Future<void> get loaded => _loaded.future;

  @override
  PlanReadMarks build() {
    unawaited(_load());
    return const PlanReadMarks();
  }

  Future<void> _load() async {
    Set<String> read = const {};
    Set<String> unread = const {};
    try {
      final prefs = await SharedPreferences.getInstance();
      read = (prefs.getStringList(_readKey) ?? const []).toSet();
      unread = (prefs.getStringList(_unreadKey) ?? const []).toSet();
    } catch (_) {
      // No store on this platform, or it could not be read: the server's
      // answer alone still renders.
    }
    // The container can be gone by now (a test, a sign-out rebuild).
    if (ref.mounted) {
      state = PlanReadMarks(read: read, unread: unread, loaded: true);
    }
    if (!_loaded.isCompleted) _loaded.complete();
  }

  /// [keys] read ([read] true) or explicitly not read.
  Future<void> mark(Iterable<String> keys, bool read) async {
    final touched = keys.where((k) => k.isNotEmpty).toSet();
    if (touched.isEmpty) return;
    final current = state;
    final nextRead = read
        ? {...current.read, ...touched}
        : current.read.difference(touched);
    final nextUnread = read
        ? current.unread.difference(touched)
        : {...current.unread, ...touched};
    if (nextRead.length == current.read.length &&
        nextUnread.length == current.unread.length &&
        current.loaded) {
      return;
    }
    state = PlanReadMarks(read: nextRead, unread: nextUnread, loaded: current.loaded);
    await _persist(nextRead, nextUnread);
  }

  /// A new plan ("Opnieuw beginnen"): drop the unticks, so the reader's own
  /// read chapters count towards the new run again.
  Future<void> clearUnread() async {
    if (state.unread.isEmpty) return;
    state = PlanReadMarks(read: state.read, loaded: state.loaded);
    await _persist(state.read, const {});
  }

  Future<void> _persist(Set<String> read, Set<String> unread) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_readKey, read.toList(growable: false));
      await prefs.setStringList(_unreadKey, unread.toList(growable: false));
    } catch (_) {
      // Best effort; the server has the mark either way.
    }
  }
}
