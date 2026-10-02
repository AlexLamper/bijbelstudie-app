import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/payload_cache.dart';
import '../../../core/data/provider_cache.dart';
import '../../../core/notifications/notification_scheduler.dart';
import '../../bible/present/bible_providers.dart';
import '../../dashboard/data/dashboard_models.dart';
import '../../dashboard/present/dashboard_providers.dart';
import '../data/bible_year_models.dart';
import '../data/bible_year_repository.dart';
import '../data/plan_read_store.dart';
import '../domain/bible_year_display.dart';
import '../domain/plan_calendar.dart';
import '../domain/plan_read_set.dart';

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
    final enrollment = current?.enrollment;
    final keys = {for (final r in refs) bibleYearRefKey(r.code, r.chapter)};
    // The enrollment the server answers with carries no `readRefs`, so this
    // is where a mark is remembered: without it the tick is gone from the
    // state the moment the mutation response lands.
    unawaited(ref.read(planReadStoreProvider.notifier).mark(keys, read));
    if (current != null && today != null) {
      state = AsyncData(
        current.copyWith(
          today: applyRefMark(today, refs, read),
          enrollment: enrollment?.copyWith(
            readRefs: read
                ? {...enrollment.readRefs, ...keys}
                : enrollment.readRefs.difference(keys),
          ),
        ),
      );
    }
    return _apply(() => _repository.markRefs(refs, read), reloadOnFailure: true);
  }

  /// The reader scrolled [code] [chapter] to its end: ticks it in the running
  /// plan, once. A no-op without a plan or when it is already read, so the
  /// reader can call it for every chapter it finishes.
  Future<String?> chapterReadToEnd(String code, int chapter) async {
    final current = state.value;
    final enrollment = current?.enrollment;
    if (enrollment == null || !enrollment.isActive || code.isEmpty) return null;
    final key = bibleYearRefKey(code, chapter);
    // `enrollment.readRefs` is empty on every server answer (the DTO has no
    // such field), so the guard asks the device's own marks and today's
    // portions too - else every scroll to the end would POST again.
    if (enrollment.readRefs.contains(key)) return null;
    if (ref.read(planReadStoreProvider).read.contains(key)) return null;
    final today = current?.today;
    if (today != null) {
      for (final portion in today.portions) {
        for (final r in portion.refs) {
          if (r.read && r.refKey == key) return null;
        }
      }
    }
    return markRefs([BibleYearChapterKey(code, chapter)], true);
  }

  /// A 'studeren' part of [day]: the uitleg read, or the vraag opened.
  Future<String?> markStudy(int day, BibleYearStudyPart part, {bool done = true}) {
    final current = state.value;
    final enrollment = current?.enrollment;
    if (current != null && enrollment != null) {
      final key = bibleYearStudyKey(day, part);
      if (done && enrollment.studyDone.contains(key)) return Future.value();
      final today = current.today;
      var study = today?.study;
      if (today != null && study != null && today.dayNumber == day) {
        study = part == BibleYearStudyPart.uitleg
            ? study.copyWith(uitlegDone: done)
            : study.copyWith(vraagDone: done);
      }
      final nextToday = today == null || study == null
          ? today
          : today.copyWith(
              study: study,
              todayDone: today.portions.every((p) => p.done) && study.done && today.dayNumber > 0,
            );
      state = AsyncData(
        current.copyWith(
          today: nextToday,
          enrollment: enrollment.copyWith(
            studyDone: done
                ? {...enrollment.studyDone, key}
                : enrollment.studyDone.difference({key}),
          ),
        ),
      );
    }
    return _apply(() => _repository.markStudy(day, part, done), reloadOnFailure: true);
  }

  /// Changes the running plan's settings (the gear); read chapters stay.
  Future<String?> updateSettings(BibleYearStartBody body) async {
    final error = await _apply(() => _repository.update(body));
    if (error == null && ref.mounted) _notifyReminders();
    return error;
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
      _clearDeviceUnticks();
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
    if (error == null && ref.mounted) {
      _clearDeviceUnticks();
      _notifyReminders();
    }
    return error;
  }

  /// A new run starts clean: an untick made in the run before it must not keep
  /// a chapter grey in the new one.
  void _clearDeviceUnticks() {
    try {
      unawaited(ref.read(planReadStoreProvider.notifier).clearUnread());
    } catch (_) {}
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

/// The running plan as a [PlanCalendar]: the state's enrollment (read
/// chapters, study parts) over the static schedule. Data(null) without a
/// running plan. Recomputed on every tick without refetching the schedule.
final planCalendarProvider = Provider.autoDispose<AsyncValue<PlanCalendar?>>((ref) {
  final async = ref.watch(bibleYearProvider);
  final value = async.value;
  if (value == null) {
    final error = async.error;
    return error != null ? AsyncError(error, async.stackTrace ?? StackTrace.current) : const AsyncLoading();
  }
  final enrollment = value.enrollment;
  final today = value.today;
  if (enrollment == null || !enrollment.isActive || today == null) return const AsyncData(null);
  final schedule = ref.watch(
    bibleYearScheduleProvider((
      plan: enrollment.planKey,
      track: enrollment.track,
      version: enrollment.scheduleVersion,
    )),
  );
  final readRefs = ref.watch(planReadRefsProvider);
  return schedule.whenData(
    (s) => PlanCalendar(
      enrollment: enrollment,
      schedule: s,
      todayDay: today.dayNumber,
      readRefs: readRefs,
    ),
  );
});

/// The reader's 66-book read map (`/dashboard`'s `readChapters`), which is
/// what `POST /last-read` fills - how chapters read in the normal reader, on
/// the website or before the plan began count towards the plan.
///
/// Followed off the Start tab when that tab holds it, so a chapter ticked
/// there recolours the plan at once, but never built for this: colouring the
/// plan must not cost a `/dashboard` request. Without the tab it comes off
/// the payload that tab cached, which is the same map one fetch older - good
/// enough for history, while today's ticks come from [planReadStoreProvider].
final planReadChaptersProvider =
    FutureProvider.autoDispose<Map<String, List<int>>>((ref) async {
      ref.cacheFor(const Duration(minutes: 10));
      if (ref.exists(dashboardProvider)) {
        final live = ref.watch(dashboardProvider).value?.readChapters;
        if (live != null) return live;
      }
      final raw = await PayloadCache.read(DashboardNotifier.cacheKey);
      if (raw == null) return const {};
      try {
        return DashboardData.fromJson(raw).readChapters;
      } catch (_) {
        return const {};
      }
    });

/// Every chapter read, as `readRefs` keys - the one set every plan surface
/// decides "gelezen" on. See `planReadRefKeys` for why it has to be merged
/// rather than read off the enrollment.
final planReadRefsProvider = Provider.autoDispose<Set<String>>((ref) {
  final state = ref.watch(bibleYearProvider).value;
  final marks = ref.watch(planReadStoreProvider);
  final readChapters = ref.watch(planReadChaptersProvider).value ?? const {};
  return planReadRefKeys(
    enrollmentRefs: state?.enrollment?.readRefs ?? const {},
    today: state?.today,
    readChapters: readChapters,
    deviceRead: marks.read,
    deviceUnread: marks.unread,
  );
});

typedef BibleYearDayPreviewKey = ({BibleYearPlanKey plan, BibleYearTrackKey track, int day});

/// One day of a not yet chosen plan (the setup's "Dag 1" example). Null when
/// it cannot be fetched; the caller shows static text then.
final bibleYearDayPreviewProvider = FutureProvider.autoDispose
    .family<BibleYearScheduleDay?, BibleYearDayPreviewKey>((ref, key) async {
      ref.cacheFor(const Duration(minutes: 30));
      try {
        return await ref
            .watch(bibleYearRepositoryProvider)
            .scheduleDay(key.plan, key.track, key.day);
      } on BibleYearException {
        return null;
      }
    });
