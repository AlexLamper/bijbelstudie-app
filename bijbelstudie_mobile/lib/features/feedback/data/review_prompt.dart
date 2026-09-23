import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ---------------------------------------------------------------------------
/// The store rating prompt's gate.
///
/// Asking for a rating on the first launch is the fastest way to collect one
/// star: the reader has not read anything yet, so the only thing they can rate
/// is the interruption. Everything that decides *when* the ask is allowed lives
/// in [ReviewPromptThresholds] — one place, so the policy can be read and
/// changed without hunting through the widget that renders it.
///
/// What this file decides is only *when the app may call the native API*.
/// Choosing the moment is explicitly allowed by both stores; asking the reader
/// whether they like the app first, with our own card and our own stars, is
/// not (App Store Review Guideline 5.6.1 disallows custom review prompts, and
/// Play's in-app review guidelines name "Do you like the app?" as a forbidden
/// pre-prompt). So there is no UI anywhere in this feature beyond the native
/// sheet the OS draws itself.
/// ---------------------------------------------------------------------------

/// Every threshold the rating prompt is gated on. Nothing else in the app may
/// hard-code one of these numbers.
class ReviewPromptThresholds {
  const ReviewPromptThresholds._();

  /// Distinct app launches (a cold start, or a return from the background
  /// after the app was actually suspended) — not rebuilds.
  static const int minLaunches = 3;

  /// …and those launches must fall on at least this many different calendar
  /// days. Three launches inside one evening is one session, not a habit.
  static const int minLaunchDays = 3;

  /// Moments that counted as real use — a long read, a finished lesson, a
  /// passed quiz, a streak milestone. See [ReviewSignal].
  static const int minEngagements = 3;

  /// How long the reader has to stay inside a reading/study screen before that
  /// visit is counted as one engagement.
  static const Duration engagementDwell = Duration(seconds: 45);

  /// From this share of the quiz answered correctly, the quiz counts as
  /// passed. Below it the reader is being sent back to re-read the chapter,
  /// which is not a success moment.
  static const double quizPassRatio = 0.6;

  /// Nothing is asked until the app has been installed at least this long.
  static const Duration minAgeSinceFirstLaunch = Duration(days: 5);

  /// After an ask that did not end in a rating, stay quiet this long.
  static const Duration backoffAfterAsk = Duration(days: 60);

  /// At most this many asks inside [askWindow] — a *rolling* window, not a
  /// lifetime cap.
  ///
  /// This mirrors the platform: `SKStoreReviewController` allows up to three
  /// prompts per 365 days per device, and Play throttles on a comparable
  /// window of its own. Counting for a lifetime instead threw two of the three
  /// away — a reader who ignored the sheet twice in their first year could
  /// never be asked again, ever, while the OS would happily have shown it.
  static const int maxAsksPerWindow = 3;

  /// The rolling window [maxAsksPerWindow] is counted over.
  static const Duration askWindow = Duration(days: 365);

  /// How long a quiet, safe screen has to stay on screen before the app is
  /// allowed to call the review API over it.
  static const Duration settleDelay = Duration(seconds: 3);
}

/// What earned an engagement. Any of these satisfies one unit of
/// [ReviewPromptThresholds.minEngagements]; none of them shows anything at the
/// moment it happens.
enum ReviewSignal {
  /// Stayed inside a reading/study screen for
  /// [ReviewPromptThresholds.engagementDwell].
  dwell,

  /// Finished a study lesson.
  lessonCompleted,

  /// Scored at least [ReviewPromptThresholds.quizPassRatio] on a lesson quiz.
  quizPassed,

  /// Reached a streak milestone (3, 7, 14, 30, 50, 100 days).
  streakMilestone,
}

/// The App Store id of "BijbelStudie — Lees & Leer".
///
/// Overridable with `--dart-define=APP_STORE_ID=…` so a second listing (or a
/// test build) does not need a code change, but it defaults to the real id:
/// without one, the explicit "Beoordeel de app" row on iOS has nowhere to go.
const String kAppStoreId = String.fromEnvironment(
  'APP_STORE_ID',
  defaultValue: '6800668187',
);

/// The App Store page with the review composer already open. Used only by the
/// explicit, user-initiated "Beoordeel de app" action — never automatically.
String get appStoreWriteReviewUrl =>
    'https://apps.apple.com/app/id$kAppStoreId?action=write-review';

/// The persisted counters the gate reasons over. Pure data: [shouldAsk] is a
/// function of this object and a clock, which is what makes the policy
/// testable without a plugin or a widget tree.
class ReviewPromptState {
  const ReviewPromptState({
    this.launchCount = 0,
    this.launchDays = 0,
    this.engagements = 0,
    this.asks = const <DateTime>[],
    this.rated = false,
    this.firstLaunchAt,
    this.lastLaunchDay,
    this.lastSignal,
  });

  final int launchCount;
  final int launchDays;
  final int engagements;

  /// What earned the most recent engagement, this session only — it is never
  /// written to disk and the gate never reads it. It exists so a call site can
  /// be traced back from the state, and so the tests can tell the signals
  /// apart.
  final ReviewSignal? lastSignal;

  /// When the app called the review API, oldest first, pruned to
  /// [ReviewPromptThresholds.askWindow] whenever it is written.
  ///
  /// A list rather than a counter because the cap is a rolling window: the
  /// question is not "how many times ever" but "how many times since this day
  /// last year".
  final List<DateTime> asks;

  /// True once the reader took the explicit "Beoordeel de app" route to the
  /// store listing. Terminal: the automatic ask never returns.
  ///
  /// Note this is *not* set by an ask. The OS may show nothing at all —
  /// `requestReview` is rate-limited by the system, the reader can switch
  /// in-app ratings off in Settings, and a call that returns normally is no
  /// evidence the sheet appeared, let alone that a review was written. Nothing
  /// in this app may read "asked" as "rated".
  final bool rated;

  final DateTime? firstLaunchAt;

  /// Days since the epoch of the most recent launch, so a second launch on the
  /// same day does not count towards [launchDays].
  final int? lastLaunchDay;

  /// The most recent ask, for the back-off.
  DateTime? get lastAskedAt => asks.isEmpty ? null : asks.last;

  /// How many asks fall inside the rolling window ending at [now].
  int asksInWindow(DateTime now) =>
      asks.where((at) => now.difference(at) < ReviewPromptThresholds.askWindow)
          .length;

  ReviewPromptState copyWith({
    int? launchCount,
    int? launchDays,
    int? engagements,
    List<DateTime>? asks,
    bool? rated,
    DateTime? firstLaunchAt,
    int? lastLaunchDay,
    ReviewSignal? lastSignal,
  }) {
    return ReviewPromptState(
      launchCount: launchCount ?? this.launchCount,
      launchDays: launchDays ?? this.launchDays,
      engagements: engagements ?? this.engagements,
      asks: asks ?? this.asks,
      rated: rated ?? this.rated,
      firstLaunchAt: firstLaunchAt ?? this.firstLaunchAt,
      lastLaunchDay: lastLaunchDay ?? this.lastLaunchDay,
      lastSignal: lastSignal ?? this.lastSignal,
    );
  }

  /// Whether the app is allowed to call the review API at [now].
  ///
  /// This answers "has this reader earned an ask" only. Whether the *moment*
  /// is right — no tour, no onboarding, not mid-chapter — is the host widget's
  /// job, because that depends on the screen and not on any counter. And
  /// whether anything is then actually drawn is the OS's decision, not ours.
  bool shouldAsk({required DateTime now}) {
    if (rated) return false;
    if (asksInWindow(now) >= ReviewPromptThresholds.maxAsksPerWindow) {
      return false;
    }

    final asked = lastAskedAt;
    if (asked != null &&
        now.difference(asked) < ReviewPromptThresholds.backoffAfterAsk) {
      return false;
    }

    final first = firstLaunchAt;
    if (first == null ||
        now.difference(first) < ReviewPromptThresholds.minAgeSinceFirstLaunch) {
      return false;
    }

    if (launchCount < ReviewPromptThresholds.minLaunches) return false;
    if (launchDays < ReviewPromptThresholds.minLaunchDays) return false;
    if (engagements < ReviewPromptThresholds.minEngagements) return false;

    return true;
  }
}

const _kLaunchCount = 'review.launchCount';
const _kLaunchDays = 'review.launchDays';
const _kEngagements = 'review.engagements';
const _kAsks = 'review.asks';
const _kRated = 'review.rated';
const _kFirstLaunchAt = 'review.firstLaunchAt';
const _kLastLaunchDay = 'review.lastLaunchDay';

/// Superseded by [_kAsks]; read once, on the next launch after the update, so
/// a device that was already asked does not get its history wiped.
const _kLegacyAskCount = 'review.askCount';
const _kLegacyLastAskedAt = 'review.lastAskedAt';

final reviewPromptProvider =
    NotifierProvider<ReviewPromptController, ReviewPromptState>(
      ReviewPromptController.new,
    );

/// Reads and writes the counters, following the same shape as
/// `ReadingSettingsController`: defaults first, disk a moment later, and a
/// completer so a caller that must not act on the defaults can wait.
class ReviewPromptController extends Notifier<ReviewPromptState> {
  final Completer<void> _loaded = Completer<void>();

  /// Completes once the first read from disk is done, successfully or not.
  Future<void> get loaded => _loaded.future;

  @override
  ReviewPromptState build() {
    _load();
    return const ReviewPromptState();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = ReviewPromptState(
        launchCount: prefs.getInt(_kLaunchCount) ?? 0,
        launchDays: prefs.getInt(_kLaunchDays) ?? 0,
        engagements: prefs.getInt(_kEngagements) ?? 0,
        asks: _readAsks(prefs),
        rated: prefs.getBool(_kRated) ?? false,
        firstLaunchAt: _readDate(prefs, _kFirstLaunchAt),
        lastLaunchDay: prefs.getInt(_kLastLaunchDay),
      );
    } catch (_) {
      // No preferences plugin (tests, an unusual platform). The defaults hold,
      // and the defaults never open the gate.
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  /// The ask history, or — on the first run after the lifetime counter was
  /// replaced — one reconstructed from it.
  ///
  /// The old format kept a count and a single timestamp, so the only honest
  /// reconstruction is "all of them happened at the last known ask". That errs
  /// towards asking less, which is the right way to be wrong here, and it
  /// ages out of the window by itself within a year.
  static List<DateTime> _readAsks(SharedPreferences prefs) {
    final stored = prefs.getStringList(_kAsks);
    if (stored != null) {
      return stored
          .map(int.tryParse)
          .whereType<int>()
          .map(DateTime.fromMillisecondsSinceEpoch)
          .toList()
        ..sort();
    }

    final legacyCount = prefs.getInt(_kLegacyAskCount) ?? 0;
    final legacyAt = _readDate(prefs, _kLegacyLastAskedAt);
    if (legacyCount <= 0 || legacyAt == null) return const <DateTime>[];
    return List<DateTime>.filled(legacyCount, legacyAt);
  }

  static DateTime? _readDate(SharedPreferences prefs, String key) {
    final millis = prefs.getInt(key);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Counts one launch. Call this once per process, not once per rebuild.
  Future<void> recordLaunch({DateTime? now}) async {
    await loaded;
    final at = now ?? DateTime.now();
    final today = _dayNumber(at);
    final isNewDay = state.lastLaunchDay != today;

    state = state.copyWith(
      launchCount: state.launchCount + 1,
      launchDays: isNewDay ? state.launchDays + 1 : state.launchDays,
      lastLaunchDay: today,
      firstLaunchAt: state.firstLaunchAt ?? at,
    );
    await _write((prefs) async {
      await prefs.setInt(_kLaunchCount, state.launchCount);
      await prefs.setInt(_kLaunchDays, state.launchDays);
      await prefs.setInt(_kLastLaunchDay, today);
      await prefs.setInt(
        _kFirstLaunchAt,
        state.firstLaunchAt!.millisecondsSinceEpoch,
      );
    });
  }

  /// Counts one moment that showed the app working: a long read, a finished
  /// lesson, a passed quiz, a streak milestone.
  ///
  /// Deliberately silent. The signal is recorded where it happens and the
  /// native sheet is left to the host, which fires it later on a calm screen —
  /// interrupting the celebration the reader just earned is exactly the
  /// timing both stores warn against.
  Future<void> recordSuccess(ReviewSignal signal) async {
    await loaded;
    state = state.copyWith(
      engagements: state.engagements + 1,
      lastSignal: signal,
    );
    await _write((prefs) => prefs.setInt(_kEngagements, state.engagements));
  }

  /// Counts one completed reading session.
  Future<void> recordEngagement() => recordSuccess(ReviewSignal.dwell);

  /// The review API was called. Starts the back-off and consumes one slot in
  /// the rolling window — whether or not the OS drew anything, because we have
  /// no way to find out and guessing would burn the reader's patience.
  Future<void> markAsked({DateTime? now}) async {
    await loaded;
    final at = now ?? DateTime.now();
    final asks = [
      ...state.asks.where(
        (earlier) => at.difference(earlier) < ReviewPromptThresholds.askWindow,
      ),
      at,
    ]..sort();

    state = state.copyWith(asks: asks);
    await _write(
      (prefs) => prefs.setStringList(_kAsks, [
        for (final ask in asks) '${ask.millisecondsSinceEpoch}',
      ]),
    );
  }

  /// The reader went to the store listing themselves. Terminal — the automatic
  /// ask never returns on this device.
  Future<void> markRated() async {
    await loaded;
    state = state.copyWith(rated: true);
    await _write((prefs) => prefs.setBool(_kRated, true));
  }

  Future<void> _write(Future<void> Function(SharedPreferences) body) async {
    try {
      await body(await SharedPreferences.getInstance());
    } catch (_) {
      // In-memory state still reflects the change for this session; the worst
      // case is that the counter restarts next launch, which errs towards not
      // asking.
    }
  }

  static int _dayNumber(DateTime at) =>
      DateTime(at.year, at.month, at.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}
