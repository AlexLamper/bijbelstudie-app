/// The server's record of a study you are doing: the settings you chose and how
/// far you got. Mirrors `serialiseEnrollment` in the website's
/// `lib/studyEnrollmentService.ts` field for field.
///
/// This is the source of truth for study progress across devices. The local
/// [StudyPlan] in `study_plan_store.dart` stays as the offline copy, but where
/// the two disagree the server wins.
library;

/// How often the reader intends to sit down with a study.
enum StudyRhythm {
  daily('dagelijks', 'Elke dag', 'Eén les per dag'),
  threePerWeek('drie-per-week', '3x per week', 'Maandag, woensdag, vrijdag'),
  weekly('wekelijks', 'Wekelijks', 'Eén les per week'),
  ownDays('eigen', 'Eigen dagen', 'Kies zelf welke dagen'),
  free('vrij', 'Geen ritme', 'Zonder herinneringen');

  const StudyRhythm(this.id, this.label, this.description);

  /// The wire value the API stores.
  final String id;
  final String label;
  final String description;

  static StudyRhythm fromId(String? id) {
    for (final rhythm in StudyRhythm.values) {
      if (rhythm.id == id) return rhythm;
    }
    return StudyRhythm.daily;
  }
}

/// How much explanation the reader wants alongside the passage.
enum StudyDepth {
  short('kort', 'Kort & praktisch', 'Toepassing op vandaag'),
  deep('diep', 'Diepgaand historisch', 'Achtergrond en uitleg');

  const StudyDepth(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;

  static StudyDepth fromId(String? id) {
    return id == 'diep' ? StudyDepth.deep : StudyDepth.short;
  }
}

/// Where the reader is inside a lesson. `done` is a cursor value only - it is
/// never one of the steps a lesson renders.
enum StudyStep {
  intro('intro', 'Intro'),
  word('word', 'Het Woord'),
  depth('depth', 'Verdieping'),
  reflection('reflection', 'Reflectie'),
  quiz('quiz', 'Toetsing'),
  done('done', 'Afgerond');

  const StudyStep(this.id, this.label);

  final String id;
  final String label;

  /// The steps a lesson can actually show, in order. `done` is excluded.
  static const List<StudyStep> renderable = [intro, word, depth, reflection, quiz];

  static StudyStep? tryFromId(String? id) {
    for (final step in StudyStep.values) {
      if (step.id == id) return step;
    }
    return null;
  }
}

class StudyEnrollment {
  const StudyEnrollment({
    required this.studyId,
    required this.status,
    required this.rhythm,
    required this.reminderDays,
    required this.depth,
    required this.currentLessonDay,
    required this.currentStep,
    required this.lessonsTotal,
    required this.lessonsCompleted,
    required this.remindersEnabled,
    this.translation,
    this.commentary,
    this.startedAt,
    this.lastActivityAt,
    this.completedAt,
    this.reminderMinutes,
    this.reminderTimezone,
  });

  final String studyId;

  /// `active` / `completed` / `paused` / `abandoned`.
  final String status;

  final StudyRhythm rhythm;

  /// Weekdays for [StudyRhythm.ownDays], `0` = Sunday. Empty for every other
  /// rhythm.
  final List<int> reminderDays;

  final StudyDepth depth;

  /// Null means "inherit the account preference", which is what the reader
  /// gets when they never picked a translation for this study.
  final String? translation;

  final String? commentary;

  final int currentLessonDay;
  final StudyStep currentStep;
  final int lessonsTotal;
  final int lessonsCompleted;

  final bool remindersEnabled;
  final int? reminderMinutes;
  final String? reminderTimezone;

  final DateTime? startedAt;
  final DateTime? lastActivityAt;
  final DateTime? completedAt;

  bool get isCompleted => completedAt != null || status == 'completed';
  bool get isActive => status == 'active';

  /// 0.0 - 1.0, safe when the server reports no lessons at all.
  double get progress {
    if (lessonsTotal <= 0) return 0;
    return (lessonsCompleted / lessonsTotal).clamp(0.0, 1.0);
  }

  int get progressPercent => (progress * 100).round();

  /// Where "ga verder" should land. A finished lesson cursor (`done`) has no
  /// step to resume into, so the caller opens the lesson at its first step.
  StudyStep? get resumeStep => currentStep == StudyStep.done ? null : currentStep;

  factory StudyEnrollment.fromJson(Map<String, dynamic> json) {
    return StudyEnrollment(
      studyId: json['studyId'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      rhythm: StudyRhythm.fromId(json['rhythm'] as String?),
      reminderDays: (json['reminderDays'] as List? ?? const [])
          .whereType<num>()
          .map((day) => day.toInt())
          .toList(growable: false),
      depth: StudyDepth.fromId(json['depth'] as String?),
      translation: json['translation'] as String?,
      commentary: json['commentary'] as String?,
      currentLessonDay: (json['currentLessonDay'] as num?)?.toInt() ?? 1,
      currentStep: StudyStep.tryFromId(json['currentStep'] as String?) ?? StudyStep.intro,
      lessonsTotal: (json['lessonsTotal'] as num?)?.toInt() ?? 0,
      lessonsCompleted: (json['lessonsCompleted'] as num?)?.toInt() ?? 0,
      remindersEnabled: json['remindersEnabled'] as bool? ?? true,
      reminderMinutes: (json['reminderMinutes'] as num?)?.toInt(),
      reminderTimezone: json['reminderTimezone'] as String?,
      startedAt: _date(json['startedAt']),
      lastActivityAt: _date(json['lastActivityAt']),
      completedAt: _date(json['completedAt']),
    );
  }
}

/// The settings half of an enrollment - what the start dialog collects, and the
/// exact body `POST /study-enrollments` expects.
class EnrollmentSettings {
  const EnrollmentSettings({
    required this.rhythm,
    required this.depth,
    required this.translation,
    this.reminderDays = const [1, 3, 5],
  });

  final StudyRhythm rhythm;
  final StudyDepth depth;
  final String translation;

  /// Only sent when [rhythm] is [StudyRhythm.ownDays]; the server ignores it
  /// otherwise, and the website sends an empty list rather than stale days.
  final List<int> reminderDays;

  EnrollmentSettings copyWith({
    StudyRhythm? rhythm,
    StudyDepth? depth,
    String? translation,
    List<int>? reminderDays,
  }) {
    return EnrollmentSettings(
      rhythm: rhythm ?? this.rhythm,
      depth: depth ?? this.depth,
      translation: translation ?? this.translation,
      reminderDays: reminderDays ?? this.reminderDays,
    );
  }

  Map<String, dynamic> toJson(String studyId) {
    return {
      'studyId': studyId,
      'rhythm': rhythm.id,
      'reminderDays': rhythm == StudyRhythm.ownDays ? reminderDays : const <int>[],
      'depth': depth.id,
      'translation': translation,
      // "Geen ritme" is the reader saying they do not want to be nudged.
      'remindersEnabled': rhythm != StudyRhythm.free,
      'reminderTimezone': DateTime.now().timeZoneName,
    };
  }
}

DateTime? _date(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
