import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/notifications/notification_scheduler.dart';
import '../../../../core/notifications/notification_service.dart';
import '../../../../core/notifications/retention_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../../core/ui/skeleton.dart';
import '../../../ai/present/ai_assistant_pane.dart';
import '../../../dashboard/data/dashboard_repository.dart';
import '../../../dashboard/present/dashboard_providers.dart';
import '../../../settings/data/notification_prefs.dart';
import '../../../settings/data/reading_settings.dart';
import '../../../studies/data/enrollment_models.dart';
import '../../../studies/data/enrollment_repository.dart';
import '../../../studies/present/studies_providers.dart';
import '../../data/context_repository.dart';
import '../../data/lesson_repository.dart';
import '../../domain/lesson_models.dart';
import 'lesson_complete_card.dart';
import 'lesson_providers.dart';
import 'lesson_settings_sheet.dart';
import 'lesson_steps.dart';
import 'step_context.dart';
import 'step_depth.dart';
import 'step_quiz.dart';

/// One lesson, start to finish.
///
/// Full-screen and outside the tab shell on purpose: a lesson is a sitting, and
/// a bottom bar inviting you elsewhere works against that. The way out is the
/// X, which asks first if you are mid-lesson.
///
/// The server decides which steps exist ([LessonPayload.steps]) and this screen
/// renders them in that order - it never reorders or skips one, and never sends
/// back a key the server did not define. That is why a study with no authored
/// intro simply opens on Het Woord.
///
/// The one screen the client adds is [LessonSlot.context] - the images and the
/// book's background - inserted before Verdieping when there is something to put
/// on it. It exists in the rail, the counter and the Vorige/Volgende walk only;
/// every write names the nearest step the server actually knows.
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

  /// The commentary the Verdieping step shows. Seeded from the payload, then
  /// owned by the reader: it lives here rather than in the step so a pick
  /// survives walking to another step and back.
  String? _commentaryId;

  /// Latched the moment the background screen has something to show. Sticky on
  /// purpose: a rail that grows a step while the reader is walking it is odd,
  /// but one that loses a step under their feet is worse.
  bool _hasContext = false;

  LessonRef get _ref => LessonRef(widget.studyId, widget.day);

  /// Seed the cursor from the saved state the first time both the lesson and
  /// its state have arrived.
  void _seed(LessonPayload lesson, LessonState state) {
    if (_cursor != null) return;

    final steps = lesson.steps;
    final fromUrl = StudyStep.tryFromId(widget.initialStep);
    final step =
        [
          if (fromUrl != null && steps.contains(fromUrl)) fromUrl,
          if (state.currentStep != null && steps.contains(state.currentStep))
            state.currentStep!,
          if (steps.isNotEmpty) steps.first,
        ].firstOrNull ??
        StudyStep.word;

    _cursor = LessonCursor(
      slot: LessonSlot.of(step),
      completed: state.stepsCompleted.map(LessonSlot.of).toSet(),
      viewTranslation: state.viewTranslation ?? lesson.translation,
      depthPanel: state.depthPanel ?? 'media',
      reflectionText: state.reflectionText,
      summary: null,
    );
    _commentaryId = lesson.commentaryId;

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
    // The background screen has no server step, so moving on to it can leave
    // nothing worth writing. Sending an empty patch would only cost a request.
    if (currentStep == null &&
        completeStep == null &&
        viewTranslation == null &&
        depthPanel == null) {
      return;
    }
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

  void _goToSlot(LessonSlot slot) {
    setState(() => _cursor = _cursor!.copyWith(slot: slot));
    _bestEffort(currentStep: slot.serverStep);
  }

  Future<void> _next(LessonPayload lesson, List<LessonSlot> slots) async {
    final cursor = _cursor!;
    final index = slots.indexOf(cursor.slot);
    final isLast = index >= slots.length - 1;

    if (!isLast) {
      final next = slots[index + 1];
      setState(
        () => _cursor = cursor.copyWith(
          slot: next,
          completed: {...cursor.completed, cursor.slot},
        ),
      );
      // Only the steps the server defined are reported: leaving Het Woord for
      // the background screen completes Het Woord and says nothing more.
      _bestEffort(
        completeStep: cursor.slot.serverStep,
        currentStep: next.serverStep,
      );
      return;
    }

    await _finish(lesson, slots);
  }

  /// The step the server should hear about for [slot]: itself, or - for the
  /// client-only background screen - the last real step before it.
  StudyStep _serverStepFor(List<LessonSlot> slots, LessonSlot slot) {
    for (var i = slots.indexOf(slot); i >= 0; i--) {
      final step = slots[i].serverStep;
      if (step != null) return step;
    }
    return slots
            .map((entry) => entry.serverStep)
            .whereType<StudyStep>()
            .lastOrNull ??
        StudyStep.word;
  }

  /// The completing write. Sent once, from the last step only - it is the
  /// branch that grants XP, keeps the reflection as a note and rolls the
  /// enrollment on.
  Future<void> _finish(LessonPayload lesson, List<LessonSlot> slots) async {
    final cursor = _cursor!;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(lessonRepositoryProvider)
          .complete(
            widget.studyId,
            widget.day,
            completeStep: _serverStepFor(slots, cursor.slot),
            reflectionText: cursor.reflectionText,
          );

      // The catalogue, the detail screen and the dashboard all read these.
      ref.invalidate(serverStudyLessonsProvider);
      ref.invalidate(studyEnrollmentsProvider);

      // Retention: mirror the completion locally, advance the server streak
      // (its only caller), and re-derive the notification ladder so any nudge
      // for "today" is cancelled now that today is done.
      final retention = ref.read(retentionStoreProvider.notifier);
      final firstEver = !ref.read(retentionStoreProvider).firstLessonDone;
      await retention.markCompleted();
      await retention.markFirstLessonDone();
      unawaited(
        ref.read(dashboardRepositoryProvider).bumpStreak().then((r) {
          if (r != null) {
            retention.reconcileServerStreak(r.streak);
            if (mounted) ref.invalidate(dashboardProvider);
          }
        }, onError: (_, __) {}),
      );
      ref.invalidate(notificationRecomputeProvider);

      if (!mounted) return;
      setState(() {
        _busy = false;
        _cursor = cursor.copyWith(
          completed: {...cursor.completed, cursor.slot},
          summary:
              result.completion ??
              const CompletionSummary(recorded: true, studyCompleted: false),
        );
      });

      // The permission prompt is earned here, once, after the first finished
      // lesson (RETENTION_PLAN §4.6).
      if (firstEver && !ref.read(retentionStoreProvider).permissionAskedAfterFirstLesson) {
        await _askForNotifications();
      }
      // A just-earned milestone is celebrated in-app rather than as a push.
      if (!mounted) return;
      final milestone =
          await NotificationScheduler.celebrateNextMilestone(ref, foregrounded: true);
      if (milestone != null && mounted) {
        await _celebrate(milestone.title, milestone.body);
      }
    } on LessonException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// The Dutch pre-permission bottom sheet (RETENTION_PLAN §4.6). Shown in-app
  /// before the OS dialog; a "Nu niet" only sets the guard, it never re-prompts.
  Future<void> _askForNotifications() async {
    final retention = ref.read(retentionStoreProvider.notifier);
    await retention.markPermissionAsked();
    if (!mounted) return;

    final wants = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          24 + MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wil je een rustig zetje op je studiedag?',
                style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              "We sturen je hooguit één herinnering per dag, op het moment dat "
              "jij kiest — nooit 's avonds laat, nooit als je die dag al bezig "
              "bent geweest. Je zet het met één tik weer uit.",
              style: Theme.of(sheetContext).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: const Text('Nu niet'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: const Text('Herinner me'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (wants != true) return;
    final granted =
        await ref.read(notificationServiceProvider).requestPermission();
    if (granted) {
      await ref.read(notificationPrefsProvider.notifier).setMasterEnabled(true);
      await ref
          .read(notificationPrefsProvider.notifier)
          .setStudyReminder(enabled: true);
    }
    await ref
        .read(notificationPrefsProvider.notifier)
        .setPendingPermissionRequest(false);
    ref.invalidate(notificationRecomputeProvider);
  }

  Future<void> _celebrate(String title, String body) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Mooi'),
          ),
        ],
      ),
    );
  }

  void _previous(List<LessonSlot> slots) {
    final index = slots.indexOf(_cursor!.slot);
    if (index <= 0) return;
    _goToSlot(slots[index - 1]);
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

    // Watched from the shell rather than from the screen itself: it decides
    // whether the slot exists at all, and warming both requests here means the
    // screen opens on its content instead of on a spinner.
    if (lesson != null) {
      final passage = lesson.passage;
      final images = ref
          .watch(geoImagesProvider(GeoRef(passage.book, passage.chapter)))
          .value;
      // Only where the introduction is actually shown - see
      // [lessonShowsBookSummary]. Past lesson 1 the photographs have to carry
      // the step on their own, and a chapter with none simply has no
      // background step rather than one that opens onto a heading and air.
      final summary = lessonShowsBookSummary(lesson.day)
          ? ref.watch(bookSummaryProvider(passage.book)).value
          : null;
      if ((images != null && images.isNotEmpty) ||
          (summary != null && summary.trim().isNotEmpty)) {
        _hasContext = true;
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.paper,
      // No SafeArea here on purpose: [_TopBar] and [_Footer] paint their own
      // `paperRaised` full-bleed into the status-bar and home-indicator insets
      // and add the system padding inside themselves. Wrapping the body
      // instead left a strip of scaffold `paper` above the bar and below the
      // footer - two bands of the wrong colour framing every lesson. The
      // skeleton has no bar of its own, so that branch keeps a SafeArea.
      body: lessonAsync.when(
        loading: () => const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: SkeletonCardColumn(count: 3),
          ),
        ),
        error: (error, _) => _error(error),
        data: (data) {
          final cursor = _cursor;
          if (cursor == null) {
            return const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SkeletonCardColumn(count: 3),
              ),
            );
          }
          return _shell(data, cursor);
        },
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
          onOpenAssistant: null,
          onOpenSettings: null,
        ),
        Expanded(
          child: AppEmptyState(
            icon: needsEnrollment
                ? Icons.lock_outline
                : Icons.wifi_off_outlined,
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
    final slots = lessonSlots(
      lesson.steps,
      withContext: _hasContext && lesson.steps.contains(StudyStep.depth),
    );
    if (slots.isEmpty) {
      return _error(const LessonException('Deze les heeft nog geen stappen.'));
    }
    // The slot can vanish under the cursor only if the content behind it did;
    // falling back to the step it follows beats rendering nothing.
    final cursorIndex = slots.indexOf(cursor.slot);
    final index = cursorIndex >= 0
        ? cursorIndex
        : slots
              .indexWhere((slot) => slot.serverStep == StudyStep.depth)
              .clamp(0, slots.length - 1);
    final isLast = index >= slots.length - 1;

    if (cursor.isFinished) {
      return Column(
        children: [
          _TopBar(
            title: lesson.title,
            subtitle:
                '${lesson.studyTitle} · les ${lesson.day} van ${lesson.lessonsTotal}',
            onClose: () => _close(lesson),
            onTapTitle: null,
            onOpenAssistant: _openAssistant,
            // The lesson is over; there is nothing left to read differently.
            onOpenSettings: null,
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
              'Les ${lesson.day} van ${lesson.lessonsTotal} · stap ${index + 1} van ${slots.length}',
          onClose: () => _close(lesson),
          onTapTitle: () => _openNavigator(lesson),
          onOpenAssistant: _openAssistant,
          onOpenSettings: () => _openSettings(lesson),
        ),
        _StepRail(
          slots: slots,
          current: slots[index],
          completed: cursor.completed,
          onTap: (slot) {
            // Forward jumps are only allowed into ground already covered,
            // otherwise the rail becomes a way to skip the reading.
            final target = slots.indexOf(slot);
            if (cursor.completed.contains(slot) || target <= index) {
              _goToSlot(slot);
            }
          },
        ),
        Expanded(child: _stepBody(lesson, cursor)),
        _Footer(
          stepLabel: slots[index].label,
          canGoBack: index > 0,
          isLast: isLast,
          busy: _busy,
          onPrevious: () => _previous(slots),
          onNext: () => _next(lesson, slots),
        ),
      ],
    );
  }

  Widget _stepBody(LessonPayload lesson, LessonCursor cursor) {
    final step = cursor.slot.serverStep;
    if (step == null) return LessonContextStep(lesson: lesson);

    switch (step) {
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
          commentaryId: _commentaryId ?? lesson.commentaryId,
          onPanelChanged: (panel) {
            setState(() => _cursor = cursor.copyWith(depthPanel: panel));
            _bestEffort(depthPanel: panel);
          },
          // The pane persists the choice itself; this only stops the payload's
          // id from being re-applied over it on the next build.
          onCommentaryChanged: (id) => setState(() => _commentaryId = id),
        );
      case StudyStep.reflection:
        return LessonReflectionStep(
          lesson: lesson,
          initialText: cursor.reflectionText,
          onChanged: (text) =>
              _cursor = _cursor!.copyWith(reflectionText: text),
        );
      case StudyStep.quiz:
        return LessonQuizStep(lesson: lesson, lessonRef: _ref);
      case StudyStep.done:
        return const SizedBox.shrink();
    }
  }

  /// Translation and type size, from any step.
  ///
  /// The translation chips on Het Woord stay where they are - they are useful
  /// exactly where the passage is - but they were the only way to change it,
  /// and they are invisible from the other four steps. Both surfaces write the
  /// same lesson-scoped `viewTranslation`, so they cannot disagree.
  Future<void> _openSettings(LessonPayload lesson) {
    final cursor = _cursor!;
    final enrollment = ref.read(studyEnrollmentProvider(widget.studyId));
    final studyTranslation =
        enrollment?.translation ??
        ref.read(readingSettingsProvider).lastVersionId;
    return showLessonSettingsSheet(
      context,
      lesson: lesson,
      translation: cursor.viewTranslation,
      onTranslationChanged: (id) {
        setState(() => _cursor = _cursor!.copyWith(viewTranslation: id));
        _bestEffort(viewTranslation: id);
      },
      studyTranslation: studyTranslation,
      onStudyTranslationChanged: (id) {
        // Reflects immediately in the passage already on screen, exactly like
        // the lesson-scoped chips - a reader who just fixed their translation
        // should not have to leave and reopen the lesson to see it.
        setState(() => _cursor = _cursor!.copyWith(viewTranslation: id));
        _bestEffort(viewTranslation: id);
        unawaited(_updateStudyTranslation(id));
      },
    );
  }

  /// Changes the enrollment's own translation - the same setting the startup
  /// sheet collects - so a reader stuck reading the wrong one is never forced
  /// back out to the study detail screen to fix it.
  ///
  /// Writes through the same call the startup/settings sheet uses
  /// ([EnrollmentRepository.updateSettings]), carrying the enrollment's other
  /// settings forward unchanged, and mirrors [readingSettingsProvider] exactly
  /// like [showStudySettingsSheet] does - it is the reader's translation now,
  /// not just this study's.
  Future<void> _updateStudyTranslation(String translationId) async {
    final enrollment = ref.read(studyEnrollmentProvider(widget.studyId));
    if (enrollment == null || enrollment.translation == translationId) return;

    try {
      await ref
          .read(enrollmentRepositoryProvider)
          .updateSettings(
            widget.studyId,
            EnrollmentSettings(
              rhythm: enrollment.rhythm,
              depth: enrollment.depth,
              translation: translationId,
              reminderDays: enrollment.reminderDays,
            ),
          );
      ref.invalidate(studyEnrollmentsProvider);
      await ref
          .read(readingSettingsProvider.notifier)
          .setLastVersion(translationId);
    } on EnrollmentException catch (_) {
      // Best-effort, same as the lesson-scoped writes above: losing this
      // costs a re-tap of the picker, not worth an error state mid-lesson.
    }
  }

  /// The assistant, on every step and inline on none.
  ///
  /// A pane sitting in the middle of a step invites the reader to stop reading
  /// and start chatting; a button that opens a screen of its own does not, and
  /// is there when a question actually comes up. The pane is the reader's own -
  /// same quota, same chapter context - so nothing about asking changes here.
  Future<void> _openAssistant() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppTheme.paperRaised,
      builder: (sheetContext) {
        // The composer must stay above the keyboard, so the sheet gives back
        // exactly the height the keyboard took.
        final media = MediaQuery.of(sheetContext);
        final height = (media.size.height - media.viewInsets.bottom) * 0.92;
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 16, color: AppTheme.teal),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('AI-assistent', style: AppTheme.bodyStrong),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Sluiten',
                        color: AppTheme.inkMuted,
                      ),
                    ],
                  ),
                ),
                const Expanded(child: AiAssistantPane()),
              ],
            ),
          ),
        );
      },
    );
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
    required this.onOpenAssistant,
    required this.onOpenSettings,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onClose;
  final VoidCallback? onTapTitle;

  /// Null only where there is no lesson to ask about.
  final VoidCallback? onOpenAssistant;

  /// Null on the error bar, where there is no lesson to configure either.
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.paperRaised,
        border: Border(bottom: BorderSide(color: AppTheme.rule)),
      ),
      // Inside the decoration, so the bar's colour runs to the top of the
      // screen and the controls still clear the status bar.
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
              if (onOpenSettings != null)
                IconButton(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.tune),
                  tooltip: 'Vertaling en weergave',
                  color: AppTheme.ink,
                ),
              if (onOpenAssistant != null)
                IconButton(
                  onPressed: onOpenAssistant,
                  icon: const Icon(Icons.auto_awesome),
                  tooltip: 'Vraag de AI-assistent',
                  color: AppTheme.teal,
                ),
              // Whatever the right-hand side did not fill, so the title stays
              // optically centred against the close button on the left.
              SizedBox(
                width:
                    48 -
                    (onOpenSettings != null ? 24 : 0) -
                    (onOpenAssistant != null ? 24 : 0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The segmented progress bar over the lesson's steps.
class _StepRail extends StatelessWidget {
  const _StepRail({
    required this.slots,
    required this.current,
    required this.completed,
    required this.onTap,
  });

  final List<LessonSlot> slots;
  final LessonSlot current;
  final Set<LessonSlot> completed;
  final ValueChanged<LessonSlot> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: AppTheme.paperRaised,
      child: Row(
        children: [
          for (final slot in slots) ...[
            Expanded(
              child: InkWell(
                onTap: () => onTap(slot),
                child: Column(
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: completed.contains(slot) || slot == current
                            ? AppTheme.teal
                            : AppTheme.rule,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      slot.label,
                      style: AppTheme.overline.copyWith(
                        color: slot == current
                            ? AppTheme.tealStrong
                            : AppTheme.inkFaint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            if (slot != slots.last) const SizedBox(width: 6),
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
