import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';
import '../domain/tree_state.dart';

/// Reads the tree, and writes the two things about it the server stores.
///
/// The cache is not an optimisation - it is what makes the Profiel tab open
/// with the reader's own tree already on screen instead of a skeleton, which is
/// most of the point of putting it there. The cached copy renders immediately
/// on a cold start or with no network, and is replaced as soon as the request
/// lands.
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
}

final levensboomRepositoryProvider = Provider<LevensboomRepository>((ref) {
  return LevensboomRepository(ref.watch(apiClientProvider));
});
