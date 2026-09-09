import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The last good response for a screen that would otherwise open on a skeleton.
///
/// Same idea as `LevensboomRepository`'s tree cache, generalised: the Start and
/// Profiel tabs both gate on a single request, so on a cold start the reader
/// watched a skeleton for as long as the server took. With this the screen
/// renders its real content on the first frame and the request replaces it when
/// it lands.
///
/// Deliberately dumb: one JSON blob per key in `SharedPreferences`, no
/// migrations, no schema. A payload that cannot be parsed - because the API
/// changed shape since it was written - is dropped and the screen simply waits
/// for the network, exactly as it did before.
class PayloadCache {
  const PayloadCache._();

  static const _prefix = 'payload.';

  /// Old enough that the cached copy is more likely to mislead than to help.
  /// A week covers "opened the app on holiday with no signal"; beyond that the
  /// streak and the badges would be telling the reader something untrue.
  static const maxAge = Duration(days: 7);

  static Future<Map<String, dynamic>?> read(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;
      final envelope = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final written = DateTime.tryParse(envelope['at'] as String? ?? '');
      if (written == null || DateTime.now().difference(written) > maxAge) {
        return null;
      }
      final body = envelope['body'];
      if (body is! Map) return null;
      return body.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, Map<String, dynamic>? body) async {
    if (body == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefix$key',
        jsonEncode({'at': DateTime.now().toIso8601String(), 'body': body}),
      );
    } catch (_) {
      // A screen that cannot cache still renders; nothing to report.
    }
  }

  /// Runs on sign-out: the next account must never see the previous reader's
  /// figures on its first frame.
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
        await prefs.remove(key);
      }
    } catch (_) {
      // Nothing cached, or no preferences plugin: nothing to forget.
    }
  }
}
