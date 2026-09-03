import '../../studies/data/enrollment_models.dart';

/// Everything one lesson needs, exactly as `GET /studies/:id/lessons/:day`
/// sends it.
///
/// The server resolves the hard parts - which steps this lesson has, which
/// verses the passage covers, which commentary matches the reader's chosen
/// depth - so nothing here is recomputed on the device. In particular [steps]
/// is authoritative: `intro` is simply absent for a study with no authored
/// prose, which is most of them.
class LessonPayload {
  const LessonPayload({
    required this.studyId,
    required this.studyTitle,
    required this.lessonsTotal,
    required this.day,
    required this.title,
    required this.estimatedMinutes,
    required this.steps,
    required this.passage,
    required this.translation,
    required this.translations,
    required this.commentaryId,
    required this.content,
    required this.outline,
    this.nextLessonDay,
  });

  final String studyId;
  final String studyTitle;
  final int lessonsTotal;

  final int day;
  final String title;
  final int estimatedMinutes;

  /// The steps to render, in order. Never add to or reorder this list.
  final List<StudyStep> steps;

  final LessonPassage passage;

  /// The translation the enrollment settled on, used until the reader switches
  /// it for this lesson.
  final String translation;
  final List<LessonTranslation> translations;

  /// Which commentary the Verdieping step shows. Server-resolved from the
  /// enrollment, then the account preference, then the default.
  final String commentaryId;

  final LessonContent content;

  /// Every lesson in the study, for the lesson navigator.
  final List<LessonOutlineEntry> outline;

  final int? nextLessonDay;

  bool get isLastLesson => nextLessonDay == null;

  factory LessonPayload.fromJson(Map<String, dynamic> json) {
    final study = (json['study'] as Map<String, dynamic>?) ?? const {};
    final lesson = (json['lesson'] as Map<String, dynamic>?) ?? const {};

    return LessonPayload(
      studyId: study['id'] as String? ?? '',
      studyTitle: study['title'] as String? ?? '',
      lessonsTotal: (study['lessonsTotal'] as num?)?.toInt() ?? 0,
      day: (lesson['day'] as num?)?.toInt() ?? 1,
      title: lesson['title'] as String? ?? '',
      estimatedMinutes: (lesson['estimatedMinutes'] as num?)?.toInt() ?? 12,
      steps: (json['steps'] as List? ?? const [])
          .whereType<String>()
          .map(StudyStep.tryFromId)
          .whereType<StudyStep>()
          .where((step) => step != StudyStep.done)
          .toList(growable: false),
      passage: LessonPassage.fromJson(
        (json['passage'] as Map<String, dynamic>?) ?? const {},
      ),
      translation: json['translation'] as String? ?? 'statenvertaling',
      translations: (json['translations'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LessonTranslation.fromJson)
          .toList(growable: false),
      commentaryId: json['commentaryId'] as String? ?? 'matthew_henry_nl',
      content: LessonContent.fromJson(
        (json['content'] as Map<String, dynamic>?) ?? const {},
      ),
      outline: (json['outline'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LessonOutlineEntry.fromJson)
          .toList(growable: false),
      nextLessonDay: (json['nextLessonDay'] as num?)?.toInt(),
    );
  }
}

class LessonPassage {
  const LessonPassage({
    required this.book,
    required this.chapter,
    required this.verseStart,
    required this.verseEnd,
    this.verseRange,
  });

  final String book;
  final int chapter;
  final int verseStart;
  final int verseEnd;
  final String? verseRange;

  /// `Markus 4:1-20`, or `Markus 4` when the lesson covers the whole chapter.
  String get reference {
    final range = verseRange;
    if (range == null || range.isEmpty) return '$book $chapter';
    return '$book $chapter:$range';
  }

  /// Whether [verse] falls inside this lesson's slice of the chapter.
  bool includes(int verse) => verse >= verseStart && verse <= verseEnd;

  factory LessonPassage.fromJson(Map<String, dynamic> json) {
    return LessonPassage(
      book: json['book'] as String? ?? 'Genesis',
      chapter: (json['chapter'] as num?)?.toInt() ?? 1,
      verseStart: (json['verseStart'] as num?)?.toInt() ?? 1,
      verseEnd: (json['verseEnd'] as num?)?.toInt() ?? 999,
      verseRange: json['verseRange'] as String?,
    );
  }
}

class LessonTranslation {
  const LessonTranslation({required this.id, required this.name, this.language});

  final String id;
  final String name;
  final String? language;

  bool get isDutch => language == 'nl';

  factory LessonTranslation.fromJson(Map<String, dynamic> json) {
    return LessonTranslation(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      language: json['language'] as String?,
    );
  }
}

/// The authored prose for a lesson. Every part is optional - a generated book
/// study has none of it, and the steps degrade rather than break.
class LessonContent {
  const LessonContent({
    this.intro,
    this.readingCue,
    this.depth,
    required this.reflection,
    required this.quiz,
  });

  final LessonIntro? intro;

  /// One line telling the reader what to watch for while reading.
  final String? readingCue;

  final LessonDepth? depth;
  final LessonReflection reflection;
  final LessonQuizConfig quiz;

  factory LessonContent.fromJson(Map<String, dynamic> json) {
    final intro = json['intro'];
    final depth = json['depth'];
    return LessonContent(
      // `intro` and `depth` are hand-authored prose blocks - a shape mistake
      // in one lesson's `watchFor` or `terms` must not blank the whole
      // lesson, so a bad block is dropped rather than left to throw out of
      // this constructor. The step list still comes from the server's own
      // `steps` array, so dropping `intro` here simply loses that one step,
      // exactly as it would for a study with no authored intro at all.
      intro: intro is Map<String, dynamic> ? _tryParse(LessonIntro.fromJson, intro) : null,
      readingCue: _safeString(json['readingCue']),
      depth: depth is Map<String, dynamic> ? _tryParse(LessonDepth.fromJson, depth) : null,
      reflection: LessonReflection.fromJson(
        (json['reflection'] as Map<String, dynamic>?) ?? const {},
      ),
      quiz: LessonQuizConfig.fromJson(
        (json['quiz'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}

/// Runs a sub-block parser, swallowing a shape mismatch rather than letting it
/// take the whole [LessonPayload] parse down. Used only for optional,
/// hand-authored blocks - never for server-computed fields, where a mismatch
/// is a real bug that should surface as an error.
T? _tryParse<T>(T Function(Map<String, dynamic>) parse, Map<String, dynamic> json) {
  try {
    return parse(json);
  } catch (_) {
    return null;
  }
}

/// A `String?` cast that tolerates the field being the wrong JSON type
/// instead of throwing - authored content is hand-edited and occasionally
/// gets the shape wrong.
String? _safeString(Object? value) => value is String ? value : null;

/// A `List<String>` cast that never throws: anything that isn't a list of
/// strings degrades to an empty list.
List<String> _safeStringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

class LessonIntro {
  const LessonIntro({required this.headline, required this.body, this.watchFor = const []});

  final String headline;
  final List<String> body;

  /// The "Let hier op" aside - one or more short pointers to watch for while
  /// reading. The API sends this as a string array (`watchFor?: string[]`
  /// in `lib/data/study-lessons/types.ts`), never a single string.
  final List<String> watchFor;

  factory LessonIntro.fromJson(Map<String, dynamic> json) {
    return LessonIntro(
      headline: _safeString(json['headline']) ?? '',
      body: _safeStringList(json['body']),
      watchFor: _safeStringList(json['watchFor']),
    );
  }
}

class LessonDepth {
  const LessonDepth({this.body = const [], this.terms = const [], this.showMedia = true});

  final List<String> body;
  final List<LessonTerm> terms;

  /// False when this passage names no place, so the Beeld panel is hidden
  /// instead of showing an empty strip.
  final bool showMedia;

  factory LessonDepth.fromJson(Map<String, dynamic> json) {
    return LessonDepth(
      body: (json['body'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      terms: (json['terms'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LessonTerm.fromJson)
          .toList(growable: false),
      showMedia: json['showMedia'] as bool? ?? true,
    );
  }
}

class LessonTerm {
  const LessonTerm({required this.term, required this.meaning});

  final String term;
  final String meaning;

  factory LessonTerm.fromJson(Map<String, dynamic> json) {
    return LessonTerm(
      term: json['term'] as String? ?? '',
      meaning: json['meaning'] as String? ?? '',
    );
  }
}

class LessonReflection {
  const LessonReflection({
    required this.question,
    this.prompts = const [],
    this.placeholder,
  });

  /// Falls back server-side to the lesson's `focus`, so this is never empty for
  /// a lesson that has a reflection step.
  final String question;
  final List<String> prompts;
  final String? placeholder;

  factory LessonReflection.fromJson(Map<String, dynamic> json) {
    return LessonReflection(
      question: json['question'] as String? ?? '',
      prompts: (json['prompts'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      placeholder: json['placeholder'] as String?,
    );
  }
}

class LessonQuizConfig {
  const LessonQuizConfig({this.enabled = true, this.questionCount = 5});

  final bool enabled;
  final int questionCount;

  factory LessonQuizConfig.fromJson(Map<String, dynamic> json) {
    return LessonQuizConfig(
      enabled: json['enabled'] as bool? ?? true,
      questionCount: (json['questionCount'] as num?)?.toInt() ?? 5,
    );
  }
}

class LessonOutlineEntry {
  const LessonOutlineEntry({
    required this.day,
    required this.title,
    required this.reference,
    required this.completed,
  });

  final int day;
  final String title;
  final String reference;
  final bool completed;

  factory LessonOutlineEntry.fromJson(Map<String, dynamic> json) {
    return LessonOutlineEntry(
      day: (json['day'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      reference: json['reference'] as String? ?? '',
      completed: json['completed'] as bool? ?? false,
    );
  }
}

/// The saved cursor inside a lesson: which steps are done, where the reader
/// was, what they wrote, and what they answered.
class LessonState {
  const LessonState({
    this.stepsCompleted = const [],
    this.currentStep,
    this.viewTranslation,
    this.depthPanel,
    this.reflectionText = '',
    this.reflectionUpdatedAt,
    this.reflectionNoteId,
    this.quizScore,
    this.quizTotal,
    this.quizAttempts = 0,
    this.completedAt,
  });

  final List<StudyStep> stepsCompleted;
  final StudyStep? currentStep;

  /// The translation the reader switched to while reading this lesson. A view
  /// preference only - it deliberately does not change the enrollment.
  final String? viewTranslation;

  /// Which Verdieping panel was open: `media`, `original` or `notes`.
  final String? depthPanel;

  final String reflectionText;
  final DateTime? reflectionUpdatedAt;
  final String? reflectionNoteId;

  final int? quizScore;
  final int? quizTotal;
  final int quizAttempts;

  final DateTime? completedAt;

  bool get isCompleted => completedAt != null;

  factory LessonState.fromJson(Map<String, dynamic> json) {
    final reflection = (json['reflection'] as Map<String, dynamic>?) ?? const {};
    final quiz = (json['quiz'] as Map<String, dynamic>?) ?? const {};

    return LessonState(
      stepsCompleted: (json['stepsCompleted'] as List? ?? const [])
          .whereType<String>()
          .map(StudyStep.tryFromId)
          .whereType<StudyStep>()
          .toList(growable: false),
      currentStep: StudyStep.tryFromId(json['currentStep'] as String?),
      viewTranslation: json['viewTranslation'] as String?,
      depthPanel: json['depthPanel'] as String?,
      reflectionText: reflection['text'] as String? ?? '',
      reflectionUpdatedAt: _date(reflection['updatedAt']),
      reflectionNoteId: reflection['noteId'] as String?,
      quizScore: (quiz['score'] as num?)?.toInt(),
      quizTotal: (quiz['total'] as num?)?.toInt(),
      quizAttempts: (quiz['attempts'] as num?)?.toInt() ?? 0,
      completedAt: _date(json['completedAt']),
    );
  }
}

/// What finishing a lesson earned, returned by the completing PATCH.
class CompletionSummary {
  const CompletionSummary({
    required this.recorded,
    required this.studyCompleted,
    this.reason,
    this.xpAwarded = 0,
    this.levelledUp = false,
    this.newBadges = const [],
    this.noteId,
    this.nextLessonDay,
  });

  /// False when this lesson was already in the ledger, in which case no XP was
  /// granted a second time.
  final bool recorded;
  final String? reason;

  final bool studyCompleted;
  final int xpAwarded;
  final bool levelledUp;
  final List<String> newBadges;

  /// Set when the reflection was promoted into a real note.
  final String? noteId;

  final int? nextLessonDay;

  factory CompletionSummary.fromJson(Map<String, dynamic> json) {
    final xp = json['xp'];
    return CompletionSummary(
      recorded: json['recorded'] as bool? ?? false,
      reason: json['reason'] as String?,
      studyCompleted: json['studyCompleted'] as bool? ?? false,
      xpAwarded: xp is Map<String, dynamic>
          ? (xp['awarded'] as num?)?.toInt() ?? (xp['amount'] as num?)?.toInt() ?? 0
          : (xp as num?)?.toInt() ?? 0,
      levelledUp: xp is Map<String, dynamic> ? xp['levelledUp'] as bool? ?? false : false,
      newBadges: xp is Map<String, dynamic>
          ? (xp['badges'] as List? ?? const []).whereType<String>().toList(growable: false)
          : const [],
      noteId: json['noteId'] as String?,
      nextLessonDay: (json['nextLessonDay'] as num?)?.toInt(),
    );
  }
}

/// One quiz question as `GET /study-quiz` serves it.
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.text,
    required this.answers,
    this.bibleReference,
  });

  final String id;
  final String text;
  final List<QuizAnswer> answers;
  final String? bibleReference;

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      answers: (json['answers'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(QuizAnswer.fromJson)
          .toList(growable: false),
      bibleReference: json['bibleReference'] as String?,
    );
  }
}

class QuizAnswer {
  const QuizAnswer({required this.id, required this.text});

  final String id;
  final String text;

  factory QuizAnswer.fromJson(Map<String, dynamic> json) {
    return QuizAnswer(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
    );
  }
}

/// Why there is no quiz for this lesson. Each reason reads differently to the
/// reader: a disabled quiz is a decision, an unavailable one is a hiccup.
enum QuizUnavailableReason {
  disabled('DISABLED'),
  notConfigured('NOT_CONFIGURED'),
  unavailable('UNAVAILABLE'),
  noQuestions('NO_QUESTIONS');

  const QuizUnavailableReason(this.code);

  final String code;

  static QuizUnavailableReason fromCode(String? code) {
    for (final reason in QuizUnavailableReason.values) {
      if (reason.code == code) return reason;
    }
    return QuizUnavailableReason.noQuestions;
  }

  String get message => switch (this) {
    QuizUnavailableReason.unavailable =>
      'De quizvragen zijn nu even niet op te halen. Je kunt de les gewoon afronden.',
    _ =>
      'Voor dit bijbelgedeelte zijn nog geen vragen beschikbaar. Rond de les af om verder te gaan.',
  };
}

class LessonQuiz {
  const LessonQuiz({
    required this.available,
    this.reason,
    this.questions = const [],
    this.savedAnswers = const {},
    this.savedScore,
    this.savedTotal,
  });

  final bool available;
  final QuizUnavailableReason? reason;
  final List<QuizQuestion> questions;

  /// Question id to the answer id already picked, so reopening the step shows
  /// the reader's own answers rather than a blank quiz.
  final Map<String, String> savedAnswers;

  final int? savedScore;
  final int? savedTotal;

  bool get isGraded => savedScore != null && savedTotal != null;

  factory LessonQuiz.fromJson(Map<String, dynamic> json) {
    final available = json['available'] as bool? ?? false;
    return LessonQuiz(
      available: available,
      reason: available ? null : QuizUnavailableReason.fromCode(json['reason'] as String?),
      questions: (json['questions'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(QuizQuestion.fromJson)
          .toList(growable: false),
      savedAnswers: {
        for (final entry in (json['savedAnswers'] as List? ?? const [])
            .whereType<Map<String, dynamic>>())
          if (entry['id'] is String && entry['answerId'] is String)
            entry['id'] as String: entry['answerId'] as String,
      },
      savedScore: (json['savedScore'] as num?)?.toInt(),
      savedTotal: (json['savedTotal'] as num?)?.toInt(),
    );
  }
}

/// How well the reader did, in the words the website uses.
String quizScoreLabel(int score, int total) {
  if (total <= 0) return 'Geen vragen';
  final ratio = score / total;
  if (ratio >= 1) return 'Alles goed';
  if (ratio >= 0.8) return 'Sterk gedaan';
  if (ratio >= 0.6) return 'Goed bezig';
  if (ratio >= 0.4) return 'Op de helft';
  return 'Nog even teruglezen';
}

/// `45 min`, or `1,5 uur` once a study runs long. Mirrors the website's
/// `formatStudyMinutes` so the same study never quotes two different lengths.
String formatStudyMinutes(int minutes) {
  if (minutes < 90) return '$minutes min';
  final halves = (minutes / 30).round() / 2;
  final text = halves == halves.roundToDouble()
      ? halves.round().toString()
      : halves.toStringAsFixed(1).replaceAll('.', ',');
  return '$text uur';
}

DateTime? _date(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
