import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';

final contextRepositoryProvider = Provider((ref) {
  return ContextRepository(ref.watch(apiClientProvider));
});

class GeoImage {
  const GeoImage({
    required this.url,
    required this.placeName,
    required this.credit,
    required this.license,
    this.description,
  });

  final String url;
  final String placeName;

  /// CC attribution has to be shown, not merely stored.
  final String credit;
  final String license;

  final String? description;

  static GeoImage? fromJson(Map<String, dynamic> json) {
    final url = (json['thumbnailUrl'] ?? json['url']) as String?;
    if (url == null || url.isEmpty) return null;
    return GeoImage(
      url: url,
      placeName: json['placeName'] as String? ?? '',
      credit: json['credit'] as String? ?? '',
      license: json['license'] as String? ?? '',
      description: json['description'] as String?,
    );
  }
}

/// The "Algemene info" tab: a public-domain introduction to the book plus
/// photographs of the places it names.
class ContextRepository {
  ContextRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<String?> getBookSummary(String book, {String lang = 'nl'}) async {
    try {
      final response = await _apiClient.dio.get(
        '/summary',
        queryParameters: {'book': book, 'lang': lang},
      );
      return (response.data as Map<String, dynamic>)['summary'] as String?;
    } catch (_) {
      // 404 simply means this book has no introduction yet.
      return null;
    }
  }

  Future<List<GeoImage>> getGeoImages(String book, int chapter) async {
    try {
      final response = await _apiClient.dio.get(
        '/geo/images',
        queryParameters: {'book': book, 'chapter': chapter},
      );
      final data = response.data as Map<String, dynamic>;
      return (data['images'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(GeoImage.fromJson)
          .whereType<GeoImage>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}

final bookSummaryProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, book) {
      return ref.watch(contextRepositoryProvider).getBookSummary(book);
    });

/// (book, chapter) — a value type so the family caches by content, not by
/// instance identity.
class GeoRef {
  const GeoRef(this.book, this.chapter);

  final String book;
  final int chapter;

  @override
  bool operator ==(Object other) =>
      other is GeoRef && other.book == book && other.chapter == chapter;

  @override
  int get hashCode => Object.hash(book, chapter);
}

final geoImagesProvider =
    FutureProvider.autoDispose.family<List<GeoImage>, GeoRef>((ref, geoRef) {
      return ref
          .watch(contextRepositoryProvider)
          .getGeoImages(geoRef.book, geoRef.chapter);
    });
