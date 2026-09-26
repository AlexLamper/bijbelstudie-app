/// Bronnen: the confessions, forms and catechism booklets of the Dutch
/// Reformed tradition, read in the app.
///
/// Mirrors the website's wire contract in `lib/content/bronnen/types.ts`
/// (`WorkSummary` for `/api/v1/bronnen`, `Work & {version}` for
/// `/api/v1/bronnen/<slug>`). The server may add fields at any time, so every
/// parser here ignores what it does not know, tolerates a missing optional
/// field and skips a block type it has never seen instead of failing the whole
/// work.
library;

String _str(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

String? _optStr(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _optInt(Object? value) => value is num ? value.toInt() : null;

List<Map<String, dynamic>> _maps(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map) item.cast<String, dynamic>(),
  ];
}

const _plurals = {
  'zondag': 'zondagen',
  'artikel': 'artikelen',
  'hoofdstuk': 'hoofdstukken',
  'formulier': 'formulieren',
  'gebed': 'gebeden',
  'belijdenis': 'belijdenissen',
  'deel': 'delen',
};

/// "52 zondagen", "1 artikel". Unknown nouns are used as they are.
String sectionCountLabel(String noun, int count) {
  final lower = noun.toLowerCase();
  return '$count ${count == 1 ? lower : _plurals[lower] ?? lower}';
}

/// "52 zondagen · 129 vragen", "37 artikelen".
String workCountLabel(String noun, int sectionCount, int questionCount) {
  final sections = sectionCountLabel(noun, sectionCount);
  // One undivided section ("Vragen en antwoorden"): only the questions count.
  if (sectionCount == 1 && questionCount > 0) {
    return '$questionCount ${questionCount == 1 ? 'vraag' : 'vragen'}';
  }
  return questionCount > 0
      ? '$sections · $questionCount ${questionCount == 1 ? 'vraag' : 'vragen'}'
      : sections;
}

/// "Guido de Brès · 1561", or just the year when the work is anonymous.
String workByline(String? author, String year) => [
  if (author != null && author.isNotEmpty) author,
  if (year.isNotEmpty) year,
].join(' · ');

class BronGroup {
  const BronGroup({required this.id, required this.label, this.description = ''});

  final String id;
  final String label;
  final String description;

  factory BronGroup.fromJson(Map<String, dynamic> json) => BronGroup(
    id: _str(json['id']),
    label: _str(json['label']),
    description: _str(json['description']),
  );
}

/// One row of a table of contents: a section without its text.
class BronSectionHead {
  const BronSectionHead({
    required this.id,
    required this.label,
    this.number,
    this.title,
  });

  final String id;
  final int? number;
  final String label;
  final String? title;

  factory BronSectionHead.fromJson(Map<String, dynamic> json) => BronSectionHead(
    id: _str(json['id']),
    number: _optInt(json['number']),
    label: _str(json['label']),
    title: _optStr(json['title']),
  );
}

/// One row of the `/api/v1/bronnen` index.
class BronWorkSummary {
  const BronWorkSummary({
    required this.slug,
    required this.title,
    required this.shortTitle,
    required this.group,
    required this.year,
    required this.description,
    required this.sectionNoun,
    required this.sectionCount,
    required this.questionCount,
    required this.version,
    required this.sections,
    this.author,
  });

  final String slug;
  final String title;
  final String shortTitle;
  final String group;
  final String? author;
  final String year;
  final String description;
  final String sectionNoun;
  final int sectionCount;
  final int questionCount;

  /// Content hash of the full payload; a cached work is refetched when it
  /// differs.
  final String version;
  final List<BronSectionHead> sections;

  String get byline => workByline(author, year);
  String get countLabel => workCountLabel(sectionNoun, sectionCount, questionCount);

  factory BronWorkSummary.fromJson(Map<String, dynamic> json) {
    final sections = _maps(json['sections'])
        .map(BronSectionHead.fromJson)
        .where((s) => s.id.isNotEmpty)
        .toList(growable: false);
    final title = _str(json['title']);
    return BronWorkSummary(
      slug: _str(json['slug']),
      title: title,
      shortTitle: _optStr(json['shortTitle']) ?? title,
      group: _str(json['group']),
      author: _optStr(json['author']),
      year: _str(json['year']),
      description: _str(json['description']),
      sectionNoun: _str(json['sectionNoun']),
      sectionCount: _optInt(json['sectionCount']) ?? sections.length,
      questionCount: _optInt(json['questionCount']) ?? 0,
      version: _str(json['version']),
      sections: sections,
    );
  }
}

class BronnenIndex {
  const BronnenIndex({required this.groups, required this.works});

  final List<BronGroup> groups;
  final List<BronWorkSummary> works;

  BronWorkSummary? work(String slug) {
    for (final w in works) {
      if (w.slug == slug) return w;
    }
    return null;
  }

  /// The groups in server order, each with its works, empty groups left out.
  /// A work whose group the app does not know is shown under "Overig" rather
  /// than dropped.
  List<(BronGroup, List<BronWorkSummary>)> get grouped {
    final known = {for (final g in groups) g.id};
    final result = <(BronGroup, List<BronWorkSummary>)>[
      for (final g in groups)
        (g, works.where((w) => w.group == g.id).toList(growable: false)),
    ];
    final rest = works.where((w) => !known.contains(w.group)).toList(growable: false);
    if (rest.isNotEmpty) {
      result.add((const BronGroup(id: '', label: 'Overig'), rest));
    }
    return result.where((entry) => entry.$2.isNotEmpty).toList(growable: false);
  }

  factory BronnenIndex.fromJson(Map<String, dynamic> json) => BronnenIndex(
    groups: _maps(json['groups'])
        .map(BronGroup.fromJson)
        .where((g) => g.id.isNotEmpty)
        .toList(growable: false),
    works: _maps(json['works'])
        .map(BronWorkSummary.fromJson)
        .where((w) => w.slug.isNotEmpty)
        .toList(growable: false),
  );
}

class BronSource {
  const BronSource({required this.name, required this.url, this.edition, this.note});

  final String name;
  final String url;
  final String? edition;
  final String? note;

  factory BronSource.fromJson(Map<String, dynamic> json) => BronSource(
    name: _str(json['name']),
    url: _str(json['url']),
    edition: _optStr(json['edition']),
    note: _optStr(json['note']),
  );
}

/// One Statenvertaling verse attached to a reference.
class BronRefVerse {
  const BronRefVerse({required this.n, required this.text});

  final int n;
  final String text;
}

/// A Scripture reference as printed ("Rom. 14:7, 8").
///
/// Resolved when the server could place it in the canon: then [readerBook] and
/// [chapter] open the app's reader, and [text] - when present - holds the
/// Statenvertaling verses. An unresolved reference carries only its [label]
/// and is shown as plain text, never linked.
class BronRef {
  const BronRef({
    required this.label,
    this.book,
    this.bookName,
    this.readerBook,
    this.chapter,
    this.verses,
    this.text = const [],
  });

  final String label;
  final String? book;
  final String? bookName;
  final String? readerBook;
  final int? chapter;
  final List<int>? verses;
  final List<BronRefVerse> text;

  bool get isResolved => readerBook != null && chapter != null && chapter! > 0;
  bool get hasText => isResolved && text.isNotEmpty;

  /// "Romeinen 14".
  String get chapterLabel => '${bookName ?? readerBook ?? ''} $chapter'.trim();

  factory BronRef.fromJson(Map<String, dynamic> json) {
    final bookName = _optStr(json['bookName']);
    final rawVerses = json['verses'];
    return BronRef(
      label: _str(json['label']),
      book: _optStr(json['book']),
      bookName: bookName,
      // `readerBook` is the key the reader opens a book by; older payloads
      // without it fall back on the display name, which the reader also knows.
      readerBook: _optStr(json['readerBook']) ?? (json['book'] is String ? bookName : null),
      chapter: _optInt(json['chapter']),
      verses: rawVerses is List
          ? [for (final v in rawVerses) if (v is num) v.toInt()]
          : null,
      text: [
        for (final v in _maps(json['text']))
          if (_optInt(v['n']) != null && v['text'] is String)
            BronRefVerse(n: _optInt(v['n'])!, text: v['text'] as String),
      ],
    );
  }
}

sealed class BronBlock {
  const BronBlock();

  /// Null for a block type this build does not know: the caller skips it.
  static BronBlock? fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'heading' => BronHeading(_str(json['text'])),
      'paragraph' => BronParagraph(
        number: _optInt(json['number']),
        text: _str(json['text']),
        refs: _refs(json['refs']),
      ),
      'qa' => BronQa(
        number: _optInt(json['number']),
        question: _str(json['question']),
        answer: _str(json['answer']),
        refs: _refs(json['refs']),
      ),
      _ => null,
    };
  }

  static List<BronRef> _refs(Object? value) => _maps(value)
      .map(BronRef.fromJson)
      .where((r) => r.label.isNotEmpty)
      .toList(growable: false);
}

class BronHeading extends BronBlock {
  const BronHeading(this.text);

  final String text;
}

class BronParagraph extends BronBlock {
  const BronParagraph({required this.text, this.number, this.refs = const []});

  final int? number;
  final String text;
  final List<BronRef> refs;
}

class BronQa extends BronBlock {
  const BronQa({
    required this.question,
    required this.answer,
    this.number,
    this.refs = const [],
  });

  final int? number;
  final String question;
  final String answer;
  final List<BronRef> refs;
}

class BronSection {
  const BronSection({
    required this.id,
    required this.label,
    required this.blocks,
    this.number,
    this.title,
  });

  final String id;
  final int? number;
  final String label;
  final String? title;
  final List<BronBlock> blocks;

  BronSectionHead get head =>
      BronSectionHead(id: id, number: number, label: label, title: title);

  factory BronSection.fromJson(Map<String, dynamic> json) => BronSection(
    id: _str(json['id']),
    number: _optInt(json['number']),
    label: _str(json['label']),
    title: _optStr(json['title']),
    blocks: [
      for (final b in _maps(json['blocks']))
        if (BronBlock.fromJson(b) case final block?) block,
    ],
  );
}

/// One work in full, as `/api/v1/bronnen/<slug>` serves it.
class BronWork {
  const BronWork({
    required this.slug,
    required this.title,
    required this.shortTitle,
    required this.group,
    required this.year,
    required this.description,
    required this.sectionNoun,
    required this.source,
    required this.rights,
    required this.sections,
    required this.version,
    this.author,
  });

  final String slug;
  final String title;
  final String shortTitle;
  final String group;
  final String? author;
  final String year;
  final String description;
  final String sectionNoun;
  final BronSource source;
  final String rights;
  final List<BronSection> sections;
  final String version;

  String get byline => workByline(author, year);

  int get questionCount => sections.fold(
    0,
    (n, s) => n + s.blocks.whereType<BronQa>().length,
  );

  String get countLabel =>
      workCountLabel(sectionNoun, sections.length, questionCount);

  int indexOfSection(String id) => sections.indexWhere((s) => s.id == id);

  BronSection? section(String id) {
    final i = indexOfSection(id);
    return i < 0 ? null : sections[i];
  }

  factory BronWork.fromJson(Map<String, dynamic> json) {
    final title = _str(json['title']);
    final source = json['source'];
    return BronWork(
      slug: _str(json['slug']),
      title: title,
      shortTitle: _optStr(json['shortTitle']) ?? title,
      group: _str(json['group']),
      author: _optStr(json['author']),
      year: _str(json['year']),
      description: _str(json['description']),
      sectionNoun: _str(json['sectionNoun']),
      source: source is Map
          ? BronSource.fromJson(source.cast<String, dynamic>())
          : const BronSource(name: '', url: ''),
      rights: _str(json['rights']),
      sections: _maps(json['sections'])
          .map(BronSection.fromJson)
          .where((s) => s.id.isNotEmpty)
          .toList(growable: false),
      version: _str(json['version']),
    );
  }
}
