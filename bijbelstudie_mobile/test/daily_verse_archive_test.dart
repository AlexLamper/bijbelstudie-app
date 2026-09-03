import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bijbelstudie_mobile/features/dashboard/data/daily_verse_store.dart';

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
}
