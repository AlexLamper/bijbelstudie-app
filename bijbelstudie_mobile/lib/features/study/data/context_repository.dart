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
    this.fullUrl,
    this.description,
    this.fromBook = false,
  });

  /// What to render: the endpoint's 640px `thumbnailUrl` when it sent one,
  /// which is the right size for a phone card, otherwise the file itself.
  final String url;

  /// The full `upload.wikimedia.org` file behind [url]. Kept so a thumbnail
  /// that does not resolve has something to fall back to instead of a grey box.
  final String? fullUrl;

  final String placeName;

  /// CC attribution has to be shown, not merely stored.
  final String credit;
  final String license;

  final String? description;

  /// True when the endpoint answered with the book's images because the
  /// chapter itself names no place - see [ContextRepository.getGeoImages].
  final bool fromBook;

  static GeoImage? fromJson(Map<String, dynamic> json, {bool fromBook = false}) {
    final file = json['url'] as String?;
    final thumbnail = json['thumbnailUrl'] as String?;
    final url = (thumbnail?.isNotEmpty ?? false) ? thumbnail! : file;
    if (url == null || url.isEmpty) return null;
    return GeoImage(
      url: url,
      fullUrl: (file?.isNotEmpty ?? false) ? file : null,
      placeName: json['placeName'] as String? ?? '',
      credit: json['credit'] as String? ?? '',
      license: json['license'] as String? ?? '',
      description: json['description'] as String?,
      fromBook: fromBook,
    );
  }
}

/// The "Algemene info" tab: a public-domain introduction to the book plus
/// photographs of the places it names.
class ContextRepository {
  ContextRepository(this._apiClient);

  final ApiClient _apiClient;

  /// How many photographs are ever worth showing. The endpoint can answer with
  /// a dozen for a well-documented book, which on a phone is a scroll nobody
  /// finishes.
  static const int imageLimit = 5;

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

  /// Photographs for a chapter, falling back to the book's own.
  ///
  /// `fallback=book` matters more than it looks: most chapters name no place at
  /// all, so without it the endpoint answers with an empty list and the panel
  /// reads as broken rather than as "nothing here". The response says which of
  /// the two it gave back in `scope`, and that is carried onto every image so
  /// the panel can say whose places these are.
  Future<List<GeoImage>> getGeoImages(
    String book,
    int chapter, {
    int limit = imageLimit,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/geo/images',
        queryParameters: {'book': book, 'chapter': chapter, 'fallback': 'book'},
      );
      final data = response.data as Map<String, dynamic>;
      final fromBook = data['scope'] == 'book';
      return (data['images'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((json) => GeoImage.fromJson(json, fromBook: fromBook))
          .whereType<GeoImage>()
          .take(limit)
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
