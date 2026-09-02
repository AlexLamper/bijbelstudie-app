import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../../core/ui/skeleton.dart';
import '../../../studies/data/enrollment_models.dart';
import '../../../studies/present/studies_providers.dart';
import '../../data/lesson_repository.dart';
import '../../domain/lesson_models.dart';
import 'lesson_complete_card.dart';
import 'lesson_providers.dart';
import 'lesson_steps.dart';
import 'step_depth.dart';
import 'step_quiz.dart';

/// One lesson, start to finish.
///
/// Full-screen and outside the tab shell on purpose: a lesson is a sitting, and
/// a bottom bar inviting you elsewhere works against that. The way out is the
/// X, which asks first if you are mid-lesson.
///
/// The server decides which steps exist ([LessonPayload.steps]) and this screen
/// renders them in that order - it never adds, reorders or skips one. That is
/// why a study with no authored intro simply opens on Het Woord.
class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({
    super.key,
    required this.studyId,
    required this.day,
    this.initialStep,
  });

  final String studyId;
  final int day;

  /// From `?stap=`, when resuming. Ignored when the lesson has no such step.
  final String? initialStep;

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  LessonCursor? _cursor;
  bool _busy = false;

  LessonRef get _ref => LessonRef(widget.studyId, widget.day);

  /// Seed the cursor from the saved state the first time both the lesson and
  /// its state have arrived.
  void _seed(LessonPayload lesson, LessonState state) {
    if (_cursor != null) return;

    final steps = lesson.steps;
    final fromUrl = StudyStep.tryFromId(widget.initialStep);
    final step = [
      if (fromUrl != null && steps.contains(fromUrl)) fromUrl,
      if (state.currentStep != null && steps.contains(state.currentStep)) state.currentStep!,
      if (steps.isNotEmpty) steps.first,
    ].firstOrNull ?? StudyStep.word;

    _cursor = LessonCursor(
      step: step,
      completed: state.stepsCompleted.toSet(),
      viewTranslation: state.viewTranslation ?? lesson.translation,
      depthPanel: state.depthPanel ?? 'media',
      reflectionText: state.reflectionText,
      summary: null,
    );

    // The website writes the cursor on open, not on first move, so "waar was
    // ik" is right even for a reader who opens a lesson and puts the phone
    // down. Fire and forget: a failed cursor write must not block the lesson.
    Future.microtask(() => _bestEffort(currentStep: step));
  }

  /// A write whose failure the reader should never see: the step they are on,
  /// the panel they opened, the translation they switched to. Losing one costs
  /// a little resumption accuracy, so it is not worth an error state.
  void _bestEffort({
    StudyStep? currentStep,
    StudyStep? completeStep,
    String? viewTranslation,
    String? depthPanel,
  }) {
    unawaited(
      ref
          .read(lessonRepositoryProvider)
          .patch(
            widget.studyId,
            widget.day,
            currentStep: currentStep,
            completeStep: completeStep,
            viewTranslation: viewTranslation,
            depthPanel: depthPanel,
          )
          .then((_) {}, onError: (_, _) {}),
    );
  }

  void _goToStep(StudyStep step) {
    setState(() => _cursor = _cursor!.copyWith(step: step));
    _bestEffort(currentStep: step);
  }

  Future<void> _next(LessonPayload lesson) async {
    final cursor = _cursor!;
    final steps = lesson.steps;
    final index = steps.indexOf(cursor.step);
    final isLast = index >= steps.length - 1;

    if (!isLast) {
      final completed = {...cursor.completed, cursor.step};
      setState(() => _cursor = cursor.copyWith(
        step: steps[index + 1],
        completed: completed,
      ));
      _bestEffort(completeStep: cursor.step, currentStep: steps[index + 1]);
      return;
    }

    await _finish(lesson);
  }

  /// The completing write. Sent once, from the last step only - it is the
  /// branch that grants XP, keeps the reflection as a note and rolls the
  /// enrollment on.
  Future<void> _finish(LessonPayload lesson) async {
    final cursor = _cursor!;
    setState(() => _busy = true);
    try {
      final result = await ref.read(lessonRepositoryProvider).patch(
        widget.studyId,
        widget.day,
        completeStep: cursor.step,
        complete: true,
      );

      // The catalogue, the detail screen and the dashboard all read these.
      ref.invalidate(serverStudyLessonsProvider);
      ref.invalidate(studyEnrollmentsProvider);

      if (!mounted) return;
      setState(() {
        _busy = false;
        _cursor = cursor.copyWith(
          completed: {...cursor.completed, cursor.step},
          summary: result.completion ??
              const CompletionSummary(recorded: true, studyCompleted: false),
        );
      });
    } on LessonException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _previous(LessonPayload lesson) {
    final cursor = _cursor!;
    final index = lesson.steps.indexOf(cursor.step);
    if (index <= 0) return;
    _goToStep(lesson.steps[index - 1]);
  }

  /// Leaving mid-lesson loses nothing - every step is saved as it happens - but
  /// readers do not know that, so say so rather than just dropping them out.
  Future<void> _close(LessonPayload? lesson) async {
    final cursor = _cursor;
    final mustConfirm = lesson != null && cursor != null && !cursor.isFinished;

    if (mustConfirm) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Les verlaten?'),
          content: const Text(
            'Je voortgang is bewaard. Je kunt later verder waar je nu bent.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Blijf hier'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Verlaat les'),
            ),
          ],
        ),
      );
      if (leave != true) return;
    }

    if (!mounted) return;
    context.go('/studies/${widget.studyId}');
  }

  @override
  Widget build(BuildContext context) {
    final lessonAsync = ref.watch(lessonProvider(_ref));
    final stateAsync = ref.watch(lessonStateProvider(_ref));

    final lesson = lessonAsync.value;
    final state = stateAsync.value;
    if (lesson != null && state != null) _seed(lesson, state);

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: lessonAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: SkeletonCardColumn(count: 3),
          ),
          error: (error, _) => _error(error),
          data: (data) {
            final cursor = _cursor;
            if (cursor == null) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: SkeletonCardColumn(count: 3),
              );
            }
            return _shell(data, cursor);
          },
        ),
      ),
    );
  }

  Widget _error(Object error) {
    final needsEnrollment = error is LessonException && error.needsEnrollment;
    return Column(
      children: [
        _TopBar(
          title: 'Les',
          subtitle: null,
          onClose: () => _close(null),
          onTapTitle: null,
        ),
        Expanded(
          child: AppEmptyState(
            icon: needsEnrollment ? Icons.lock_outline : Icons.wifi_off_outlined,
            title: needsEnrollment ? 'Nog niet gestart' : 'Les niet geladen',
            description: error is LessonException
                ? error.message
                : 'Controleer je verbinding en probeer het opnieuw.',
            action: SiteButton(
              label: needsEnrollment ? 'Naar de studie' : 'Opnieuw proberen',
              expand: false,
              onPressed: needsEnrollment
                  ? () => context.go('/studies/${widget.studyId}')
                  : () => ref.invalidate(lessonProvider(_ref)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _shell(LessonPayload lesson, LessonCursor cursor) {
    final steps = lesson.steps;
    final index = steps.indexOf(cursor.step);
    final isLast = index >= steps.length - 1;

    if (cursor.isFinished) {
      return Column(
        children: [
          _TopBar(
            title: lesson.title,
            subtitle: '${lesson.studyTitle} · les ${lesson.day} van ${lesson.lessonsTotal}',
            onClose: () => _close(lesson),
            onTapTitle: null,
          ),
          Expanded(
            child: LessonCompleteCard(
              lesson: lesson,
              summary: cursor.summary!,
              quizScore: ref.watch(lessonQuizProvider(_ref)).value?.savedScore,
              quizTotal: ref.watch(lessonQuizProvider(_ref)).value?.savedTotal,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _TopBar(
          title: lesson.title,
          subtitle:
              'Les ${lesson.day} van ${lesson.lessonsTotal} · stap ${index + 1} van ${steps.length}',
          onClose: () => _close(lesson),
          onTapTitle: () => _openNavigator(lesson),
        ),
        _StepRail(
          steps: steps,
          current: cursor.step,
          completed: cursor.completed,
          onTap: (step) {
            // Forward jumps are only allowed into ground already covered,
            // otherwise the rail becomes a way to skip the reading.
            final target = steps.indexOf(step);
            if (cursor.completed.contains(step) || target <= index) {
              _goToStep(step);
            }
          },
        ),
        Expanded(child: _stepBody(lesson, cursor)),
        _Footer(
          stepLabel: cursor.step.label,
          canGoBack: index > 0,
          isLast: isLast,
          busy: _busy,
          onPrevious: () => _previous(lesson),
          onNext: () => _next(lesson),
        ),
      ],
    );
  }

  Widget _stepBody(LessonPayload lesson, LessonCursor cursor) {
    switch (cursor.step) {
      case StudyStep.intro:
        return LessonIntroStep(lesson: lesson);
      case StudyStep.word:
        return LessonWordStep(
          lesson: lesson,
          translation: cursor.viewTranslation,
          onTranslationChanged: (id) {
            setState(() => _cursor = cursor.copyWith(viewTranslation: id));
            // A view preference for this lesson only - the enrollment's own
            // translation is deliberately left alone.
            _bestEffort(viewTranslation: id);
          },
        );
      case StudyStep.depth:
        return LessonDepthStep(
          lesson: lesson,
          panel: cursor.depthPanel,
          translation: cursor.viewTranslation,
          onPanelChanged: (panel) {
            setState(() => _cursor = cursor.copyWith(depthPanel: panel));
            _bestEffort(depthPanel: panel);
          },
        );
      case StudyStep.reflection:
        return LessonReflectionStep(
          lesson: lesson,
          initialText: cursor.reflectionText,
          onChanged: (text) => _cursor = _cursor!.copyWith(reflectionText: text),
        );
      case StudyStep.quiz:
        return LessonQuizStep(lesson: lesson, lessonRef: _ref);
      case StudyStep.done:
        return const SizedBox.shrink();
    }
  }

  /// Jump to another lesson in the same study. Locked ahead of where the reader
  /// has got to, so the navigator cannot be used to skip the study.
  Future<void> _openNavigator(LessonPayload lesson) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppTheme.paperRaised,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            const Eyebrow('De lessen'),
            const SizedBox(height: 10),
            for (final entry in lesson.outline)
              _NavigatorRow(
                entry: entry,
                isCurrent: entry.day == lesson.day,
                locked: !entry.completed && entry.day > lesson.day,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.replace('/studie/${widget.studyId}/${entry.day}');
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.onTapTitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onClose;
  final VoidCallback? onTapTitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.paperRaised,
        border: Border(bottom: BorderSide(color: AppTheme.rule)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close),
            tooltip: 'Les sluiten',
            color: AppTheme.ink,
          ),
          Expanded(
            child: InkWell(
              onTap: onTapTitle,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Text(
                      title,
                      style: AppTheme.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: AppTheme.metaLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Balances the close button so the title stays optically centred.
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

/// The segmented progress bar over the lesson's steps.
class _StepRail extends StatelessWidget {
  const _StepRail({
    required this.steps,
    required this.current,
    required this.completed,
    required this.onTap,
  });

  final List<StudyStep> steps;
  final StudyStep current;
  final Set<StudyStep> completed;
  final ValueChanged<StudyStep> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: AppTheme.paperRaised,
      child: Row(
        children: [
          for (final step in steps) ...[
            Expanded(
              child: InkWell(
                onTap: () => onTap(step),
                child: Column(
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: completed.contains(step) || step == current
                            ? AppTheme.teal
                            : AppTheme.rule,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      step.label,
                      style: AppTheme.overline.copyWith(
                        color: step == current ? AppTheme.tealStrong : AppTheme.inkFaint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            if (step != steps.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.stepLabel,
    required this.canGoBack,
    required this.isLast,
    required this.busy,
    required this.onPrevious,
    required this.onNext,
  });

  final String stepLabel;
  final bool canGoBack;
  final bool isLast;
  final bool busy;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.paperRaised,
        border: Border(top: BorderSide(color: AppTheme.rule)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              IconButton(
                onPressed: canGoBack && !busy ? onPrevious : null,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Vorige stap',
              ),
              Expanded(
                child: Text(
                  stepLabel,
                  style: AppTheme.metaLabel,
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(
                width: 150,
                child: SiteButton(
                  label: isLast ? 'Les afronden' : 'Volgende',
                  trailingIcon: isLast ? Icons.check : Icons.arrow_forward,
                  height: 44,
                  loading: busy,
                  onPressed: busy ? null : onNext,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigatorRow extends StatelessWidget {
  const _NavigatorRow({
    required this.entry,
    required this.isCurrent,
    required this.locked,
    required this.onTap,
  });

  final LessonOutlineEntry entry;
  final bool isCurrent;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RuleListTile(
      onTap: locked ? null : onTap,
      child: Row(
        children: [
          Icon(
            entry.completed
                ? Icons.check_circle
                : locked
                ? Icons.lock_outline
                : Icons.radio_button_unchecked,
            size: 16,
            color: entry.completed
                ? AppTheme.positive
                : locked
                ? AppTheme.inkFaint
                : AppTheme.teal,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: AppTheme.bodyStrong.copyWith(
                    color: locked ? AppTheme.inkMuted : AppTheme.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(entry.reference, style: AppTheme.caption),
              ],
            ),
          ),
          if (isCurrent) SiteBadge.teal('Nu'),
        ],
      ),
    );
  }
}
