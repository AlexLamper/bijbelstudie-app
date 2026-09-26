import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../domain/bronnen_models.dart';
import 'bronnen_store.dart';

/// Reads `/api/v1/bronnen` and `/api/v1/bronnen/<slug>`, with an offline copy.
///
/// Both endpoints are static on the server (prerendered, no auth). The index
/// is small and always asked for fresh, falling back on its last copy when
/// the network is gone. A work is large and changes rarely, so it is served
/// from the device whenever its cached `version` matches the index's, and
/// fetched only when the version moved or it was never read. A work that was
/// read once therefore opens offline for good.
class BronnenRepository {
  BronnenRepository(this._apiClient, this._store);

  final ApiClient _apiClient;
  final BronnenStore _store;

  static const indexKey = 'index';
  static String workKey(String slug) => 'work.$slug';

  Future<BronnenIndex> getIndex() async {
    try {
      final response = await _apiClient.dio.get('/bronnen');
      final data = response.data;
      if (data is! Map) throw const FormatException('Onverwacht antwoord');
      final body = data.cast<String, dynamic>();
      await _store.write(indexKey, body);
      return BronnenIndex.fromJson(body);
    } catch (error) {
      final cached = await _store.read(indexKey);
      if (cached != null) return BronnenIndex.fromJson(cached);
      throw Exception(_message(error, 'Bronnen konden niet worden geladen.'));
    }
  }

  /// The work in full. [version] is the index's current version for [slug],
  /// or null when the index could not be had - then any cached copy is good
  /// enough.
  Future<BronWork> getWork(String slug, {String? version}) async {
    final cached = await _readWork(slug);
    if (cached != null && (version == null || version.isEmpty || cached.version == version)) {
      return cached;
    }

    try {
      final response = await _apiClient.dio.get('/bronnen/${Uri.encodeComponent(slug)}');
      final data = response.data;
      if (data is! Map) throw const FormatException('Onverwacht antwoord');
      final body = data.cast<String, dynamic>();
      final work = BronWork.fromJson(body);
      if (work.sections.isEmpty) throw const FormatException('Lege tekst');
      await _store.write(workKey(slug), body);
      return work;
    } catch (error) {
      // An outdated copy beats no text at all.
      if (cached != null) return cached;
      throw Exception(_message(error, 'Deze tekst kon niet worden geladen.'));
    }
  }

  /// The copy on this device, if any, without touching the network.
  Future<BronWork?> cachedWork(String slug) => _readWork(slug);

  Future<BronWork?> _readWork(String slug) async {
    final json = await _store.read(workKey(slug));
    if (json == null) return null;
    try {
      final work = BronWork.fromJson(json);
      return work.sections.isEmpty ? null : work;
    } catch (_) {
      return null;
    }
  }

  String _message(Object error, String fallback) {
    if (error is DioException) {
      if (error.response?.statusCode == 404) return 'Deze tekst bestaat niet (meer).';
      return 'Geen verbinding. $fallback';
    }
    return fallback;
  }
}
