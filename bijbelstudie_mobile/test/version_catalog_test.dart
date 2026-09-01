import 'package:flutter_test/flutter_test.dart';

import 'package:bijbelstudie_mobile/features/bible/domain/bible_models.dart';
import 'package:bijbelstudie_mobile/features/bible/domain/version_catalog.dart';

/// `/api/v1/bibles` hands versions back in manifest order, which is the order
/// the files sit in on the server. These pin the order the app imposes on top
/// of it — the first question a new account is ever asked.
void main() {
  BibleSource version(String id, String name, String language) =>
      BibleSource(id: id, name: name, language: language, attribution: '');

  /// Deliberately shuffled, and in roughly the order the server really returns
  /// them: Canisius first, Statenvertaling sixth, languages interleaved.
  final fromServer = [
    version('canisiusbijbel', 'Canisiusbijbel 1939', 'nl'),
    version('heilige_schrift_1917', 'De Heilige Schrift 1917', 'nl'),
    version('statenvertaling', 'Statenvertaling', 'nl'),
    version('nbg51', 'NBG-vertaling 1951', 'nl'),
    version('kjv', 'King James Version', 'en'),
    version('asv', 'American Standard Version', 'en'),
    version('web', 'World English Bible', 'en'),
    version('geneva', 'Geneva Bible (1599)', 'en'),
    version('coverdale', 'Coverdale Bible (1535)', 'en'),
  ];

  test('Dutch first, then English', () {
    final ids = VersionCatalog.sorted(fromServer).map((v) => v.id).toList();

    expect(ids, [
      'statenvertaling',
      'nbg51',
      'canisiusbijbel',
      'heilige_schrift_1917',
      'kjv',
      'asv',
      'web',
      'geneva',
      'coverdale',
    ]);
  });

  test('does not mutate the list it was given', () {
    final before = fromServer.map((v) => v.id).toList();
    VersionCatalog.sorted(fromServer);
    expect(fromServer.map((v) => v.id).toList(), before);
  });

  test('groups carry the Dutch language name and keep the order', () {
    final groups = VersionCatalog.grouped(fromServer);

    // Two groups, so exactly one separator in the picker.
    expect(groups.map((g) => g.label), ['Nederlands', 'Engels']);
    expect(groups.first.versions.first.id, 'statenvertaling');
    expect(groups.last.versions.first.id, 'kjv');
  });

  test('an unranked version lands at the end of its own language group', () {
    // A translation added to the server manifest must appear without an app
    // release, and must not outrank the ones that were ranked by hand.
    final withNewcomer = [
      ...fromServer,
      version('nieuwe_nl', 'Een Nieuwe Vertaling', 'nl'),
      version('ylt', 'Young''s Literal Translation', 'en'),
    ];

    final groups = VersionCatalog.grouped(withNewcomer);
    expect(groups.first.versions.last.id, 'nieuwe_nl');
    expect(groups.last.versions.last.id, 'ylt');
    expect(groups.map((g) => g.label), ['Nederlands', 'Engels']);
  });

  test('a language we do not ship sorts after the two we do, never before', () {
    // German is website-only now, so if it ever reappeared in the manifest it
    // must land at the end rather than in the middle of the English block.
    final withUnknown = [
      version('elberfelder_1905', 'Elberfelder 1905', 'de'),
      version('afri', 'Afrikaans', 'af'),
      ...fromServer,
    ];

    final languages = VersionCatalog.sorted(withUnknown).map((v) => v.language).toList();
    expect(languages.first, 'nl');
    expect(languages.sublist(languages.length - 2), ['af', 'de']);
  });

  test('the German translations are simply absent from what the server sends', () {
    // Luther 1912 and Elberfelder 1905 were dropped server-side
    // (MOBILE_ALLOWED_BIBLES). This asserts the client has no opinion of its
    // own that could quietly resurrect either.
    final ids = VersionCatalog.sorted(fromServer).map((v) => v.id);
    expect(ids, isNot(contains('luther_1912')));
    expect(ids, isNot(contains('elberfelder_1905')));
    expect(VersionCatalog.grouped(fromServer).map((g) => g.label), isNot(contains('Duits')));
  });

  group('short codes', () {
    test('the hand-kept codes are the ones readers write', () {
      expect(VersionCatalog.shortCode(version('statenvertaling', 'Statenvertaling', 'nl')), 'SV');
      expect(VersionCatalog.shortCode(version('nbg51', 'NBG-vertaling 1951', 'nl')), 'NBG51');
      expect(VersionCatalog.shortCode(version('kjv', 'King James Version', 'en')), 'KJV');
      expect(VersionCatalog.shortCode(version('hsv', 'Herziene Statenvertaling', 'nl')), 'HSV');
    });

    test('every version the server sends today gets a badge', () {
      for (final v in fromServer) {
        final code = VersionCatalog.shortCode(v);
        expect(code, isNotEmpty, reason: v.id);
        expect(code.length, lessThanOrEqualTo(VersionCatalog.maxShortCodeLength), reason: v.id);
      }
    });

    test('an unknown version falls back to initials of its name', () {
      expect(
        VersionCatalog.shortCodeFor(id: 'nieuwe_nl', name: 'Een Nieuwe Vertaling'),
        'ENV',
      );
      expect(
        VersionCatalog.shortCodeFor(id: 'ylt', name: "Young's Literal Translation"),
        'YLT',
      );
    });

    test('a trailing year is kept only when the whole code still fits', () {
      // `E1905` fits; `DHS1917` does not, and a truncated `DHS191` would be
      // worse than no year at all.
      expect(VersionCatalog.shortCodeFor(id: 'elberfelder_1905', name: 'Elberfelder 1905'), 'E1905');
      expect(
        VersionCatalog.shortCodeFor(id: 'unknown_1917', name: 'De Heilige Schrift 1917'),
        'DHS',
      );
    });

    test('the badge is never empty and never longer than the cap', () {
      expect(VersionCatalog.shortCodeFor(id: 'x', name: ''), 'X');
      expect(VersionCatalog.shortCodeFor(id: '', name: '---'), '?');
      final long = VersionCatalog.shortCodeFor(
        id: 'a_very_long_identifier_indeed',
        name: 'Alpha Beta Gamma Delta Epsilon Zeta Eta Theta',
      );
      expect(long.length, VersionCatalog.maxShortCodeLength);
      expect(long, 'ABGDEZ');
    });
  });
}
