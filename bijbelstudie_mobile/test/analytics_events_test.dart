import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the funnel against the two ways it silently stops measuring.
///
/// **Declared but never emitted.** `paywall_hit` and `paywall_cta_clicked` sat
/// in [AnalyticsEvents] for weeks without a single call site, so the iOS funnel
/// began at `pricing_viewed` while the web funnel began two steps earlier. The
/// two were built to be compared and could not be. Nothing failed, no error was
/// logged; the events were simply never sent.
///
/// **Emitted with a value the server drops.** `/api/v1/analytics` validates
/// against a fixed allowlist in `lib/analyticsSchema.ts` and discards anything
/// outside it — no error, no 400, just a row that never appears. A typo in a
/// `surface` or `source` string is therefore invisible at runtime and invisible
/// in review.
///
/// Both mirrors below are copies of the server's allowlist. They are duplicated
/// deliberately: the schema lives in a different repository, so a compile-time
/// import is impossible and a stale copy failing loudly here is the next best
/// thing.
void main() {
  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  final sources = {
    for (final file in dartFiles) file.path: file.readAsStringSync(),
  };

  /// `lib/analyticsSchema.ts` → `EVENTS.paywall_hit.surface`.
  const allowedSurfaces = {
    'commentary',
    'ai_limit',
    'original_text',
    'plan_limit',
    'offline',
    'resources',
  };

  /// `lib/analyticsSchema.ts` → `EVENTS.pricing_viewed.source`.
  const allowedSources = {
    'sidebar_cta',
    'paywall_commentary',
    'paywall_ai',
    'paywall_plan',
    'nav',
    'direct',
    'landing',
    'unknown',
    'app_profile',
    'app_resources',
    'app_study',
    'app_ai',
  };

  group('every declared event is emitted somewhere', () {
    final declaration = RegExp(r"static const (\w+) = '([a-z_]+)';");
    final analyticsFile = sources.entries.firstWhere(
      (e) => e.key.endsWith('analytics.dart'),
    );

    final declared = {
      for (final m in declaration.allMatches(analyticsFile.value))
        m.group(1)!: m.group(2)!,
    };

    test('the scan found the event constants', () {
      // Guards against the regex matching nothing after a refactor, which would
      // turn every assertion below into a no-op that always passes.
      expect(declared, isNotEmpty);
    });

    for (final entry in declared.entries) {
      test('${entry.value} has a call site', () {
        final callers = sources.entries
            .where((e) => e.key != analyticsFile.key)
            .where((e) => e.value.contains('AnalyticsEvents.${entry.key}'))
            .map((e) => e.key)
            .toList();

        expect(
          callers,
          isNotEmpty,
          reason:
              'AnalyticsEvents.${entry.key} ("${entry.value}") is declared but '
              'never tracked. Either emit it or delete the constant — a name '
              'with no call site reads as a measured step that is not measured.',
        );
      });
    }
  });

  group('every tracked property value is one the server accepts', () {
    final surfaceLiteral = RegExp(r"'surface':\s*'([a-z_]+)'");
    // Both routes carry the same source values: /pro-intro is the funnel that
    // leads into /premium, and it hands its source straight through.
    final sourceLiteral = RegExp(r"'/(?:premium|pro-intro)\?source=([a-z_]+)'");

    test('surface values are in the allowlist', () {
      final found = <String, String>{};
      sources.forEach((path, text) {
        for (final m in surfaceLiteral.allMatches(text)) {
          found[m.group(1)!] = path;
        }
      });

      expect(found, isNotEmpty, reason: 'No surface literals found to check.');

      for (final entry in found.entries) {
        expect(
          allowedSurfaces,
          contains(entry.key),
          reason:
              '"${entry.key}" in ${entry.value} is not in paywall_hit.surface. '
              'The server drops the event without an error, so this is the only '
              'place it can be caught.',
        );
      }
    });

    test('paywall source values are in the allowlist', () {
      final found = <String, String>{};
      sources.forEach((path, text) {
        for (final m in sourceLiteral.allMatches(text)) {
          found[m.group(1)!] = path;
        }
      });

      expect(found, isNotEmpty, reason: 'No ?source= literals found to check.');

      for (final entry in found.entries) {
        expect(
          allowedSources,
          contains(entry.key),
          reason:
              '"${entry.key}" in ${entry.value} is not in pricing_viewed.source. '
              'Add it to lib/analyticsSchema.ts in the web repo first, or the '
              'paywall visit is recorded with no attribution.',
        );
      }
    });
  });
}
