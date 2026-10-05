import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything the vriendenkring notifications remember between foregrounds.
///
/// Three jobs, all of them small, all of them in `SharedPreferences` under the
/// same `notif.social.` prefix the rest of the notification preferences use:
///
/// 1. **the cursor** - where the last pull of `GET /notifications/social` got
///    to, so the next one asks for what came after and nothing is replayed;
/// 2. **the delivered ledger** - what has already been shown, whichever path
///    showed it. This is the dedupe, and it holds two shapes of key on purpose:
///    - `<id>@<createdAt>` for an event the pull handled. The server keeps a
///      friend request's id stable across a re-open (a declined verzoek sent
///      again is the same document) and moves its timestamp instead, so "the
///      same event again" is the id *and* the timestamp;
///    - a bare `<id>` for an event a real APNs push delivered, written by
///      `AppDelegate` -> `onPushDelivered` from the payload's `eventId`. A bare
///      id matches every timestamp, which is right: APNs collapses the re-open
///      onto the same notification, so iOS has seen it either way.
///
///    [SocialNotificationStore.wasDelivered] checks both;
/// 3. **the switch and the one-shot permission guard** - `NotificationPrefs`
///    has no field for the social kinds (`enabledFor` answers false for an id
///    it does not know), and that file belongs to the settings screen, so the
///    switch lives here until a settings row exists. Default on, and still
///    subordinate to `NotificationPrefs.masterEnabled`.
///
/// Every read is total: a broken or missing value reads as the default rather
/// than throwing on a foreground.
class SocialNotificationStore {
  const SocialNotificationStore._();

  static const _p = 'notif.social.';

  static const cursorKey = '${_p}cursor';
  static const deliveredKey = '${_p}delivered';
  static const enabledKey = '${_p}enabled';
  static const askSpentKey = '${_p}askSpent';
  static const deviceTokenKey = '${_p}deviceToken';
  static const deviceTokenAtKey = '${_p}deviceTokenAt';
  static const slotKey = '${_p}slot';

  /// How many event ids the ledger keeps. A pull asks for at most 50 at a time
  /// and the cursor normally means the same id is never offered twice, so this
  /// is only there for the cases where it is: a cursor that failed to persist,
  /// a server that re-sends, a push and a pull racing each other.
  static const maxDelivered = 300;

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('[Social] prefs unavailable: $e');
      return null;
    }
  }

  // ── Cursor ────────────────────────────────────────────────────────────────

  static Future<String?> cursor() async {
    final value = (await _prefs())?.getString(cursorKey);
    return value == null || value.isEmpty ? null : value;
  }

  /// Written only after the page's events have been handled, so a crash in the
  /// middle replays rather than loses - the ledger then stops the replay from
  /// becoming a second notification.
  static Future<void> setCursor(String? value) async {
    final prefs = await _prefs();
    if (prefs == null) return;
    if (value == null || value.isEmpty) {
      await prefs.remove(cursorKey);
    } else {
      await prefs.setString(cursorKey, value);
    }
  }

  // ── Delivered ledger ──────────────────────────────────────────────────────

  static Future<List<String>> delivered() async {
    final raw = (await _prefs())?.getString(deliveredKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {}
    return const [];
  }

  /// Marks [ids] as shown. Newest last; the oldest beyond [maxDelivered] are
  /// dropped.
  static Future<void> markDelivered(Iterable<String> ids) async {
    final add = ids.where((id) => id.isNotEmpty).toList();
    if (add.isEmpty) return;
    final prefs = await _prefs();
    if (prefs == null) return;
    final kept = [...await delivered()];
    for (final id in add) {
      kept.remove(id);
      kept.add(id);
    }
    final trimmed = kept.length <= maxDelivered
        ? kept
        : kept.sublist(kept.length - maxDelivered);
    try {
      await prefs.setString(deliveredKey, jsonEncode(trimmed));
    } catch (e) {
      debugPrint('[Social] ledger write failed: $e');
    }
  }

  /// One bare event id, for the push callback: it arrives one at a time and must
  /// be recorded even when no pull is running.
  static Future<void> markDeliveredOne(String id) => markDelivered([id]);

  /// Whether this event has already been shown. [ledger] is one read of
  /// [delivered], so a page of fifty does not read the preferences fifty times.
  ///
  /// [eventId] alone is what a push wrote; [ledgerKey] is `<id>@<createdAt>`,
  /// what the pull writes. Either hit means "shown".
  static bool wasDelivered(
    Set<String> ledger, {
    required String eventId,
    required String ledgerKey,
  }) =>
      ledger.contains(eventId) || ledger.contains(ledgerKey);

  // ── Switch ────────────────────────────────────────────────────────────────

  /// On unless the reader turned it off. Nothing is shown without OS
  /// permission anyway, so the default only decides what happens once
  /// permission is there.
  static Future<bool> enabled() async =>
      (await _prefs())?.getBool(enabledKey) ?? true;

  static Future<void> setEnabled(bool value) async =>
      (await _prefs())?.setBool(enabledKey, value);

  // ── The one social permission ask ─────────────────────────────────────────

  /// Whether the social pre-permission sheet has been offered. Separate from
  /// `RetentionState.permissionAskedAfterFirstLesson`: accepting a friend is a
  /// reason of its own, so it is offered even when the reading ask was spent -
  /// but still only once.
  static Future<bool> askSpent() async =>
      (await _prefs())?.getBool(askSpentKey) ?? false;

  static Future<void> markAskSpent() async =>
      (await _prefs())?.setBool(askSpentKey, true);

  // ── APNs device token ─────────────────────────────────────────────────────

  static Future<String?> deviceToken() async {
    final value = (await _prefs())?.getString(deviceTokenKey);
    return value == null || value.isEmpty ? null : value;
  }

  static Future<DateTime?> deviceTokenAt() async {
    final ms = (await _prefs())?.getInt(deviceTokenAtKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> setDeviceToken(String token) async {
    final prefs = await _prefs();
    if (prefs == null) return;
    await prefs.setString(deviceTokenKey, token);
    await prefs.setInt(deviceTokenAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> clearDeviceToken() async {
    final prefs = await _prefs();
    if (prefs == null) return;
    await prefs.remove(deviceTokenKey);
    await prefs.remove(deviceTokenAtKey);
  }

  // ── Notification id rotation ──────────────────────────────────────────────

  /// The next index into a social type's `idRange`, so two hartjes sit in the
  /// tray side by side instead of one replacing the other.
  static Future<int> nextSlot(int length) async {
    if (length <= 1) return 0;
    final prefs = await _prefs();
    if (prefs == null) return 0;
    final next = ((prefs.getInt(slotKey) ?? 0) + 1) % 100000;
    await prefs.setInt(slotKey, next);
    return next % length;
  }

  // ── Sign-out ──────────────────────────────────────────────────────────────

  /// Everything here belongs to one account: the cursor is their place in
  /// their own feed and the ledger is what they were shown.
  static Future<void> clearForSignOut() async {
    final prefs = await _prefs();
    if (prefs == null) return;
    for (final key in [cursorKey, deliveredKey, deviceTokenKey, deviceTokenAtKey]) {
      await prefs.remove(key);
    }
  }
}
