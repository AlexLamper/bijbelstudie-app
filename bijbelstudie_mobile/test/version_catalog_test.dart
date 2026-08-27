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
    version('elberfelder_1905', 'Elberfelder 1905', 'de'),
    version('statenvertaling', 'Statenvertaling', 'nl'),
    version('nbg51', 'NBG-vertaling 1951', 'nl'),
    version('kjv', 'King James Version', 'en'),
    version('asv', 'American Standard Version', 'en'),
    version('web', 'World English Bible', 'en'),
    version('geneva', 'Geneva Bible (1599)', 'en'),
    version('coverdale', 'Coverdale Bible (1535)', 'en'),
  ];

  test('Dutch first, then English, then the rest', () {
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
      'elberfelder_1905',
    ]);
  });

  test('does not mutate the list it was given', () {
    final before = fromServer.map((v) => v.id).toList();
    VersionCatalog.sorted(fromServer);
    expect(fromServer.map((v) => v.id).toList(), before);
  });

  test('groups carry the Dutch language name and keep the order', () {
    final groups = VersionCatalog.grouped(fromServer);

    expect(groups.map((g) => g.label), ['Nederlands', 'Engels', 'Duits']);
    expect(groups.first.versions.first.id, 'statenvertaling');
    expect(groups[1].versions.first.id, 'kjv');
    expect(groups.last.versions.single.id, 'elberfelder_1905');
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
    expect(groups[1].versions.last.id, 'ylt');
    expect(groups.map((g) => g.label), ['Nederlands', 'Engels', 'Duits']);
  });

  test('an unknown language sorts after the three we ship, never before', () {
    final withUnknown = [
      version('afri', 'Afrikaans', 'af'),
      ...fromServer,
    ];

    final languages = VersionCatalog.sorted(withUnknown).map((v) => v.language).toList();
    expect(languages.first, 'nl');
    expect(languages.last, 'af');
  });

  test('Luther 1912 is simply absent — nothing in the client filters it', () {
    // The removal is server-side (MOBILE_ALLOWED_BIBLES). This asserts the
    // client has no opinion of its own that could quietly resurrect it.
    expect(
      VersionCatalog.sorted(fromServer).map((v) => v.id),
      isNot(contains('luther_1912')),
    );
  });
}
