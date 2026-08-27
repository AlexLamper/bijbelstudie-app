import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bijbelstudie_mobile/features/bible/present/bible_providers.dart';
import 'package:bijbelstudie_mobile/features/dashboard/data/dashboard_models.dart';
import 'package:bijbelstudie_mobile/features/settings/data/reading_settings.dart';

/// Where the reader opens.
///
/// The app used to reset to Genesis 1 on every launch, so these lock down the
/// rule that replaced it: the device copy and the server copy are both read,
/// the more recently written one wins, and nothing is painted until one of them
/// has answered.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  /// The location once hydration has settled. Waiting on `restored` rather than
  /// on a fixed delay keeps these tests off the clock.
  Future<ReaderLocation> settled(ProviderContainer container) async {
    final completer = Completer<ReaderLocation>();
    final sub = container.listen<ReaderLocation>(
      readerLocationProvider,
      (previous, next) {
        if (next.restored && !completer.isCompleted) completer.complete(next);
      },
      fireImmediately: true,
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 5));
    } finally {
      sub.close();
    }
  }

  ProviderContainer hostWith({
    Map<String, Object> prefs = const {},
    LastRead? remote,
  }) {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderContainer(
      overrides: [
        remoteReaderLocationProvider.overrideWith((ref) async => remote),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('opens on the chapter stored on this device', () async {
    final container = hostWith(
      prefs: {
        'reader.lastBook': 'Johannes',
        'reader.lastChapter': 3,
        'reader.lastVersionId': 'nbg51',
        'reader.lastLocationAt': DateTime(2026, 8, 20).millisecondsSinceEpoch,
      },
    );

    final location = await settled(container);
    expect(location.book, 'Johannes');
    expect(location.chapter, 3);
    expect(location.versionId, 'nbg51');
  });

  test('opens on Genesis 1 only when neither copy has anything', () async {
    final container = hostWith();

    final location = await settled(container);
    expect(location.book, 'Genesis');
    expect(location.chapter, 1);
    expect(location.restored, isTrue);
  });

  test('takes the server copy on a device that has never read anything', () async {
    // The second-device case: a fresh install knows nothing, the account does.
    final container = hostWith(
      remote: LastRead(
        book: 'Romeinen',
        chapter: 8,
        version: 'statenvertaling',
        updatedAt: DateTime(2026, 8, 25),
      ),
    );

    final location = await settled(container);
    expect(location.book, 'Romeinen');
    expect(location.chapter, 8);
  });

  test('takes the server copy when it is the more recent of the two', () async {
    final container = hostWith(
      prefs: {
        'reader.lastBook': 'Johannes',
        'reader.lastChapter': 3,
        'reader.lastLocationAt': DateTime(2026, 8, 20).millisecondsSinceEpoch,
      },
      remote: LastRead(
        book: 'Romeinen',
        chapter: 8,
        version: 'statenvertaling',
        updatedAt: DateTime(2026, 8, 25),
      ),
    );

    final location = await settled(container);
    expect(location.book, 'Romeinen');
    expect(location.chapter, 8);
  });

  test('keeps the device copy when it is the more recent of the two', () async {
    // The offline case: this device read on past the last chapter the server
    // ever heard about.
    final container = hostWith(
      prefs: {
        'reader.lastBook': 'Johannes',
        'reader.lastChapter': 3,
        'reader.lastLocationAt': DateTime(2026, 8, 25).millisecondsSinceEpoch,
      },
      remote: LastRead(
        book: 'Romeinen',
        chapter: 8,
        version: 'statenvertaling',
        updatedAt: DateTime(2026, 8, 20),
      ),
    );

    final location = await settled(container);
    expect(location.book, 'Johannes');
    expect(location.chapter, 3);
  });

  test('never overrules a chapter the user opened while it was resolving', () async {
    final container = hostWith(
      prefs: {
        'reader.lastBook': 'Johannes',
        'reader.lastChapter': 3,
        'reader.lastLocationAt': DateTime(2026, 8, 20).millisecondsSinceEpoch,
      },
    );

    // Tapping "ga verder" on the dashboard a moment after launch: hydration is
    // still in flight and must not pull the reader back off this chapter.
    container
        .read(readerLocationProvider.notifier)
        .openChapter(book: 'Psalmen', chapter: 23);

    final location = await settled(container);
    expect(location.book, 'Psalmen');
    expect(location.chapter, 23);

    // And still there once hydration has had every chance to finish.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(readerLocationProvider).book, 'Psalmen');
  });

  test('writes the position down as soon as the reader pages on', () async {
    final container = hostWith(
      prefs: {
        'reader.lastBook': 'Johannes',
        'reader.lastChapter': 3,
        'reader.lastLocationAt': DateTime(2026, 8, 20).millisecondsSinceEpoch,
      },
    );
    await settled(container);

    container.read(readerLocationProvider.notifier).nextChapter(const [1, 2, 3, 4, 5]);
    expect(container.read(readerLocationProvider).chapter, 4);

    // Persisted without waiting for the chapter text to arrive, so a chapter
    // that fails to load is still where the app reopens.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('reader.lastBook'), 'Johannes');
    expect(prefs.getInt('reader.lastChapter'), 4);
    expect(container.read(readingSettingsProvider).lastChapter, 4);
  });

  group('applyPreferredVersion', () {
    test('moves the reader onto the chosen translation and stores it', () async {
      final container = hostWith(
        prefs: {
          'reader.lastBook': 'Johannes',
          'reader.lastChapter': 3,
          'reader.lastVersionId': 'statenvertaling',
          'reader.lastLocationAt': DateTime(2026, 8, 20).millisecondsSinceEpoch,
        },
      );
      await settled(container);

      container.read(readerLocationProvider.notifier).applyPreferredVersion('kjv');

      expect(container.read(readerLocationProvider).versionId, 'kjv');
      expect(container.read(readingSettingsProvider).lastVersionId, 'kjv');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('reader.lastVersionId'), 'kjv');
    });

    test('leaves the chapter and its timestamp alone', () async {
      // Unlike openChapter, this must not stamp a reading position: doing so
      // would claim "Johannes 3, just now" on a device that has only been
      // through the setup wizard, and beat a genuinely newer position the
      // account has on the website.
      final storedAt = DateTime(2026, 8, 20).millisecondsSinceEpoch;
      final container = hostWith(
        prefs: {
          'reader.lastBook': 'Johannes',
          'reader.lastChapter': 3,
          'reader.lastLocationAt': storedAt,
        },
      );
      await settled(container);

      container.read(readerLocationProvider.notifier).applyPreferredVersion('kjv');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final location = container.read(readerLocationProvider);
      expect(location.book, 'Johannes');
      expect(location.chapter, 3);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('reader.lastLocationAt'), storedAt);
    });

    test('a choice made before hydration finishes still wins', () async {
      // The setup wizard is often what triggers the very first read of the
      // reading settings, so the disk load can still be in flight when the
      // reader taps a translation. The stored value must not overwrite it.
      final container = hostWith(
        prefs: {'reader.lastVersionId': 'statenvertaling'},
      );

      container.read(readerLocationProvider.notifier).applyPreferredVersion('kjv');
      await settled(container);

      expect(container.read(readerLocationProvider).versionId, 'kjv');
      expect(container.read(readingSettingsProvider).lastVersionId, 'kjv');
    });
  });
}
