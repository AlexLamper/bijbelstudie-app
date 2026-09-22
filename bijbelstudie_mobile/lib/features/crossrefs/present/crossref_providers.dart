import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/content_cache.dart';
import '../../auth/present/auth_controller.dart' show apiClientProvider;
import '../../bible/present/bible_providers.dart' show ChapterRef;
import '../data/crossref_repository.dart';
import '../domain/crossref_models.dart';

final crossRefRepositoryProvider = Provider((ref) {
  return CrossRefRepository(
    ref.watch(apiClientProvider),
    ref.watch(contentCacheProvider),
  );
});

/// Every cross-reference of one chapter, keyed by the chapter the reader is
/// in.
///
/// The unit is the chapter, not the verse, because that is the unit the route
/// serves, the unit the ETag covers and the unit the cache row holds. A sheet
/// opened on verse 3 and one opened on verse 4 of the same chapter therefore
/// share a single request — and the long-press row can show a count without
/// costing a second one.
final crossRefChapterProvider = FutureProvider.autoDispose
    .family<CrossRefChapter, ChapterRef>((ref, chapterRef) {
      return ref
          .watch(crossRefRepositoryProvider)
          .getChapter(chapterRef.sourceId, chapterRef.book, chapterRef.chapter);
    });

/// The same chapter, but only if it is already on this device.
///
/// What the long-press row's trailing count reads. Deliberately separate from
/// [crossRefChapterProvider]: opening the action sheet must not start a
/// request, so the count is shown when it is free and left out when it is not.
final cachedCrossRefChapterProvider = FutureProvider.autoDispose
    .family<CrossRefChapter?, ChapterRef>((ref, chapterRef) async {
      try {
        return await ref
            .watch(crossRefRepositoryProvider)
            .cachedChapter(
              chapterRef.sourceId,
              chapterRef.book,
              chapterRef.chapter,
            );
      } catch (_) {
        // No cache on this platform (web, tests). A missing count is not an
        // error state worth painting.
        return null;
      }
    });
