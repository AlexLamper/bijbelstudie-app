/// The reverse trial and the personal limit, as the server reports them.
///
/// Every new account gets Pro on its first three ACTIVE days (days on which
/// the app or the website was opened), counted on the server. While those
/// days run, the server counts four features; when they end, the one used
/// most keeps a tiny daily allowance and everything else drops to the normal
/// free limits. The numbers, the rules and the enforcement are the website's
/// (`lib/entitlements.ts`, `lib/reverseTrialRules.ts`); this file only parses
/// `/api/v1/me`'s additive `trial` and `limits` objects and words them - with
/// the same sentences the website uses, so the two clients never disagree.
library;

/// The five features the trial weighs. `id` is the server's string.
enum ProFeature {
  /// The guided lessons. Free and unlimited for everyone but the reader whose
  /// personal limit they are: one NEW lesson a day, a begun one always
  /// finished.
  studies('studies', 'de lessen'),
  ai('ai', 'AI-vragen'),
  notes('notes', 'notities'),
  study('study', 'studiemateriaal'),
  audio('audio', 'muziek en voorlezen');

  const ProFeature(this.id, this.name);

  final String id;

  /// In running text: "Omdat je AI-vragen het meest gebruikte".
  final String name;

  static ProFeature? fromId(Object? id) {
    for (final feature in values) {
      if (feature.id == id) return feature;
    }
    return null;
  }
}

int _count(Object? value) {
  if (value is num && value.isFinite && value > 0) return value.round();
  return 0;
}

int? _optionalInt(Object? value) => value is num ? value.toInt() : null;

/// What the trial counted. Chapters are only for the recap.
class TrialUsage {
  const TrialUsage({
    this.ai = 0,
    this.notes = 0,
    this.highlights = 0,
    this.study = 0,
    this.audio = 0,
    this.lessons = 0,
    this.lessonSteps = 0,
    this.chapters = 0,
  });

  final int ai;
  final int notes;
  final int highlights;
  final int study;
  final int audio;

  /// Lessons finished, and lesson steps worked through for the first time.
  final int lessons;
  final int lessonSteps;
  final int chapters;

  factory TrialUsage.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const {};
    return TrialUsage(
      ai: _count(j['ai']),
      notes: _count(j['notes']),
      highlights: _count(j['highlights']),
      study: _count(j['study']),
      audio: _count(j['audio']),
      lessons: _count(j['lessons']),
      lessonSteps: _count(j['lessonSteps']),
      chapters: _count(j['chapters']),
    );
  }
}

/// `/api/v1/me.trial`. Null on an account created before the reverse trial.
class ReverseTrial {
  const ReverseTrial({
    required this.active,
    required this.daysUsed,
    required this.daysTotal,
    this.endsAt,
    this.topFeature,
    this.usage = const TrialUsage(),
    this.recapPending = false,
    this.existingAccount = false,
    this.announce = false,
  });

  /// True while the Pro days run; false once they ended.
  final bool active;
  final int daysUsed;
  final int daysTotal;

  /// Midnight after the last day, once that day is under way.
  final DateTime? endsAt;

  /// The feature that is (or will be) the personal limit; null when none was used.
  final ProFeature? topFeature;
  final TrialUsage usage;

  /// "Je Pro-dagen zitten erop" is due: once, on either client.
  final bool recapPending;

  /// The one-time trial of an account from before the reverse trial.
  final bool existingAccount;

  /// "Je hebt 3 dagen Pro gekregen" is due: once, on either client, while the
  /// trial of an older account runs.
  final bool announce;

  bool get ended => !active;
  int get daysLeft => (daysTotal - daysUsed).clamp(0, daysTotal);

  static ReverseTrial? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final state = json['state'];
    if (state != 'active' && state != 'ended') return null;
    final ends = json['endsAt'];
    return ReverseTrial(
      active: state == 'active',
      daysUsed: _count(json['daysUsed']),
      daysTotal: _optionalInt(json['daysTotal']) ?? 3,
      endsAt: ends is String ? DateTime.tryParse(ends) : null,
      topFeature: ProFeature.fromId(json['topFeature']),
      usage: TrialUsage.fromJson(json['usage'] as Map<String, dynamic>?),
      recapPending: json['recapPending'] == true,
      existingAccount: json['origin'] == 'existing',
      announce: json['announce'] == true,
    );
  }
}

/// `/api/v1/me.limits`: what this account may do right now. The routes
/// enforce the same object; the app mirrors it so a gate never promises what
/// the server will refuse.
class AccountLimits {
  const AccountLimits({
    required this.aiDaily,
    required this.notes,
    required this.crossRefs,
    required this.studyChaptersPerDay,
    required this.audioPerDay,
    required this.offline,
    this.lessonsPerDay,
    this.limitedFeature,
  });

  final int aiDaily;

  /// Notes an account may hold before a new one is refused; null = unlimited.
  final int? notes;

  /// Cross-references per verse; null = all.
  final int? crossRefs;

  /// Null: the normal free preview of paid study material. A number: that many
  /// chapters a day in full, nothing beyond.
  final int? studyChaptersPerDay;

  /// Music tracks per day; null = unlimited, 0 = Pro only.
  final int? audioPerDay;
  final bool offline;

  /// New lessons a day; null = as many as you like (everyone but one reader).
  final int? lessonsPerDay;

  /// The feature with a personal limit, or null.
  final ProFeature? limitedFeature;

  /// The normal free account, for a server that has not sent `limits` yet.
  /// Mirrors `FREE_LIMITS` in the website's lib/entitlements.ts.
  static const free = AccountLimits(
    aiDaily: 3,
    notes: 10,
    crossRefs: 2,
    studyChaptersPerDay: null,
    audioPerDay: 0,
    offline: false,
  );

  static const pro = AccountLimits(
    aiDaily: 200,
    notes: null,
    crossRefs: null,
    studyChaptersPerDay: null,
    audioPerDay: null,
    offline: true,
  );

  static AccountLimits? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return AccountLimits(
      aiDaily: _optionalInt(json['aiDaily']) ?? free.aiDaily,
      notes: _optionalInt(json['notes']),
      crossRefs: _optionalInt(json['crossRefs']),
      studyChaptersPerDay: _optionalInt(json['studyChaptersPerDay']),
      audioPerDay: _optionalInt(json['audioPerDay']),
      offline: json['offline'] == true,
      lessonsPerDay: _optionalInt(json['lessonsPerDay']),
      limitedFeature: ProFeature.fromId(json['limitedFeature']),
    );
  }
}

/// The sentences, word for word the website's (`usageHeadline`,
/// `PERSONAL_LIMIT_LINES`, `personalLimitReason` in lib/entitlements.ts).
/// Each number is the server's TINY_* value; keep them in step.
class PersonalPlanCopy {
  const PersonalPlanCopy._();

  static const tinyAiDaily = 1;
  static const tinyStudyChapters = 1;
  static const tinyCrossRefs = 1;
  static const tinyAudioDaily = 1;
  static const tinyLessonsDaily = 1;

  static String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

  static String _inDays(int days) => days > 0 ? ' in ${_plural(days, 'dag', 'dagen')}' : '';

  /// "Je stelde 9 vragen aan de AI in 3 dagen". Null when there is nothing to say.
  static String? headline(ProFeature feature, TrialUsage usage, int days) {
    switch (feature) {
      case ProFeature.ai:
        return usage.ai > 0 ? 'Je stelde ${_plural(usage.ai, 'vraag', 'vragen')} aan de AI${_inDays(days)}' : null;
      case ProFeature.notes:
        if (usage.notes > 0) return 'Je schreef ${_plural(usage.notes, 'notitie', 'notities')}${_inDays(days)}';
        return usage.highlights > 0
            ? 'Je markeerde ${_plural(usage.highlights, 'vers', 'verzen')}${_inDays(days)}'
            : null;
      case ProFeature.study:
        return usage.study > 0
            ? 'Je opende ${usage.study} keer commentaar, grondtekst of kruisverwijzingen${_inDays(days)}'
            : null;
      case ProFeature.audio:
        return usage.audio > 0 ? 'Je luisterde ${usage.audio} keer naar muziek of voorlezen${_inDays(days)}' : null;
      case ProFeature.studies:
        if (usage.lessons > 0) return 'Je deed ${_plural(usage.lessons, 'les', 'lessen')}${_inDays(days)}';
        return usage.lessonSteps > 0
            ? 'Je zette ${_plural(usage.lessonSteps, 'stap', 'stappen')} in je lessen${_inDays(days)}'
            : null;
    }
  }

  /// What a free account keeps of [feature] when it is the personal limit.
  static String limitLine(ProFeature feature) => switch (feature) {
    ProFeature.ai => '${_plural(tinyAiDaily, 'vraag', 'vragen')} per dag aan de AI-assistent',
    ProFeature.notes => 'geen nieuwe notities; je bestaande notities blijf je lezen en bewerken',
    ProFeature.study =>
      'elke dag ${_plural(tinyStudyChapters, 'hoofdstuk', 'hoofdstukken')} met al het commentaar en de grondtekst, '
          'en ${_plural(tinyCrossRefs, 'kruisverwijzing', 'kruisverwijzingen')} per vers',
    ProFeature.audio => '$tinyAudioDaily muzieknummer of voorgelezen hoofdstuk per dag',
    ProFeature.studies =>
      '${_plural(tinyLessonsDaily, 'nieuwe les', 'nieuwe lessen')} per dag; een les waar je al aan begonnen bent, maak je altijd af',
  };

  /// The refusal at the personal limit.
  static String reason(ProFeature feature) => switch (feature) {
    ProFeature.ai => 'Je gratis AI-vraag voor vandaag is gesteld. Morgen kun je er weer $tinyAiDaily stellen.',
    ProFeature.notes =>
      'Nieuwe notities schrijven hoort bij Pro. Je bestaande notities blijf je lezen en bewerken, en markeren blijft gratis.',
    ProFeature.study =>
      'Je gratis hoofdstuk met al het studiemateriaal is voor vandaag gebruikt. Morgen opent er weer $tinyStudyChapters.',
    ProFeature.audio =>
      'Je gratis muzieknummer of voorgelezen hoofdstuk is voor vandaag gebruikt. Morgen kun je er weer $tinyAudioDaily kiezen.',
    ProFeature.studies =>
      'Je nieuwe les voor vandaag ben je al begonnen. Morgen kun je weer $tinyLessonsDaily nieuwe les beginnen; een les waar je al in zit, maak je gewoon af.',
  };

  /// What Pro gives back, said under the refusal on the paywall.
  static String proLine(ProFeature feature) => switch (feature) {
    ProFeature.ai => 'Met Pro stel je er 200 per dag.',
    ProFeature.notes => 'Met Pro schrijf je weer onbeperkt notities.',
    ProFeature.study => 'Met Pro open je alle commentaren en de grondtekst bij elk hoofdstuk.',
    ProFeature.audio => 'Met Pro speelt alle muziek door en lees je ook offline.',
    ProFeature.studies => 'Met Pro begin je elke dag zoveel lessen als je wilt.',
  };

  /// What stays free for an account with [limited] as its personal limit.
  static List<String> freeIncludes(ProFeature? limited, AccountLimits free) {
    return [
      'de Bijbel lezen in alle vertalingen',
      if (limited == ProFeature.studies)
        '${_plural(tinyLessonsDaily, 'nieuwe les', 'nieuwe lessen')} per dag in de begeleide studies'
      else
        'alle begeleide studies',
      'het KingComments-commentaar',
      if (limited != ProFeature.ai) '${free.aiDaily} AI-vragen per dag',
      if (limited != ProFeature.notes)
        '${free.notes ?? AccountLimits.free.notes} notities (markeren onbeperkt)'
      else
        'onbeperkt markeren',
      if (limited != ProFeature.study) '${free.crossRefs ?? AccountLimits.free.crossRefs} kruisverwijzingen per vers',
    ];
  }

  /// "a, b en c".
  static String list(List<String> items) {
    if (items.length <= 1) return items.join();
    return '${items.sublist(0, items.length - 1).join(', ')} en ${items.last}';
  }
}
