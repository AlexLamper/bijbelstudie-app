import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bijbelstudie_mobile/features/feedback/data/review_prompt.dart';

/// The rating prompt's gate. Everything here is pure: a counter snapshot plus
/// a clock, no plugin and no widget tree — which is the point of keeping the
/// policy out of the host widget.
void main() {
  final now = DateTime(2026, 9, 1, 20, 0);

  /// A reader who has cleared every threshold with nothing standing in the way.
  ReviewPromptState earned({
    int launchCount = ReviewPromptThresholds.minLaunches,
    int launchDays = ReviewPromptThresholds.minLaunchDays,
    int engagements = ReviewPromptThresholds.minEngagements,
    int askCount = 0,
    bool rated = false,
    Duration? age,
    DateTime? lastAskedAt,
  }) {
    return ReviewPromptState(
      launchCount: launchCount,
      launchDays: launchDays,
      engagements: engagements,
      askCount: askCount,
      rated: rated,
      firstLaunchAt: now.subtract(
        age ?? ReviewPromptThresholds.minAgeSinceFirstLaunch,
      ),
      lastAskedAt: lastAskedAt,
    );
  }

  group('closed below the thresholds', () {
    test('a fresh install never asks', () {
      expect(const ReviewPromptState().shouldAsk(now: now), isFalse);
    });

    test('too few launches', () {
      expect(
        earned(launchCount: ReviewPromptThresholds.minLaunches - 1)
            .shouldAsk(now: now),
        isFalse,
      );
    });

    test('enough launches but all on too few days', () {
      expect(
        earned(
          launchCount: 12,
          launchDays: ReviewPromptThresholds.minLaunchDays - 1,
        ).shouldAsk(now: now),
        isFalse,
      );
    });

    test('launches without real reading', () {
      expect(
        earned(engagements: ReviewPromptThresholds.minEngagements - 1)
            .shouldAsk(now: now),
        isFalse,
      );
    });

    test('installed too recently', () {
      expect(
        earned(
          age: ReviewPromptThresholds.minAgeSinceFirstLaunch -
              const Duration(hours: 1),
        ).shouldAsk(now: now),
        isFalse,
      );
    });
  });

  group('open above the thresholds', () {
    test('every threshold met', () {
      expect(earned().shouldAsk(now: now), isTrue);
    });

    test('comfortably past every threshold', () {
      expect(
        earned(
          launchCount: 40,
          launchDays: 20,
          engagements: 30,
          age: const Duration(days: 90),
        ).shouldAsk(now: now),
        isTrue,
      );
    });
  });

  group('back-off and caps', () {
    test('a dismissed ask goes quiet for weeks', () {
      final justAsked = earned(
        askCount: 1,
        lastAskedAt: now.subtract(
          ReviewPromptThresholds.backoffAfterAsk - const Duration(days: 1),
        ),
      );
      expect(justAsked.shouldAsk(now: now), isFalse);
      expect(ReviewPromptThresholds.backoffAfterAsk.inDays, greaterThan(14));
    });

    test('…and comes back once the back-off has run out', () {
      expect(
        earned(
          askCount: 1,
          age: const Duration(days: 365),
          lastAskedAt: now.subtract(
            ReviewPromptThresholds.backoffAfterAsk + const Duration(days: 1),
          ),
        ).shouldAsk(now: now),
        isTrue,
      );
    });

    test('the lifetime cap is final', () {
      expect(
        earned(
          askCount: ReviewPromptThresholds.maxLifetimeAsks,
          age: const Duration(days: 3650),
          lastAskedAt: now.subtract(const Duration(days: 3000)),
        ).shouldAsk(now: now),
        isFalse,
      );
    });

    test('a reader who rated is never asked again', () {
      expect(earned(rated: true).shouldAsk(now: now), isFalse);
    });
  });

  group('launch counting', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('two launches on one day count as one day', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(reviewPromptProvider.notifier);
      await notifier.loaded;
      await notifier.recordLaunch(now: DateTime(2026, 9, 1, 9));
      await notifier.recordLaunch(now: DateTime(2026, 9, 1, 21));
      await notifier.recordLaunch(now: DateTime(2026, 9, 2, 8));

      final state = container.read(reviewPromptProvider);
      expect(state.launchCount, 3);
      expect(state.launchDays, 2);
      expect(state.firstLaunchAt, DateTime(2026, 9, 1, 9));
      // Three launches, but only two days and no reading yet.
      expect(state.shouldAsk(now: DateTime(2026, 9, 30)), isFalse);
    });

    test('engagement plus days opens the gate', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(reviewPromptProvider.notifier);
      await notifier.loaded;
      for (var day = 1; day <= ReviewPromptThresholds.minLaunches; day++) {
        await notifier.recordLaunch(now: DateTime(2026, 9, day, 9));
      }
      for (var i = 0; i < ReviewPromptThresholds.minEngagements; i++) {
        await notifier.recordEngagement();
      }

      expect(
        container.read(reviewPromptProvider).shouldAsk(now: DateTime(2026, 10, 1)),
        isTrue,
      );
    });
  });
}
