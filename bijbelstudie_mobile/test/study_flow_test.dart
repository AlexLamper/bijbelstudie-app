import 'package:bijbelstudie_mobile/features/studies/data/enrollment_models.dart';
import 'package:bijbelstudie_mobile/features/studies/data/study_models.dart';
import 'package:bijbelstudie_mobile/features/study/domain/lesson_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The guided study flow is almost all server-resolved, so what matters on the
/// device is that the payloads are read exactly as sent and the enrollment body
/// is written exactly as expected. Both are contracts with the backend, and a
/// silent drift in either shows up as a lesson that will not open or progress
/// that never saves.
void main() {
  group('lesson payload', () {
    Map<String, dynamic> payload({
      Map<String, dynamic>? intro,
      List<String> steps = const ['intro', 'word', 'depth', 'reflection', 'quiz'],
    }) {
      return {
        'study': {'id': 'opstanding', 'title': 'De opstanding', 'lessonsTotal': 4},
        'lesson': {'day': 2, 'title': 'Het lege graf', 'estimatedMinutes': 15},
        'steps': steps,
        'passage': {
          'book': 'Johannes',
          'chapter': 20,
          'verseRange': '1-18',
          'verseStart': 1,
          'verseEnd': 18,
        },
        'translation': 'nbg51',
        'translations': [
          {'id': 'nbg51', 'name': 'NBG 1951', 'language': 'nl'},
          {'id': 'kjv', 'name': 'King James', 'language': 'en'},
        ],
        'commentaryId': 'dachsel',
        'content': {
          'intro': intro,
          'readingCue': 'Let op wie er als eerste gelooft.',
          'depth': {'showMedia': false},
          'reflection': {'question': 'Wat raakt je hier?', 'prompts': ['Waarom?']},
          'quiz': {'enabled': true, 'questionCount': 5},
        },
        'outline': [
          {'day': 1, 'title': 'Les 1', 'reference': 'Johannes 19', 'completed': true},
          {'day': 2, 'title': 'Het lege graf', 'reference': 'Johannes 20:1-18', 'completed': false},
        ],
        'nextLessonDay': 3,
      };
    }

    test('reads the steps the server sent, in order', () {
      final lesson = LessonPayload.fromJson(payload(intro: {'headline': 'Hoi', 'body': []}));

      expect(lesson.steps, [
        StudyStep.intro,
        StudyStep.word,
        StudyStep.depth,
        StudyStep.reflection,
        StudyStep.quiz,
      ]);
    });

    test('drops intro when the study has no authored prose for the lesson', () {
      // This is the common case: sixty-six generated book studies have no
      // intro, and the server leaves the step out rather than sending an empty
      // one. The flow must open on Het Woord, not on a blank screen.
      final lesson = LessonPayload.fromJson(
        payload(steps: const ['word', 'depth', 'reflection', 'quiz']),
      );

      expect(lesson.steps.contains(StudyStep.intro), isFalse);
      expect(lesson.steps.first, StudyStep.word);
      expect(lesson.content.intro, isNull);
    });

    test('never invents a step the server did not send', () {
      final lesson = LessonPayload.fromJson(payload(steps: const ['word', 'reflection']));

      expect(lesson.steps, [StudyStep.word, StudyStep.reflection]);
    });

    test('ignores the "done" cursor value if it appears among the steps', () {
      // `done` is an enrollment cursor, never something a lesson renders.
      final lesson = LessonPayload.fromJson(payload(steps: const ['word', 'done']));

      expect(lesson.steps, [StudyStep.word]);
    });

    test('keeps the passage slice and the reference it reads as', () {
      final lesson = LessonPayload.fromJson(payload());

      expect(lesson.passage.reference, 'Johannes 20:1-18');
      expect(lesson.passage.includes(1), isTrue);
      expect(lesson.passage.includes(18), isTrue);
      expect(lesson.passage.includes(19), isFalse);
    });

    test('a whole-chapter lesson reads without a verse range', () {
      final json = payload();
      (json['passage'] as Map<String, dynamic>).remove('verseRange');

      expect(LessonPayload.fromJson(json).passage.reference, 'Johannes 20');
    });

    test('carries the server-resolved commentary rather than a default', () {
      expect(LessonPayload.fromJson(payload()).commentaryId, 'dachsel');
    });

    test('hides the media panel when the passage names no place', () {
      expect(LessonPayload.fromJson(payload()).content.depth?.showMedia, isFalse);
    });
  });

  group('lesson state', () {
    test('reads the saved cursor, reflection and quiz score', () {
      final state = LessonState.fromJson({
        'stepsCompleted': ['intro', 'word'],
        'currentStep': 'depth',
        'viewTranslation': 'kjv',
        'depthPanel': 'original',
        'reflection': {
          'text': 'Mijn antwoord',
          'updatedAt': '2026-08-30T10:00:00.000Z',
          'noteId': 'note-1',
        },
        'quiz': {'score': 4, 'total': 5, 'attempts': 1},
        'completedAt': null,
      });

      expect(state.stepsCompleted, [StudyStep.intro, StudyStep.word]);
      expect(state.currentStep, StudyStep.depth);
      expect(state.viewTranslation, 'kjv');
      expect(state.depthPanel, 'original');
      expect(state.reflectionText, 'Mijn antwoord');
      expect(state.reflectionNoteId, 'note-1');
      expect(state.quizScore, 4);
      expect(state.isCompleted, isFalse);
    });

    test('a lesson never opened comes back empty rather than broken', () {
      final state = LessonState.fromJson(const {});

      expect(state.stepsCompleted, isEmpty);
      expect(state.currentStep, isNull);
      expect(state.reflectionText, '');
      expect(state.isCompleted, isFalse);
    });
  });

  group('completion', () {
    test('reads what finishing the lesson earned', () {
      final summary = CompletionSummary.fromJson(const {
        'recorded': true,
        'studyCompleted': false,
        'xp': {'awarded': 25, 'levelledUp': true, 'badges': ['volhouder']},
        'noteId': 'note-9',
        'nextLessonDay': 3,
      });

      expect(summary.recorded, isTrue);
      expect(summary.xpAwarded, 25);
      expect(summary.levelledUp, isTrue);
      expect(summary.newBadges, ['volhouder']);
      expect(summary.noteId, 'note-9');
      expect(summary.nextLessonDay, 3);
    });

    test('redoing a lesson is recorded as already done and pays no XP again', () {
      final summary = CompletionSummary.fromJson(const {
        'recorded': false,
        'reason': 'ALREADY_RECORDED',
        'studyCompleted': false,
        'xp': null,
      });

      expect(summary.recorded, isFalse);
      expect(summary.reason, 'ALREADY_RECORDED');
      expect(summary.xpAwarded, 0);
    });
  });

  group('quiz', () {
    test('reads questions and the answers already picked', () {
      final quiz = LessonQuiz.fromJson(const {
        'available': true,
        'savedAnswers': [
          {'id': 'q1', 'answerId': 'a2'},
        ],
        'savedScore': null,
        'savedTotal': null,
        'questions': [
          {
            'id': 'q1',
            'text': 'Wie kwam als eerste bij het graf?',
            'bibleReference': 'Johannes 20:1',
            'answers': [
              {'id': 'a1', 'text': 'Petrus'},
              {'id': 'a2', 'text': 'Maria Magdalena'},
            ],
          },
        ],
      });

      expect(quiz.available, isTrue);
      expect(quiz.questions.single.answers.length, 2);
      expect(quiz.savedAnswers['q1'], 'a2');
      expect(quiz.isGraded, isFalse);
    });

    test('each unavailable reason has its own wording', () {
      for (final code in ['DISABLED', 'NOT_CONFIGURED', 'UNAVAILABLE', 'NO_QUESTIONS']) {
        final quiz = LessonQuiz.fromJson({'available': false, 'reason': code});
        expect(quiz.available, isFalse);
        expect(quiz.reason, isNotNull);
        expect(quiz.reason!.message, isNotEmpty);
      }

      // A hiccup upstream reads differently from a passage nobody has written
      // questions for - one is temporary, the other is not.
      expect(
        QuizUnavailableReason.unavailable.message,
        isNot(QuizUnavailableReason.noQuestions.message),
      );
    });

    test('an unknown reason still yields a usable empty state', () {
      final quiz = LessonQuiz.fromJson(const {'available': false, 'reason': 'SOMETHING_NEW'});

      expect(quiz.reason, QuizUnavailableReason.noQuestions);
    });

    test('score labels run from all-correct down to none', () {
      expect(quizScoreLabel(5, 5), 'Alles goed');
      expect(quizScoreLabel(4, 5), 'Sterk gedaan');
      expect(quizScoreLabel(3, 5), 'Goed bezig');
      expect(quizScoreLabel(2, 5), 'Op de helft');
      expect(quizScoreLabel(0, 5), 'Nog even teruglezen');
      expect(quizScoreLabel(0, 0), 'Geen vragen');
    });
  });

  group('enrollment settings body', () {
    test('sends the rhythm, depth and translation the reader chose', () {
      final body = const EnrollmentSettings(
        rhythm: StudyRhythm.weekly,
        depth: StudyDepth.deep,
        translation: 'nbg51',
      ).toJson('boek-markus');

      expect(body['studyId'], 'boek-markus');
      expect(body['rhythm'], 'wekelijks');
      expect(body['depth'], 'diep');
      expect(body['translation'], 'nbg51');
      expect(body['remindersEnabled'], isTrue);
    });

    test('only "eigen dagen" sends weekdays', () {
      final own = const EnrollmentSettings(
        rhythm: StudyRhythm.ownDays,
        depth: StudyDepth.short,
        translation: 'statenvertaling',
        reminderDays: [1, 4],
      ).toJson('daniel');
      expect(own['reminderDays'], [1, 4]);

      // Any other rhythm sends an empty list rather than stale days.
      final daily = const EnrollmentSettings(
        rhythm: StudyRhythm.daily,
        depth: StudyDepth.short,
        translation: 'statenvertaling',
        reminderDays: [1, 4],
      ).toJson('daniel');
      expect(daily['reminderDays'], isEmpty);
    });

    test('"geen ritme" turns reminders off', () {
      final body = const EnrollmentSettings(
        rhythm: StudyRhythm.free,
        depth: StudyDepth.short,
        translation: 'statenvertaling',
      ).toJson('daniel');

      expect(body['remindersEnabled'], isFalse);
    });
  });

  group('enrollment', () {
    StudyEnrollment enrollment(Map<String, dynamic> overrides) {
      return StudyEnrollment.fromJson({
        'studyId': 'boek-markus',
        'status': 'active',
        'rhythm': 'dagelijks',
        'reminderDays': <int>[],
        'depth': 'kort',
        'currentLessonDay': 3,
        'currentStep': 'depth',
        'lessonsTotal': 16,
        'lessonsCompleted': 2,
        'remindersEnabled': true,
        ...overrides,
      });
    }

    test('reports progress without dividing by zero', () {
      expect(enrollment({'lessonsTotal': 0}).progress, 0);
      expect(enrollment({}).progressPercent, 13);
    });

    test('resumes on the step the reader left off on', () {
      expect(enrollment({}).resumeStep, StudyStep.depth);
    });

    test('a finished lesson cursor has no step to resume into', () {
      // `done` means the lesson was completed, so the next open starts at the
      // beginning of the next lesson rather than at a step.
      expect(enrollment({'currentStep': 'done'}).resumeStep, isNull);
    });

    test('a completed study is completed whichever field says so', () {
      expect(enrollment({'status': 'completed'}).isCompleted, isTrue);
      expect(
        enrollment({'completedAt': '2026-08-01T00:00:00.000Z'}).isCompleted,
        isTrue,
      );
      expect(enrollment({}).isCompleted, isFalse);
    });
  });

  group('catalogue study', () {
    test('reads the grouping metadata the catalog endpoint adds', () {
      final study = CuratedStudy.fromJson(const {
        'id': 'boek-markus',
        'type': 'Boek',
        'title': 'Markus',
        'description': 'Wie is Jezus?',
        'durationLabel': '16 lessen',
        'startBook': 'Markus',
        'startChapter': 1,
        'startVersion': 'statenvertaling',
        'image': '',
        'category': 'nt',
        'kind': 'Evangelie',
        'avgMinutes': 10,
        'about': ['Eerste alinea', 'Tweede alinea'],
        'suggestedRhythm': 'dagelijks',
        'suggestedDepth': 'kort',
        'lessons': [
          {'day': 1, 'title': 'Hoofdstuk 1', 'book': 'Markus', 'chapter': 1, 'focus': 'x'},
        ],
      });

      expect(study.category, 'nt');
      expect(study.kind, 'Evangelie');
      expect(study.minutesPerLesson, 10);
      expect(study.about, ['Eerste alinea', 'Tweede alinea']);
      expect(StudyRhythm.fromId(study.suggestedRhythm), StudyRhythm.daily);
    });

    test('still parses the older /studies response that lacks the metadata', () {
      // A server that predates the catalog route sends none of these, and the
      // app falls back to that endpoint - so this must not throw.
      final study = CuratedStudy.fromJson(const {
        'id': 'opstanding',
        'type': 'Gedeelte',
        'title': 'De opstanding',
        'description': 'Het lege graf',
        'durationLabel': '4 lessen',
        'startBook': 'Johannes',
        'startChapter': 20,
        'startVersion': 'statenvertaling',
        'image': '',
        'lessons': <Map<String, dynamic>>[],
      });

      expect(study.category, isNull);
      expect(study.kind, isNull);
      expect(study.about, isEmpty);
      // Falls back to the flat ten-minute assumption.
      expect(study.minutesPerLesson, 10);
    });
  });

  group('study length', () {
    test('reads as minutes until it runs long, then as hours', () {
      expect(formatStudyMinutes(45), '45 min');
      expect(formatStudyMinutes(89), '89 min');
      expect(formatStudyMinutes(90), '1,5 uur');
      expect(formatStudyMinutes(120), '2 uur');
      expect(formatStudyMinutes(160), '2,5 uur');
    });
  });
}
