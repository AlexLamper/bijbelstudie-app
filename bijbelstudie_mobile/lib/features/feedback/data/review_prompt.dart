import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ---------------------------------------------------------------------------
/// The App Store rating prompt's gate.
///
/// Asking for a rating on the first launch is the fastest way to collect one
/// star: the reader has not read anything yet, so the only thing they can rate
/// is the interruption. Everything that decides *when* the ask is allowed lives
/// in [ReviewPromptThresholds] — one place, so the policy can be read and
/// changed without hunting through the widget that renders it.
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

  /// Reading sessions that lasted long enough to count as real use. See
  /// [engagementDwell].
  static const int minEngagements = 3;

  /// How long the reader has to stay inside a reading/study screen before that
  /// visit is counted as one engagement.
  static const Duration engagementDwell = Duration(seconds: 45);

  /// Nothing is asked until the app has been installed at least this long.
  static const Duration minAgeSinceFirstLaunch = Duration(days: 5);

  /// After an ask that did not end in a rating, stay quiet this long.
  static const Duration backoffAfterAsk = Duration(days: 60);

  /// Hard lifetime cap. iOS additionally rate-limits the native sheet to three
  /// presentations per 365 days per device, so an ask that gets past this gate
  /// can still legitimately show nothing.
  static const int maxLifetimeAsks = 3;

  /// How long a quiet, safe screen has to stay on screen before the prompt is
  /// allowed to appear over it.
  static const Duration settleDelay = Duration(seconds: 3);
}

/// Optional App Store id, for the `openStoreListing` fallback on iOS.
///
/// Pass `--dart-define=APP_STORE_ID=123456789` once the listing exists; while
/// it is empty the fallback is simply skipped rather than deep-linking to a
/// made-up product page.
const String kAppStoreId = String.fromEnvironment('APP_STORE_ID');

/// The persisted counters the gate reasons over. Pure data: [shouldAsk] is a
/// function of this object and a clock, which is what makes the policy
/// testable without a plugin or a widget tree.
class ReviewPromptState {
  const ReviewPromptState({
    this.launchCount = 0,
    this.launchDays = 0,
    this.engagements = 0,
    this.askCount = 0,
    this.rated = false,
    this.firstLaunchAt,
    this.lastAskedAt,
    this.lastLaunchDay,
  });

  final int launchCount;
  final int launchDays;
  final int engagements;
  final int askCount;

  /// True once a star was tapped. Terminal: the ask never returns.
  final bool rated;

  final DateTime? firstLaunchAt;
  final DateTime? lastAskedAt;

  /// Days since the epoch of the most recent launch, so a second launch on the
  /// same day does not count towards [launchDays].
  final int? lastLaunchDay;

  ReviewPromptState copyWith({
    int? launchCount,
    int? launchDays,
    int? engagements,
    int? askCount,
    bool? rated,
    DateTime? firstLaunchAt,
    DateTime? lastAskedAt,
    int? lastLaunchDay,
  }) {
    return ReviewPromptState(
      launchCount: launchCount ?? this.launchCount,
      launchDays: launchDays ?? this.launchDays,
      engagements: engagements ?? this.engagements,
      askCount: askCount ?? this.askCount,
      rated: rated ?? this.rated,
      firstLaunchAt: firstLaunchAt ?? this.firstLaunchAt,
      lastAskedAt: lastAskedAt ?? this.lastAskedAt,
      lastLaunchDay: lastLaunchDay ?? this.lastLaunchDay,
    );
  }

  /// Whether the prompt is allowed to appear at [now].
  ///
  /// This answers "has this reader earned an ask" only. Whether the *moment*
  /// is right — no tour, no onboarding, not mid-chapter — is the host widget's
  /// job, because that depends on the screen and not on any counter.
  bool shouldAsk({required DateTime now}) {
    if (rated) return false;
    if (askCount >= ReviewPromptThresholds.maxLifetimeAsks) return false;

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
const _kAskCount = 'review.askCount';
const _kRated = 'review.rated';
const _kFirstLaunchAt = 'review.firstLaunchAt';
const _kLastAskedAt = 'review.lastAskedAt';
const _kLastLaunchDay = 'review.lastLaunchDay';

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
        askCount: prefs.getInt(_kAskCount) ?? 0,
        rated: prefs.getBool(_kRated) ?? false,
        firstLaunchAt: _readDate(prefs, _kFirstLaunchAt),
        lastAskedAt: _readDate(prefs, _kLastAskedAt),
        lastLaunchDay: prefs.getInt(_kLastLaunchDay),
      );
    } catch (_) {
      // No preferences plugin (tests, an unusual platform). The defaults hold,
      // and the defaults never open the gate.
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
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

  /// Counts one completed reading session.
  Future<void> recordEngagement() async {
    await loaded;
    state = state.copyWith(engagements: state.engagements + 1);
    await _write((prefs) => prefs.setInt(_kEngagements, state.engagements));
  }

  /// The prompt was shown. Starts the back-off whether or not it is dismissed;
  /// a rating calls [markRated] on top of this.
  Future<void> markAsked({DateTime? now}) async {
    await loaded;
    final at = now ?? DateTime.now();
    state = state.copyWith(askCount: state.askCount + 1, lastAskedAt: at);
    await _write((prefs) async {
      await prefs.setInt(_kAskCount, state.askCount);
      await prefs.setInt(_kLastAskedAt, at.millisecondsSinceEpoch);
    });
  }

  /// A star was tapped. Terminal — nothing asks again on this device.
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
