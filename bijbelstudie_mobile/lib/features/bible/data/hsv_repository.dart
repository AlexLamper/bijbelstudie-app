import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';

/// The Herziene Statenvertaling, inside the free-of-charge allowance Stichting
/// HSV grants - fifty verses, no more, with the source named.
///
/// The web side holds the rules and the list (`lib/hsvQuota.ts` there); this is
/// a reader of the two endpoints it exposes, and deliberately nothing else:
///
///   GET /bibles/hsv              which verses may be quoted - coordinates only
///   GET /bibles/hsv/:book/:ch    the text of those verses in one chapter
///
/// There is no chapter endpoint for the HSV and no `hsv` entry in `/bibles`, so
/// the app can never offer it as a translation to read. It is a quotation shown
/// beside a verse, which is what the licence allows.
///
/// Nothing here is cached to disk. The text is licensed, not ours, so it lives
/// for as long as the sheet is open and no longer - the server sends it
/// `no-store` for the same reason.
final hsvRepositoryProvider = Provider((ref) {
  return HsvRepository(ref.watch(apiClientProvider));
});

/// One quotable verse, in both the Dutch and the English spelling of its book,
/// because the reader asks with whichever one the open translation uses.
class HsvRef {
  const HsvRef({
    required this.book,
    required this.bookNl,
    required this.chapter,
    required this.verse,
  });

  factory HsvRef.fromJson(Map<String, dynamic> json) => HsvRef(
    book: json['book']?.toString() ?? '',
    bookNl: json['bookNl']?.toString() ?? '',
    chapter: (json['chapter'] as num?)?.toInt() ?? 0,
    verse: (json['verse'] as num?)?.toInt() ?? 0,
  );

  final String book;
  final String bookNl;
  final int chapter;
  final int verse;
}

/// Which verses the product may quote. No text - a reference is a coordinate,
/// so this costs nothing against the allowance and may be held in memory.
class HsvIndex {
  HsvIndex({required this.attribution, required this.notice, required List<HsvRef> refs})
    : _keys = {
        for (final ref in refs) ...{
          _key(ref.book, ref.chapter, ref.verse),
          _key(ref.bookNl, ref.chapter, ref.verse),
        },
      };

  const HsvIndex.empty() : attribution = '', notice = '', _keys = const {};

  factory HsvIndex.fromJson(Map<String, dynamic> json) => HsvIndex(
    attribution: json['attribution']?.toString() ?? '',
    notice: json['notice']?.toString() ?? '',
    refs: (json['verses'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(HsvRef.fromJson)
        .toList(),
  );

  /// The source line that must be printed with the words, exactly as given.
  final String attribution;

  /// One line saying why there are only fifty.
  final String notice;

  final Set<String> _keys;

  static String _key(String book, int chapter, int verse) =>
      '${book.trim().toLowerCase()}|$chapter:$verse';

  /// Whether this verse is one of the fifty. Drives whether the reader is
  /// offered the HSV at all - an unlisted verse never shows the row.
  bool has(String book, int chapter, int verse) =>
      _keys.contains(_key(book, chapter, verse));

  bool get isEmpty => _keys.isEmpty;
}

class HsvRepository {
  HsvRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<HsvIndex> getIndex() async {
    final response = await _apiClient.dio.get('/bibles/hsv');
    return HsvIndex.fromJson(response.data as Map<String, dynamic>);
  }

  /// The quoted verses of one chapter, verse number to text. Usually one or
  /// two; never a chapter.
  Future<Map<int, String>> getChapter(String book, int chapter) async {
    final response = await _apiClient.dio.get(
      '/bibles/hsv/${Uri.encodeComponent(book)}/$chapter',
    );
    final data = response.data as Map<String, dynamic>;
    return {
      for (final row in (data['verses'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>())
        (row['verse'] as num).toInt(): row['text']?.toString() ?? '',
    };
  }
}
