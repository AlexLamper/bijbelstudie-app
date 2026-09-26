import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/payload_cache.dart';
import '../../../core/data/provider_cache.dart';
import '../../../core/notifications/notification_scheduler.dart';
import '../../bible/present/bible_providers.dart';
import '../../dashboard/data/resume_link.dart';
import '../../study/present/study_pane_controller.dart';
import '../data/bible_year_models.dart';
import '../data/bible_year_repository.dart';
import '../domain/bible_year_display.dart';

/// The state behind every "Bijbel in een jaar" surface in the app - the plan
/// screen, the Studies block and the Start tab's card - so ticking a chapter
/// on one shows on the others. Mirrors the website's `useBibleYear` hook: one
/// GET, then each mutation replaces `enrollment` and `today` with the server's
/// answer, and a chapter tick is optimistic.
///
/// Opens on the last good payload ([PayloadCache]) so the card renders
/// offline; a failed fetch with a cached copy keeps the cached copy.
class BibleYearController extends AsyncNotifier<BibleYearState> {
  static const cacheKey = 'bibleYear';

  /// Set when the reader is sent to a chapter from a plan surface: reading it
  /// there auto-ticks it server-side (`/last-read`), so the next plan surface
  /// to mount fetches again.
  bool _dirty = false;

  /// Which chapter the reader showed when the state was fetched. A different
  /// one on the next mount means the reader moved, and may have read a plan
  /// chapter the state does not know about yet.
  String? _readerKeyAtFetch;

  @override
  Future<BibleYearState> build() async {
    ref.cacheFor();
    final repository = ref.watch(bibleYearRepositoryProvider);

    BibleYearState? cached;
    final raw = await PayloadCache.read(cacheKey);
    if (raw != null) {
      try {
        cached = BibleYearState.fromJson(raw);
        if (state is AsyncLoading) state = AsyncData(cached);
      } catch (_) {
        // A payload from an older build. Wait for the network.
      }
    }

    try {
      final fresh = await repository.fetchState();
      _remember(fresh);
      return fresh;
    } on BibleYearException catch (e) {
      // Signed out: never show the previous reader's plan.
      if (e.isUnauthorized || cached == null) rethrow;
      return cached;
    }
  }

  BibleYearRepository get _repository => ref.read(bibleYearRepositoryProvider);

  void _remember(BibleYearState next) {
    _dirty = false;
    _readerKeyAtFetch = _readerKey();
    unawaited(PayloadCache.write(cacheKey, next.toJson()));
  }

  String? _readerKey() {
    if (!ref.exists(readerLocationProvider)) return null;
    final location = ref.read(readerLocationProvider);
    return '${location.book}/${location.chapter}';
  }

  /// The next [refreshIfStale] fetches.
  void markDirty() => _dirty = true;

  /// Called when a plan surface mounts: fetch again when the reader was sent
  /// away to read, the reader moved on, or the day rolled over.
  ///
  /// Only while a plan is active: without one, a moved reader or a new day
  /// changes nothing the state shows, and most readers have no plan - so
  /// every Start-tab mount and reader move would be a wasted request. A plan
  /// started here replaces the state itself ([start]); one started on
  /// another device shows once the provider is rebuilt, or at once when the
  /// caller knows from `/dashboard` that one runs ([planActive]).
  Future<void> refreshIfStale({bool planActive = false}) async {
    final current = state;
    if (current.isLoading || !current.hasValue) return;
    final active = current.value?.isActive == true;
    if (!_dirty && !active && !planActive) return;
    final today = current.value?.today;
    final dayRolled = today != null && today.localDate.isNotEmpty && today.localDate != deviceToday();
    if (_dirty || !active || dayRolled || _readerKey() != _readerKeyAtFetch) {
      await refresh();
    }
  }

  /// Fetches again and keeps what is shown when that fails (offline).
  Future<void> refresh() async {
    try {
      final fresh = await _repository.fetchState();
      if (!ref.mounted) return;
      _remember(fresh);
      state = AsyncData(fresh);
    } on BibleYearException catch (e, st) {
      if (ref.mounted && e.isUnauthorized) state = AsyncError(e, st);
    }
  }

  /// Runs a mutation and folds its `{ enrollment, today }` into the state.
  /// Returns null on success, else the Dutch message to show.
  Future<String?> _apply(
    Future<Map<String, dynamic>> Function() run, {
    bool reloadOnFailure = false,
  }) async {
    try {
      final json = await run();
      if (!ref.mounted) return null;
      final next = (state.value ?? const BibleYearState()).withMutation(json);
      _remember(next);
      state = AsyncData(next);
      return null;
    } on BibleYearException catch (e, st) {
      if (!ref.mounted) return e.message;
      if (e.isUnauthorized) {
        state = AsyncError(e, st);
      } else if (reloadOnFailure) {
        // An optimistic tick that did not land: take the server's word again.
        unawaited(refresh());
      }
      return e.message;
    }
  }

  Future<String?> markRefs(List<BibleYearChapterKey> refs, bool read) {
    final current = state.value;
    final today = current?.today;
    if (current != null && today != null) {
      state = AsyncData(current.copyWith(today: applyRefMark(today, refs, read)));
    }
    return _apply(() => _repository.markRefs(refs, read), reloadOnFailure: true);
  }

  Future<String?> markDay(int day, bool read) => _apply(() => _repository.markDay(day, read));

  Future<String?> shift() => _apply(_repository.shift);

  Future<String?> stop() async {
    final error = await _apply(_repository.stop);
    if (error == null && ref.mounted) _notifyReminders();
    return error;
  }

  /// POST; on 409 (started on another device) the state is reloaded so the
  /// running plan shows, and that counts as success.
  Future<String?> start(BibleYearStartBody body) async {
    try {
      final json = await _repository.start(body);
      if (!ref.mounted) return null;
      final next = (state.value ?? const BibleYearState()).withMutation(json);
      _remember(next);
      state = AsyncData(next);
      _notifyReminders();
      return null;
    } on BibleYearException catch (e, st) {
      if (!ref.mounted) return e.message;
      if (e.isConflict) {
        await refresh();
        return null;
      }
      if (e.isUnauthorized) state = AsyncError(e, st);
      return e.message;
    }
  }

  /// POST, falling back to PATCH restart - only for an explicit "Opnieuw
  /// beginnen", which abandons (never deletes) the plan before it.
  Future<String?> restart(BibleYearStartBody body) async {
    final error = await _apply(() async {
      try {
        return await _repository.start(body);
      } on BibleYearException catch (e) {
        if (!e.isConflict) rethrow;
        return _repository.restart(body);
      }
    });
    if (error == null && ref.mounted) _notifyReminders();
    return error;
  }

  /// The notification ladder reads the plan (`/notifications/schedule`), so a
  /// plan that starts or stops re-derives it.
  void _notifyReminders() {
    try {
      ref.read(notificationReschedulerProvider).requestReschedule();
    } catch (_) {}
  }
}

final bibleYearProvider = AsyncNotifierProvider.autoDispose<BibleYearController, BibleYearState>(
  BibleYearController.new,
  retry: bibleYearRetry,
);

/// Riverpod retries a failed build by default, ten times. Signed out is an
/// answer, not a glitch, so it is never retried; anything else twice, gently -
/// the server's CPU budget is a standing constraint.
Duration? bibleYearRetry(int retryCount, Object error) {
  if (error is BibleYearException && error.isUnauthorized) return null;
  if (retryCount >= 2) return null;
  return Duration(seconds: 2 << retryCount);
}

typedef BibleYearScheduleKey = ({BibleYearPlanKey plan, BibleYearTrackKey track, int version});

/// The static schedule of a running plan, for the backlog links and "Komende
/// dagen". Keyed on the plan's own version so a later schedule tweak never
/// shows the wrong days.
final bibleYearScheduleProvider = FutureProvider.autoDispose
    .family<BibleYearSchedule, BibleYearScheduleKey>((ref, key) async {
      ref.cacheFor(const Duration(minutes: 30));
      return ref
          .watch(bibleYearRepositoryProvider)
          .schedule(key.plan, key.track, version: key.version);
    });

/// Opens [chapter] in the reader the way every other "lees hoofdstuk" link in
/// the app does (reader location, reader half of the split screen, Bijbel
/// tab), and marks the plan stale so the chapter shows as read on return.
void openBibleYearChapter(BuildContext context, WidgetRef ref, BibleYearRef chapter) {
  ref.read(bibleYearProvider.notifier).markDirty();
  ref
      .read(readerLocationProvider.notifier)
      .openChapter(book: resolveBookName(chapter.book) ?? chapter.book, chapter: chapter.chapter);
  ref.read(studyPaneProvider.notifier).showReader();
  context.go('/study');
}

/// Refetches the plan (when stale) each time the widget mounts - which is how
/// a reader coming back from the Bijbel tab finds today's chapters ticked.
mixin BibleYearRefreshOnMount<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// False skips the refresh (and so never builds the provider): the Start
  /// tab's card when the dashboard already said there is no plan.
  bool get bibleYearRefreshOnMount => true;

  /// True when the caller knows a plan runs (the dashboard said so), so a
  /// state that shows none is refetched.
  bool get bibleYearKnownActive => false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !bibleYearRefreshOnMount) return;
      unawaited(ref
          .read(bibleYearProvider.notifier)
          .refreshIfStale(planActive: bibleYearKnownActive));
    });
  }
}
