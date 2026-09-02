import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
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
  const LessonQuizStep({super.key, required this.lesson, required this.lessonRef});

  final LessonPayload lesson;
  final LessonRef lessonRef;

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
  /// blank quiz - the server keeps every pick.
  void _seed(LessonQuiz quiz) {
    if (_seeded) return;
    _seeded = true;
    _answers.addAll(quiz.savedAnswers);
    if (quiz.isGraded) {
      _result = QuizResult(
        score: quiz.savedScore!,
        total: quiz.savedTotal!,

      );
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

  Future<void> _pick(LessonQuiz quiz, QuizQuestion question, String answerId) async {
    setState(() => _answers[question.id] = answerId);

    final repository = ref.read(lessonRepositoryProvider);
    final lessonRef = widget.lessonRef;

    // Save on every tap so a half-finished quiz survives leaving the lesson.
    unawaited(
      repository
          .saveQuizAnswers(lessonRef.studyId, lessonRef.day, {question.id: answerId})
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
    } on LessonException catch (e) {
      if (!mounted) return;
      setState(() => _grading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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

        final question = quiz.questions[_index.clamp(0, quiz.questions.length - 1)];
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
              onTap: picked != null ? null : () => _pick(quiz, question, answer.id),
            ),
          ),
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
              Text(
                '${result.score}/${result.total}',
                style: AppTheme.displayLarge.copyWith(color: AppTheme.teal),
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
  const _AnswerRow({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
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
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.question,
    required this.pickedAnswerId,
    required this.grade,
  });

  final QuizQuestion question;
  final String? pickedAnswerId;
  final QuizGrade? grade;

  String? _answerText(String? id) {
    if (id == null) return null;
    for (final answer in question.answers) {
      if (answer.id == id) return answer.text;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // An unmarked question says nothing about right or wrong - the grader did
    // not recognise it, so claiming either way would be a guess.
    final marked = grade != null && grade!.known;
    final correct = marked && grade!.correct;

    final picked = _answerText(pickedAnswerId);
    final rightAnswer = _answerText(grade?.correctAnswerId);

    final tone = !marked
        ? AppTheme.inkMuted
        : correct
        ? AppTheme.positive
        : AppTheme.destructive;

    return AppCard(
      radius: AppTheme.radiusMd,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                !marked
                    ? Icons.help_outline
                    : correct
                    ? Icons.check_circle
                    : Icons.cancel,
                size: 16,
                color: tone,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(question.text, style: AppTheme.bodyStrong)),
            ],
          ),
          const SizedBox(height: 10),
          if (picked != null)
            _ReviewLine(
              label: 'Jouw antwoord',
              value: picked,
              color: marked ? tone : null,
            ),
          // Only worth stating when they missed it; repeating their own
          // correct answer back at them is noise.
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
          if (grade?.bibleReference != null) ...[
            const SizedBox(height: 6),
            Text(
              grade!.bibleReference!,
              style: AppTheme.caption.copyWith(color: AppTheme.teal),
            ),
          ],
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
