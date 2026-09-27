import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/content_cache.dart';
import '../../auth/present/auth_controller.dart' show apiClientProvider;
import '../../bible/present/bible_providers.dart' show ChapterRef;
import '../../premium/present/pro_access_provider.dart';
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
///
/// A Pro reader asks for the full list (`full=1`); everyone else reads the
/// free slice off the CDN. Watching [hasProProvider] refetches the moment a
/// purchase lands, so the locked row gives way to the full list in place.
final crossRefChapterProvider = FutureProvider.autoDispose
    .family<CrossRefChapter, ChapterRef>((ref, chapterRef) {
      final full = ref.watch(hasProProvider);
      return ref
          .watch(crossRefRepositoryProvider)
          .getChapter(
            chapterRef.sourceId,
            chapterRef.book,
            chapterRef.chapter,
            full: full,
          );
    });

/// The same chapter, but only if it is already on this device.
///
/// What the long-press row's trailing count reads. Deliberately separate from
/// [crossRefChapterProvider]: opening the action sheet must not start a
/// request, so the count is shown when it is free and left out when it is not.
final cachedCrossRefChapterProvider = FutureProvider.autoDispose
    .family<CrossRefChapter?, ChapterRef>((ref, chapterRef) async {
      // Either tier's row will do: the count is `total`, which the free slice
      // and the full list carry alike. Not watching Pro status keeps a
      // long-press free of the profile and RevenueCat lookups.
      final repository = ref.watch(crossRefRepositoryProvider);
      try {
        return await repository.cachedChapter(
              chapterRef.sourceId,
              chapterRef.book,
              chapterRef.chapter,
            ) ??
            await repository.cachedChapter(
              chapterRef.sourceId,
              chapterRef.book,
              chapterRef.chapter,
              full: true,
            );
      } catch (_) {
        // No cache on this platform (web, tests). A missing count is not an
        // error state worth painting.
        return null;
      }
    });
