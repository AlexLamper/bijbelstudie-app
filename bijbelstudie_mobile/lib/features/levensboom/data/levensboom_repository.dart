import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';
import '../domain/tree_state.dart';

/// What a studio write came back with.
class LevensboomWrite {
  const LevensboomWrite.ok(this.tree) : error = null, label = null;

  const LevensboomWrite.failed(this.error, this.label) : tree = null;

  /// The fresh `levensboom` block, on success.
  final Map<String, dynamic>? tree;

  /// On failure: the server's code (`ITEM_LOCKED`, `INVALID_ITEM`, ...),
  /// `HTTP_<status>` for an answer without a JSON error body, or `NETWORK`
  /// when the host was never reached at all.
  final String? error;

  /// The rule, in Dutch ("Niveau 8"), when the server refused a locked pick.
  final String? label;

  bool get isOk => tree != null;
}

/// Reads the tree, and writes what the server stores about it.
///
/// The cache is not an optimisation - it is what makes the Profiel tab open
/// with the reader's own tree already on screen instead of a skeleton, which is
/// most of the point of putting it there. The cached copy renders immediately
/// on a cold start or with no network, and is replaced as soon as the request
/// lands. It carries the studio choice too, so the species is right offline.
class LevensboomRepository {
  LevensboomRepository(this._apiClient);

  final ApiClient _apiClient;

  static const _cacheKey = 'levensboom.lastState';

  Future<TreeState> fetch() async {
    final response = await _apiClient.dio.get('/gamification');
    final state = TreeState.fromJson(
      (response.data as Map).cast<String, dynamic>(),
    );
    await _cache(state);
    return state;
  }

  /// The last good state, or null. Best-effort: a device with no preferences
  /// plugin simply starts from the network.
  Future<TreeState?> cached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      return TreeState.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> cache(TreeState state) => _cache(state);

  /// Forgets the cached tree. Runs on sign-out, so whoever signs in next -
  /// a different account, or the same address re-created after a deletion -
  /// never opens on the previous reader's tree.
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (_) {
      // Nothing cached, or no preferences plugin: nothing to forget.
    }
  }

  Future<void> _cache(TreeState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(state.toJson()));
    } catch (_) {
      // A tree that cannot be cached still renders; nothing to report.
    }
  }

  /// Marks the celebration as seen and/or writes the two prefs.
  ///
  /// The marker lives on the account rather than on the device, so a level-up
  /// earned on the website is celebrated once here and not again.
  Future<void> markSeen({int? level, bool? reducedMotion, bool? disabled}) async {
    await _apiClient.dio.post(
      '/gamification/seen',
      data: {
        if (level != null) 'level': level,
        if (reducedMotion != null) 'reducedMotion': reducedMotion,
        if (disabled != null) 'disabled': disabled,
      },
    );
  }

  /// The studio's write. The server checks every id against the catalog and
  /// today's unlocks; a refused pick comes back as a failure carrying the rule
  /// rather than as an exception, because "Niveau 8" is an answer, not an
  /// error.
  Future<LevensboomWrite> patchAvatar(Map<String, Object?> body) async {
    try {
      final response = await _apiClient.dio.patch('/levensboom', data: body);
      final data = response.data;
      if (data is Map && data['levensboom'] is Map) {
        return LevensboomWrite.ok((data['levensboom'] as Map).cast<String, dynamic>());
      }
      return const LevensboomWrite.failed('MALFORMED', null);
    } on DioException catch (e) {
      final response = e.response;
      // No response at all: connection refused, DNS, timeout. In a debug build
      // that is a local dev server that is not running.
      if (response == null) return const LevensboomWrite.failed('NETWORK', null);
      final data = response.data;
      if (data is Map && data['error'] is String) {
        return LevensboomWrite.failed(data['error'] as String, data['label'] as String?);
      }
      // A status without a JSON error body: the HTML not-found page of a
      // deployment that predates this route, an empty 405, a redirect. That
      // used to be folded into NETWORK, which hid the one thing worth knowing.
      return LevensboomWrite.failed('HTTP_${response.statusCode}', null);
    } catch (_) {
      return const LevensboomWrite.failed('NETWORK', null);
    }
  }
}

final levensboomRepositoryProvider = Provider<LevensboomRepository>((ref) {
  return LevensboomRepository(ref.watch(apiClientProvider));
});
