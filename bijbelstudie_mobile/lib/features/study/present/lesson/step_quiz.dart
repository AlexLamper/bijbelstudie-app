import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../feedback/data/review_prompt.dart';
import '../../data/lesson_repository.dart';
import '../../domain/lesson_models.dart';
import 'lesson_providers.dart';

/// Step 5 - five questions from BijbelQuiz on this passage.
///
/// One card at a time, advancing itself after a pick: a list of five questions
/// invites skimming, and the point is to check whether the passage landed.
///
/// The lesson can always be finished, quiz or no quiz. A missing quiz is
/// usually a passage nobody has written questions for yet, which is not the
/// reader's problem.
class LessonQuizStep extends ConsumerStatefulWidget {
  const LessonQuizStep({
    super.key,
    required this.lesson,
    required this.lessonRef,
    this.answers = const {},
    this.onAnswersChanged,
    this.onSkip,
  });

  final LessonPayload lesson;
  final LessonRef lessonRef;

  /// Picks already made in this session, kept by the shell so they outlive
  /// this step being rebuilt. Laid over the server's saved picks, which may
  /// not have caught up with the last tap yet.
  final Map<String, String> answers;

  /// Every pick, with the full set so far.
  final ValueChanged<Map<String, String>>? onAnswersChanged;

  /// Moves on past Toetsing without finishing it - the same walk as Volgende.
  /// Null hides the link.
  final VoidCallback? onSkip;

  @override
  ConsumerState<LessonQuizStep> createState() => _LessonQuizStepState();
}

class _LessonQuizStepState extends ConsumerState<LessonQuizStep> {
  static const _advanceDelay = Duration(milliseconds: 340);

  final Map<String, String> _answers = {};
  int _index = 0;
  bool _grading = false;
  QuizResult? _result;
  bool _seeded = false;

  /// Reopening the step should show what the reader already answered, not a
  /// blank quiz - the server keeps every pick, and the shell keeps the ones
  /// made since the quiz was fetched.
  void _seed(LessonQuiz quiz) {
    if (_seeded) return;
    _seeded = true;
    _answers
      ..addAll(quiz.savedAnswers)
      ..addAll(widget.answers);
    if (quiz.isGraded) {
      _result = QuizResult(score: quiz.savedScore!, total: quiz.savedTotal!);
      _index = quiz.questions.length;
      return;
    }
    // Resume on the first question with no answer yet.
    for (var i = 0; i < quiz.questions.length; i++) {
      if (!_answers.containsKey(quiz.questions[i].id)) {
        _index = i;
        return;
      }
    }
    _index = quiz.questions.length;
  }

  Future<void> _pick(
    LessonQuiz quiz,
    QuizQuestion question,
    String answerId,
  ) async {
    setState(() => _answers[question.id] = answerId);
    widget.onAnswersChanged?.call(Map.of(_answers));

    final repository = ref.read(lessonRepositoryProvider);
    final lessonRef = widget.lessonRef;

    // Save on every tap so a half-finished quiz survives leaving the lesson.
    // The full set, not just this pick: an older server replaces the saved
    // answers with whatever the request carries.
    unawaited(
      repository
          .saveQuizAnswers(lessonRef.studyId, lessonRef.day, Map.of(_answers))
          .then((_) {}, onError: (_, _) {}),
    );

    await Future<void>.delayed(_advanceDelay);
    if (!mounted) return;

    final isLast = _index >= quiz.questions.length - 1;
    if (!isLast) {
      setState(() => _index += 1);
      return;
    }

    setState(() => _grading = true);
    try {
      final result = await repository.gradeQuiz(
        lessonRef.studyId,
        lessonRef.day,
        _answers,
      );
      if (!mounted) return;
      setState(() {
        _grading = false;
        _result = result;
        _index = quiz.questions.length;
      });

      // A passed quiz is a success moment worth counting towards the rating
      // gate - the reader read the passage and it stuck. Recorded only; the
      // native review sheet is fired much later, by `ReviewPromptHost`, on a
      // calm screen. A poor score sends them back to re-read, which is the
      // opposite of a moment to ask about.
      if (result.total > 0 &&
          result.score / result.total >= ReviewPromptThresholds.quizPassRatio) {
        unawaited(
          ref
              .read(reviewPromptProvider.notifier)
              .recordSuccess(ReviewSignal.quizPassed),
        );
      }
    } on LessonException catch (e) {
      if (!mounted) return;
      setState(() => _grading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final quizAsync = ref.watch(lessonQuizProvider(widget.lessonRef));

    return quizAsync.when(
      loading: () => const Center(child: AppLoader()),
      error: (_, _) => _unavailable(QuizUnavailableReason.unavailable),
      data: (quiz) {
        if (!quiz.available || quiz.questions.isEmpty) {
          return _unavailable(quiz.reason ?? QuizUnavailableReason.noQuestions);
        }

        _seed(quiz);

        final result = _result;
        if (result != null) return _scoreCard(quiz, result);
        if (_grading) return const Center(child: AppLoader());

        final question =
            quiz.questions[_index.clamp(0, quiz.questions.length - 1)];
        return _questionCard(quiz, question);
      },
    );
  }

  Widget _unavailable(QuizUnavailableReason reason) {
    return AppEmptyState(
      icon: Icons.quiz_outlined,
      title: 'Geen quiz voor dit gedeelte',
      description: reason.message,
    );
  }

  Widget _questionCard(LessonQuiz quiz, QuizQuestion question) {
    final picked = _answers[question.id];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Row(
          children: [
            const Expanded(child: Eyebrow('Toetsing')),
            Text(
              'vraag ${_index + 1} van ${quiz.questions.length}',
              style: AppTheme.metaLabel,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SiteProgressBar(value: (_index + 1) / quiz.questions.length, height: 4),
        const SizedBox(height: 18),
        Text(question.text, style: AppTheme.displaySmall),
        if (question.bibleReference != null) ...[
          const SizedBox(height: 6),
          Text(
            question.bibleReference!,
            style: AppTheme.caption.copyWith(color: AppTheme.teal),
          ),
        ],
        const SizedBox(height: 18),
        for (final answer in question.answers)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AnswerRow(
              label: answer.text,
              selected: picked == answer.id,
              onTap: picked != null
                  ? null
                  : () => _pick(quiz, question, answer.id),
            ),
          ),
        // Quiet on purpose: not knowing an answer after one reading is normal,
        // and the reader should know they can move on without feeling pushed.
        if (widget.onSkip != null) ...[
          const SizedBox(height: 14),
          Center(
            child: InkWell(
              onTap: widget.onSkip,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text.rich(
                  TextSpan(
                    text: 'Niet verplicht · ',
                    children: [
                      TextSpan(
                        text: 'Toetsing overslaan',
                        style: TextStyle(
                          decoration: TextDecoration.underline,
                          decorationColor: AppTheme.inkFaint,
                        ),
                      ),
                    ],
                  ),
                  style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The score, then the questions one by one.
  ///
  /// A bare score teaches nothing: the reader who got two wrong wants to know
  /// which two and what the answer was. Where the grader recognised the
  /// question this shows right or wrong, the reader's own pick, the correct
  /// answer when they missed it, and the grader's explanation if it sent one.
  /// Nothing is written here that the grader did not say - an invented
  /// explanation of Scripture is worse than no explanation.
  Widget _scoreCard(LessonQuiz quiz, QuizResult result) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const Eyebrow('Toetsing'),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            children: [
              Text.rich(
                TextSpan(
                  text: '${result.score}/${result.total}',
                  style: AppTheme.displayLarge.copyWith(color: AppTheme.teal),
                  children: [
                    TextSpan(
                      text: result.total == 1 ? ' vraag goed' : ' vragen goed',
                      style: AppTheme.displaySmall.copyWith(
                        color: AppTheme.teal,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                quizScoreLabel(result.score, result.total),
                style: AppTheme.bodyStrong,
              ),
              const SizedBox(height: 10),
              SiteProgressBar(
                value: result.total == 0 ? 0 : result.score / result.total,
              ),
            ],
          ),
        ),

        if (quiz.questions.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionHeader(eyebrow: 'Nakijken', title: 'Jouw antwoorden'),
          const SizedBox(height: 4),
          Text(
            'Tik op een vraag voor je antwoord en de uitleg.',
            style: AppTheme.caption,
          ),
          const SizedBox(height: 10),
          for (final question in quiz.questions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ReviewCard(
                question: question,
                pickedAnswerId: _answers[question.id],
                grade: result.gradeFor(question.id),
              ),
            ),
        ],

        const SizedBox(height: 8),
        Text(
          'Rond de les af om verder te gaan.',
          style: AppTheme.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _AnswerRow extends StatelessWidget {
  const _AnswerRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Material(
      color: selected ? AppTheme.tealTint : AppTheme.paperRaised,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(color: selected ? AppTheme.teal : AppTheme.rule),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18,
                color: selected ? AppTheme.teal : AppTheme.inkMuted,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: AppTheme.bodyStrong)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One question, after marking.
///
/// Folded by default to right or wrong and the question itself, so the list
/// reads as a tally first; a tap opens the rest - the reader's own pick, the
/// correct answer when they missed it, the explanation and the verse it is in.
class _ReviewCard extends StatefulWidget {
  const _ReviewCard({
    required this.question,
    required this.pickedAnswerId,
    required this.grade,
  });

  final QuizQuestion question;
  final String? pickedAnswerId;
  final QuizGrade? grade;

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  bool _expanded = false;

  String? _answerText(String? id) {
    if (id == null) return null;
    for (final answer in widget.question.answers) {
      if (answer.id == id) return answer.text;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final grade = widget.grade;
    // An unmarked question says nothing about right or wrong - the grader did
    // not recognise it, so claiming either way would be a guess.
    final marked = grade != null && grade.known;
    final correct = marked && grade.correct;

    final picked = _answerText(widget.pickedAnswerId);
    final rightAnswer = _answerText(grade?.correctAnswerId);
    final reference = grade?.bibleReference ?? widget.question.bibleReference;

    final tone = !marked
        ? AppTheme.inkMuted
        : correct
        ? AppTheme.positive
        : AppTheme.destructive;

    return AppCard(
      radius: AppTheme.radiusMd,
      padding: const EdgeInsets.all(14),
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  !marked
                      ? Icons.help_outline
                      : correct
                      ? Icons.check_circle
                      : Icons.cancel,
                  size: 16,
                  color: tone,
                  semanticLabel: !marked
                      ? 'Niet nagekeken'
                      : correct
                      ? 'Goed'
                      : 'Fout',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.question.text,
                  style: AppTheme.bodyStrong,
                  maxLines: _expanded ? null : 2,
                  overflow: _expanded ? null : TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  Icons.expand_more,
                  size: 20,
                  color: AppTheme.inkFaint,
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(left: 26, top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ReviewLine(
                          label: 'Jouw antwoord',
                          value: picked ?? 'Niet beantwoord',
                          color: marked ? tone : null,
                        ),
                        // Only worth stating when they missed it; repeating
                        // their own correct answer back at them is noise.
                        if (marked && !correct && rightAnswer != null) ...[
                          const SizedBox(height: 6),
                          _ReviewLine(
                            label: 'Juiste antwoord',
                            value: rightAnswer,
                            color: AppTheme.positive,
                          ),
                        ],
                        if (grade?.explanation != null) ...[
                          const SizedBox(height: 10),
                          Text(grade!.explanation!, style: AppTheme.bodyMuted),
                        ],
                        if (reference != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            reference,
                            style: AppTheme.caption.copyWith(
                              color: AppTheme.teal,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppTheme.overline),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTheme.bodyMuted.copyWith(color: color ?? AppTheme.ink),
        ),
      ],
    );
  }
}
