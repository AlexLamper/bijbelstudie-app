/// The onboarding guide as a pure state machine.
///
/// The guide replaced a spotlight tour that *described* the app: seven cards,
/// each pointing at a widget with a paragraph beside it. People skimmed it and
/// still did not know what the app could do. The guide has the reader *do* the
/// four things that matter most, on the real screens, right after setup:
///
/// 1. [GuideStepId.mark]  - long-press a verse, pick a colour, write a note;
/// 2. [GuideStepId.swipe] - swipe from the Bible text to Studie, the one
///    swipe the app has between screens (the main tabs do not swipe);
/// 3. [GuideStepId.ask]   - ask the assistant about the chapter;
/// 4. [GuideStepId.study] - open the commentary, grondtekst or
///    cross-references for a verse.
///
/// A step only advances on the real action, reported as a [GuideSignal] by the
/// widget where it happened. Nothing here touches Flutter, storage or the
/// network, so the whole flow is unit-testable; `tour_controller.dart` wraps
/// it with the side effects.
///
/// The guide must never trap anyone, so every failure counts: a highlight the
/// server refused, a note that could not be saved, an assistant that could
/// not answer - each completes its task as a *fallback* and the guide moves
/// on. The Overslaan link is always there as well.
library;

enum GuideStepId {
  mark('mark'),
  swipe('swipe'),
  ask('ask'),
  study('study');

  const GuideStepId(this.id);

  /// The id in storage and in analytics (`guide_step_*.step`).
  final String id;

  static GuideStepId? fromId(String raw) {
    for (final step in values) {
      if (step.id == raw) return step;
    }
    return null;
  }
}

/// One thing the reader has to do. A step is done when all of its tasks are.
enum GuideTask {
  longPress,
  pickColour,
  writeNote,
  swipeToStudy,
  openAssistant,
  askQuestion,
  openStudy,
}

/// What the app reports back. Sent whether or not the guide is running - a
/// signal outside the guide is a no-op, apart from keeping [GuideState.surface]
/// honest for the one-time tips.
enum GuideSignal {
  /// The verse action sheet opened (a verse was long-pressed).
  verseSheetOpened,

  /// The verse sheet and anything it led to (note editor, grondtekst,
  /// cross-references) have all closed again.
  verseSheetClosed,
  noteEditorOpened,
  noteEditorClosed,
  highlightSaved,
  highlightFailed,
  noteSaved,
  noteFailed,

  /// `/study` flipped from the Bible text to the materials pane, by a swipe or
  /// by the switch in the title row.
  studyPaneShown,

  /// The materials pane is on its Assistent tab.
  assistantShown,
  aiAsked,
  aiAnswered,

  /// The assistant could not answer: no network, a daily limit, an error, or
  /// it is unavailable altogether.
  aiFailed,
  commentaryOpened,
  originalOpened,
  crossRefsOpened,
}

/// What is covering the bottom of the screen right now, so the guide can keep
/// its card out of the way.
enum GuideSurface { none, sheet, noteEditor }

enum GuideOutcome { done, fallback, skipped }

class GuideStep {
  const GuideStep({
    required this.id,
    required this.tasks,
    required this.onStudyPane,
  });

  final GuideStepId id;
  final List<GuideTask> tasks;

  /// Which side of `/study` the step starts on: false for the Bible text,
  /// true for the materials (Commentaar ... Assistent).
  final bool onStudyPane;
}

/// The guide, in order. Four steps: Alex asked for three to five, the Pro
/// features first and used for real, plus the basic navigation gesture. The
/// swipe sits second because it is how the reader gets to the assistant.
const List<GuideStep> kGuideSteps = [
  GuideStep(
    id: GuideStepId.mark,
    tasks: [GuideTask.longPress, GuideTask.pickColour, GuideTask.writeNote],
    onStudyPane: false,
  ),
  GuideStep(
    id: GuideStepId.swipe,
    tasks: [GuideTask.swipeToStudy],
    onStudyPane: false,
  ),
  GuideStep(
    id: GuideStepId.ask,
    tasks: [GuideTask.openAssistant, GuideTask.askQuestion],
    onStudyPane: true,
  ),
  GuideStep(
    id: GuideStepId.study,
    tasks: [GuideTask.longPress, GuideTask.openStudy],
    onStudyPane: false,
  ),
];

class GuideState {
  const GuideState({
    this.active = false,
    this.replay = false,
    this.index = 0,
    this.done = const {},
    this.stepDone = false,
    this.fallback = false,
    this.asking = false,
    this.outcomes = const {},
    this.finishing = false,
    this.sheetOpen = false,
    this.editorOpen = false,
    this.verse,
    this.startXp,
    this.rewardLoading = false,
    this.rewardXp,
  });

  /// True from the first step until the reward card is closed. Other
  /// surfaces (the Pro promo, the rating prompt, the reader's auto-hiding
  /// bars) stand back while it is.
  final bool active;

  /// Started again from Profiel rather than straight after setup.
  final bool replay;

  final int index;

  /// Tasks of the current step that are done.
  final Set<GuideTask> done;

  /// Every task of the current step is done; the card shows its "gelukt"
  /// state and waits for Volgende, so nobody is pulled away from an answer
  /// they are still reading.
  final bool stepDone;

  /// The current step was completed by a failure rather than the real thing.
  final bool fallback;

  /// A question to the assistant is on its way.
  final bool asking;

  final Map<GuideStepId, GuideOutcome> outcomes;

  /// Past the last step: the reward card is up.
  final bool finishing;

  final bool sheetOpen;
  final bool editorOpen;

  /// The verse last long-pressed, so the assistant step can offer a question
  /// about that verse.
  final int? verse;

  /// The account's XP when the guide started, so the reward card can grow the
  /// tree from where it stood before the guide's own XP.
  final int? startXp;

  final bool rewardLoading;

  /// XP the guide's reward actually paid, once the server confirmed it.
  final int? rewardXp;

  GuideStep? get step =>
      active && !finishing && index >= 0 && index < kGuideSteps.length ? kGuideSteps[index] : null;

  GuideSurface get surface {
    if (editorOpen) return GuideSurface.noteEditor;
    if (sheetOpen) return GuideSurface.sheet;
    return GuideSurface.none;
  }

  int get completedCount =>
      outcomes.values.where((outcome) => outcome != GuideOutcome.skipped).length;

  int get skippedCount =>
      outcomes.values.where((outcome) => outcome == GuideOutcome.skipped).length;

  /// Steps that were skipped or never reached. These come back once each, as
  /// a tip, the first time the reader is on their screen again.
  List<GuideStepId> get unfinished => [
    for (final step in kGuideSteps)
      if (outcomes[step.id] == null || outcomes[step.id] == GuideOutcome.skipped) step.id,
  ];

  GuideState copyWith({
    bool? active,
    int? index,
    Set<GuideTask>? done,
    bool? stepDone,
    bool? fallback,
    bool? asking,
    Map<GuideStepId, GuideOutcome>? outcomes,
    bool? finishing,
    bool? sheetOpen,
    bool? editorOpen,
    int? verse,
    bool? rewardLoading,
    int? rewardXp,
  }) {
    return GuideState(
      active: active ?? this.active,
      replay: replay,
      index: index ?? this.index,
      done: done ?? this.done,
      stepDone: stepDone ?? this.stepDone,
      fallback: fallback ?? this.fallback,
      asking: asking ?? this.asking,
      outcomes: outcomes ?? this.outcomes,
      finishing: finishing ?? this.finishing,
      sheetOpen: sheetOpen ?? this.sheetOpen,
      editorOpen: editorOpen ?? this.editorOpen,
      verse: verse ?? this.verse,
      startXp: startXp,
      rewardLoading: rewardLoading ?? this.rewardLoading,
      rewardXp: rewardXp ?? this.rewardXp,
    );
  }
}

class GuideMachine {
  const GuideMachine._();

  static GuideState start({bool replay = false, int? startXp}) =>
      GuideState(active: true, replay: replay, startXp: startXp);

  /// Applies one signal. Only tasks of the current step can be completed, and
  /// a step that is already done stays done until Volgende.
  static GuideState signal(GuideState state, GuideSignal signal, {int? verse}) {
    var next = _surface(state, signal, verse: verse);
    final step = next.step;
    if (step == null || next.stepDone) return next;

    final tasks = _tasksFor(signal);
    if (signal == GuideSignal.aiAsked) next = next.copyWith(asking: true);
    if (signal == GuideSignal.aiAnswered || signal == GuideSignal.aiFailed) {
      next = next.copyWith(asking: false);
    }
    if (tasks.isEmpty) return next;

    final done = {...next.done, ...tasks.where(step.tasks.contains)};
    if (done.length == next.done.length) return next;

    final failed = signal == GuideSignal.highlightFailed ||
        signal == GuideSignal.noteFailed ||
        signal == GuideSignal.aiFailed;
    final fallback = next.fallback || failed;
    final complete = step.tasks.every(done.contains);
    return next.copyWith(done: done, fallback: fallback, stepDone: complete);
  }

  /// Volgende on a finished step.
  static GuideState next(GuideState state) {
    final step = state.step;
    if (step == null || !state.stepDone) return state;
    return _advance(
      state,
      step.id,
      state.fallback ? GuideOutcome.fallback : GuideOutcome.done,
    );
  }

  /// Overslaan: the current step is left for a tip and the guide goes on.
  static GuideState skip(GuideState state) {
    final step = state.step;
    if (step == null) return state;
    return _advance(state, step.id, GuideOutcome.skipped);
  }

  /// Stopped outright, or the reward card closed.
  static GuideState end(GuideState state) => GuideState(
    sheetOpen: state.sheetOpen,
    editorOpen: state.editorOpen,
  );

  static GuideState _advance(GuideState state, GuideStepId id, GuideOutcome outcome) {
    final outcomes = {...state.outcomes, id: outcome};
    final index = state.index + 1;
    final reset = GuideState(
      active: true,
      replay: state.replay,
      index: index,
      outcomes: outcomes,
      sheetOpen: state.sheetOpen,
      editorOpen: state.editorOpen,
      verse: state.verse,
      startXp: state.startXp,
    );
    if (index < kGuideSteps.length) return reset;
    // Past the last step. A reward is for doing something: a guide that was
    // skipped from start to end simply closes.
    final didSomething = outcomes.values.any((o) => o != GuideOutcome.skipped);
    if (!didSomething) return end(reset).copyWith(outcomes: outcomes);
    return reset.copyWith(finishing: true);
  }

  static GuideState _surface(GuideState state, GuideSignal signal, {int? verse}) {
    switch (signal) {
      case GuideSignal.verseSheetOpened:
        return state.copyWith(sheetOpen: true, verse: verse);
      case GuideSignal.verseSheetClosed:
        return state.copyWith(sheetOpen: false, editorOpen: false);
      case GuideSignal.noteEditorOpened:
        return state.copyWith(editorOpen: true);
      case GuideSignal.noteEditorClosed:
        return state.copyWith(editorOpen: false);
      default:
        return state;
    }
  }

  static List<GuideTask> _tasksFor(GuideSignal signal) {
    switch (signal) {
      case GuideSignal.verseSheetOpened:
        return const [GuideTask.longPress];
      case GuideSignal.highlightSaved:
      case GuideSignal.highlightFailed:
        return const [GuideTask.longPress, GuideTask.pickColour];
      case GuideSignal.noteSaved:
      case GuideSignal.noteFailed:
        return const [GuideTask.writeNote];
      case GuideSignal.studyPaneShown:
        return const [GuideTask.swipeToStudy];
      case GuideSignal.assistantShown:
        return const [GuideTask.openAssistant];
      case GuideSignal.aiAnswered:
      case GuideSignal.aiFailed:
        return const [GuideTask.openAssistant, GuideTask.askQuestion];
      case GuideSignal.commentaryOpened:
      case GuideSignal.originalOpened:
      case GuideSignal.crossRefsOpened:
        return const [GuideTask.longPress, GuideTask.openStudy];
      case GuideSignal.verseSheetClosed:
      case GuideSignal.noteEditorOpened:
      case GuideSignal.noteEditorClosed:
      case GuideSignal.aiAsked:
        return const [];
    }
  }
}
