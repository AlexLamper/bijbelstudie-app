import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bijbelstudie_mobile/features/dashboard/data/daily_verse_store.dart';
import 'package:bijbelstudie_mobile/features/dashboard/data/dashboard_models.dart';
import 'package:bijbelstudie_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:bijbelstudie_mobile/features/dashboard/present/dashboard_providers.dart';
import 'package:bijbelstudie_mobile/features/settings/data/reading_settings.dart';

const _nbgNotice = 'NBG-vertaling 1951© 1951 Nederlands-Vlaams Bijbelgenootschap';

/// Answers `getDailyVerse` and records what it was asked for; every other
/// member is unused by the provider under test.
class _RecordingRepository implements DashboardRepository {
  final requested = <String?>[];

  @override
  Future<DailyVerse?> getDailyVerse({String? versionId}) async {
    requested.add(versionId);
    return DailyVerse.fromJson({
      'text': 'Want zo lief heeft God de wereld gehad',
      'reference': 'John 3:16',
      'book': 'John',
      'chapter': 3,
      'verse': 16,
      'version': 'NBG-vertaling 1951',
      'versionId': versionId,
      'attribution': _nbgNotice,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedDashboard extends DashboardNotifier {
  @override
  Future<DashboardData> build() async => const DashboardData(
    name: 'Test',
    isPro: false,
    streak: 0,
    freezes: 0,
    readChapters: {},
    weekDays: [],
    weekTotal: 0,
    notesCount: 0,
    recentNotes: [],
    badges: [],
  );
}

void main() {
  test('server archive merges into the device copy and persists', () async {
    SharedPreferences.setMockInitialValues({
      'daytext.history': jsonEncode([
        {
          'date': '2026-09-03',
          'text': 'Lokaal',
          'reference': 'Genesis 1:1',
          'book': 'Genesis',
          'chapter': 1,
          'verse': 1,
          'version': 'SV',
        },
      ]),
    });

    final c1 = ProviderContainer();
    c1.read(dailyVerseStoreProvider);
    await c1.read(dailyVerseStoreProvider.notifier).mergeServer(const [
          DailyVerseEntry(
            date: '2026-09-01',
            text: 'Server een',
            reference: 'Psalmen 23:1',
            book: 'Psalmen',
            chapter: 23,
            verse: 1,
            version: 'SV',
          ),
          DailyVerseEntry(
            date: '2026-09-03',
            text: 'Server botst met lokaal',
            reference: 'Anders 1:1',
            book: 'Anders',
            chapter: 1,
            verse: 1,
            version: 'SV',
          ),
        ]);

    final history = c1.read(dailyVerseStoreProvider).history;
    expect(history.map((e) => e.date), ['2026-09-03', '2026-09-01']);
    // Device entry wins on a clash.
    expect(history.first.text, 'Lokaal');
    c1.dispose();

    // Survives a restart.
    final c2 = ProviderContainer();
    c2.read(dailyVerseStoreProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c2.read(dailyVerseStoreProvider).history.length, 2);
    c2.dispose();
  });

  test('empty server archive leaves the device copy alone', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    c.read(dailyVerseStoreProvider);
    await c.read(dailyVerseStoreProvider.notifier).mergeServer(const []);
    expect(c.read(dailyVerseStoreProvider).history, isEmpty);
    c.dispose();
  });

  test('daytext payload carries the translation id and notice', () {
    final verse = DailyVerse.fromJson({
      'text': 'x',
      'reference': 'John 3:16',
      'book': 'John',
      'chapter': 3,
      'verse': 16,
      'version': 'NBG-vertaling 1951',
      'versionId': 'nbg51',
      'attribution': _nbgNotice,
    })!;
    expect(verse.versionId, 'nbg51');
    expect(verse.attribution, _nbgNotice);

    // An old payload without them still parses.
    final old = DailyVerse.fromJson({'text': 'x', 'version': 'Statenvertaling'})!;
    expect(old.versionId, isNull);
    expect(old.attribution, isNull);
  });

  test("switching translation replaces today's entry, notice included", () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final store = c.read(dailyVerseStoreProvider.notifier);

    const sv = DailyVerse(
      text: 'Want alzo lief',
      reference: 'Johannes 3:16',
      book: 'Johannes',
      chapter: 3,
      verse: 16,
    );
    const nbg = DailyVerse(
      text: 'Want zo lief',
      reference: 'Johannes 3:16',
      book: 'Johannes',
      chapter: 3,
      verse: 16,
      versionId: 'nbg51',
      attribution: _nbgNotice,
    );
    await store.remember(sv, version: 'SV');
    await store.remember(nbg, version: 'NBG51');

    final history = c.read(dailyVerseStoreProvider).history;
    expect(history.length, 1);
    expect(history.first.text, 'Want zo lief');
    expect(history.first.version, 'NBG51');
    expect(history.first.attribution, _nbgNotice);
    expect(
      DailyVerseEntry.fromJson(history.first.toJson())!.attribution,
      _nbgNotice,
    );
  });

  test("verse of the day follows the reader's translation", () async {
    SharedPreferences.setMockInitialValues({'reader.lastVersionId': 'nbg51'});
    final repo = _RecordingRepository();
    final c = ProviderContainer(
      overrides: [
        dashboardRepositoryProvider.overrideWithValue(repo),
        dashboardProvider.overrideWith(_FixedDashboard.new),
      ],
    );
    addTearDown(c.dispose);
    final sub = c.listen(translatedDailyVerseProvider, (_, _) {});
    addTearDown(sub.close);

    await c.read(readingSettingsProvider.notifier).loaded;
    final verse = await c.read(translatedDailyVerseProvider.future);
    expect(verse?.versionId, 'nbg51');
    expect(verse?.attribution, _nbgNotice);
    expect(repo.requested.last, 'nbg51');

    // Back to the Statenvertaling: no request, the dashboard's copy serves.
    final calls = repo.requested.length;
    await c
        .read(readingSettingsProvider.notifier)
        .setLastVersion('statenvertaling');
    expect(await c.read(translatedDailyVerseProvider.future), isNull);
    expect(repo.requested.length, calls);

    await c.read(readingSettingsProvider.notifier).setLastVersion('kjv');
    await c.read(translatedDailyVerseProvider.future);
    expect(repo.requested.last, 'kjv');
  });
}
