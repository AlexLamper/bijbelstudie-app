import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';

final contextRepositoryProvider = Provider((ref) {
  return ContextRepository(ref.watch(apiClientProvider));
});

class GeoImage {
  const GeoImage({
    required this.fileUrl,
    required this.placeName,
    required this.credit,
    required this.license,
    this.description,
    this.fromBook = false,
  });

  /// The original `upload.wikimedia.org` file. Always resolvable, but routinely
  /// a 3-10 MB, 5000px photograph, so it is only ever rendered through
  /// [sizedUrl] - see there for why the endpoint's own `thumbnailUrl` is not
  /// used at all.
  final String fileUrl;

  final String placeName;

  /// CC attribution has to be shown, not merely stored.
  final String credit;
  final String license;

  final String? description;

  /// True when the endpoint answered with the book's images because the
  /// chapter itself names no place - see [ContextRepository.getGeoImages].
  final bool fromBook;

  /// A copy of the photograph resized to [width] px, via Wikimedia's own
  /// `Special:FilePath`.
  ///
  /// The endpoint sends a `thumbnailUrl` built by substituting a width into
  /// Wikimedia's `thumb/` URL pattern, and that URL does not load: for most
  /// files upload.wikimedia.org answers an arbitrary width with
  /// `400 Use thumbnail sizes listed on https://w.wiki/GHai`. Rendering it is
  /// why this step showed nothing but broken-image boxes. `Special:FilePath`
  /// is the documented resize entry point and accepts any width, so the
  /// thumbnail is derived from [fileUrl] here instead of trusting the pattern.
  ///
  /// Falls back to [fileUrl] for anything not hosted on Wikimedia, which
  /// costs bandwidth but always renders.
  String sizedUrl(int width) {
    final uri = Uri.tryParse(fileUrl);
    if (uri == null || !uri.host.endsWith('wikimedia.org')) return fileUrl;
    final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (name.isEmpty) return fileUrl;
    // The segment is already percent-encoded in the source URL and must stay
    // that way: several of these filenames are Arabic or Hebrew.
    return 'https://commons.wikimedia.org/wiki/Special:FilePath/$name'
        '?width=$width';
  }

  static GeoImage? fromJson(Map<String, dynamic> json, {bool fromBook = false}) {
    // `url` is the file itself; `thumbnailUrl` is deliberately ignored - see
    // [sizedUrl].
    final file = json['url'] as String?;
    if (file == null || file.isEmpty) return null;
    return GeoImage(
      fileUrl: file,
      placeName: json['placeName'] as String? ?? '',
      credit: json['credit'] as String? ?? '',
      license: json['license'] as String? ?? '',
      description: json['description'] as String?,
      fromBook: fromBook,
    );
  }
}

/// Wikimedia refuses a request with no User-Agent outright (403) and asks for a
/// descriptive one by policy, so every image request from this app sends these.
const Map<String, String> wikimediaImageHeaders = {
  'User-Agent': 'BijbelStudie/1.0 (https://www.bijbelstudie.io; '
      'info@bijbelstudie.io)',
};

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
