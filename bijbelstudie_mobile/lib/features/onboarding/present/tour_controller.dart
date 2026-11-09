import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../ai/present/ai_suggested_question.dart';
import '../../auth/present/auth_controller.dart';
import '../../progress_tree/present/progress_tree_providers.dart';
import '../../study/present/study_pane_controller.dart';
import '../data/guide_repository.dart';
import '../data/onboarding_storage.dart';
import '../data/preferences_repository.dart';
import '../domain/guide_machine.dart';
import 'guide_cues.dart';

export '../domain/guide_machine.dart';

/// The onboarding guide: four things the reader does for real, right after
/// setup, with a hand showing how - see [GuideMachine] for the steps and why
/// they replaced the spotlight tour.
///
/// The provider keeps the tour's name, [tourControllerProvider], and its
/// `active` flag on purpose: the Pro promo, the rating prompt and the reader's
/// auto-hiding bars already stand back while it is set, and they keep doing so
/// without having to know the tour became a guide. `/tour` still starts it,
/// from setup and from Profiel.

/// Anchor ids. Constants rather than bare strings so a renamed anchor breaks
/// at compile time instead of silently never being found.
class TourAnchorIds {
  const TourAnchorIds._();

  static const dashboardHero = 'dashboard-hero';
  static const navStudy = 'nav-study';
  static const navStudies = 'nav-studies';
  static const navNotes = 'nav-notes';
  static const navProfile = 'nav-profile';
  static const readerBar = 'reader-bar';
  static const readerText = 'reader-text';
  static const studyPaneSwitcher = 'study-pane-switcher';
  static const studyMaterialsTabs = 'study-materials-tabs';
  static const notesTabs = 'notes-tabs';
  static const profilePro = 'profile-pro';

  // The guide's own targets.
  /// The chapter's first verse row in the reader.
  static const firstVerse = 'reader-first-verse';

  /// The colour dots in the verse action sheet.
  static const sheetColours = 'verse-sheet-colours';
  static const sheetNote = 'verse-sheet-note';
  static const sheetCommentary = 'verse-sheet-commentary';

  /// The Assistent label in Studie's tab row: the label found by its text
  /// inside the row's own anchor (see [TourAnchors.rectFor]).
  static const aiTab = '$studyMaterialsTabs#Assistent';

  /// The first suggested question in the assistant's empty state.
  static const aiSuggestion = 'ai-suggestion';
  static const aiComposer = 'ai-composer';
}

/// Sends one guide event to the funnel. A provider so tests can listen in
/// without an [Analytics] client and its network.
typedef GuideTracker = void Function(String event, Map<String, String> props);

final guideTrackerProvider = Provider<GuideTracker>((ref) {
  return (event, props) {
    try {
      ref.read(analyticsProvider).track(event, props);
    } catch (_) {
      // Telemetry never interrupts the guide.
    }
  };
});

final tourControllerProvider = NotifierProvider<TourController, GuideState>(
  TourController.new,
);

class TourController extends Notifier<GuideState> {
  @override
  GuideState build() {
    // The swipe and the Assistent tab are not callbacks anywhere: they are the
    // study pane changing. Listening here sees a drag across the pager and a
    // tap on the switch alike, which is the point - either gets you there.
    ref.listen(studyPaneProvider, _onPane);
    return const GuideState();
  }

  String? get _accountId {
    try {
      return ref.read(authControllerProvider).value?.id;
    } catch (_) {
      return null;
    }
  }

  void _track(String event, Map<String, String> props) =>
      ref.read(guideTrackerProvider)(event, props);

  /// Starts the guide from its first step. [replay] is a run started again
  /// from Profiel rather than straight after setup.
  void start({bool replay = false}) {
    if (state.active) return;
    int? startXp;
    try {
      startXp = ref.read(treeStateProvider).value?.xp;
    } catch (_) {}
    state = GuideMachine.start(replay: replay, startXp: startXp);
    ref.read(guideTipsProvider.notifier).guideStarted();
    _track(AnalyticsEvents.guideStarted, {'replay': '$replay'});
    _syncSuggestion();
  }

  /// Reports something the reader did. Safe to call at any time: outside the
  /// guide it only keeps track of open sheets, for the tips.
  void signal(GuideSignal signal, {int? verse}) {
    final before = state;
    final after = GuideMachine.signal(before, signal, verse: verse);
    if (identical(after, before)) return;
    state = after;
    final step = before.step;
    if (step != null && !before.stepDone && after.stepDone) {
      _track(AnalyticsEvents.guideStepCompleted, {
        'step': step.id.id,
        'how': after.fallback ? 'fallback' : 'done',
      });
    }
    if (after.verse != before.verse) _syncSuggestion();
  }

  /// Volgende, once the current step is done.
  void next() {
    final before = state;
    final after = GuideMachine.next(before);
    if (identical(after, before)) return;
    state = after;
    _afterAdvance(before, after);
  }

  /// Overslaan: leaves this step for a tip and goes on to the next.
  void skip() {
    final before = state;
    final step = before.step;
    if (step == null) return;
    _track(AnalyticsEvents.guideStepSkipped, {'step': step.id.id, 'how': 'skip'});
    final after = GuideMachine.skip(before);
    state = after;
    _afterAdvance(before, after);
  }

  /// The close button: stops the guide where it is. This step and every one
  /// not reached yet come back as tips. On the reward card it simply closes.
  void close() {
    final before = state;
    if (!before.active) return;
    if (before.finishing) {
      state = GuideMachine.end(before);
      return;
    }
    final step = before.step;
    if (step != null) {
      _track(AnalyticsEvents.guideStepSkipped, {'step': step.id.id, 'how': 'close'});
    }
    state = GuideMachine.end(before);
    _ended(before.unfinished);
    _syncSuggestion();
  }

  /// Offers the assistant a question about the verse the reader marked, for
  /// exactly as long as the assistant step is on - and takes it away again,
  /// so it never lingers in the assistant after the guide.
  void _syncSuggestion() {
    final verse = state.verse;
    final wanted = state.step?.id == GuideStepId.ask && verse != null
        ? GuideCopy.verseQuestion(verse)
        : null;
    if (ref.read(aiSuggestedQuestionProvider) != wanted) {
      ref.read(aiSuggestedQuestionProvider.notifier).set(wanted);
    }
  }

  void _afterAdvance(GuideState before, GuideState after) {
    _syncSuggestion();
    final reachedEnd = after.finishing || !after.active;
    if (!reachedEnd) return;
    _track(AnalyticsEvents.guideFinished, {
      'done': '${after.completedCount}',
      'skipped': '${after.skippedCount}',
    });
    _ended(after.unfinished);
    if (after.finishing) unawaited(_claimReward());
  }

  /// Records that the guide is behind this account, here and on the server,
  /// and hands the steps it left to the tips. Best effort throughout: none of
  /// it may keep the guide on screen.
  void _ended(List<GuideStepId> unfinished) {
    final accountId = _accountId;
    ref.read(guideTipsProvider.notifier).guideEnded(unfinished);
    unawaited(() async {
      try {
        await ref.read(onboardingStorageProvider).markTourSeen(accountId);
      } catch (_) {}
      try {
        await ref.read(preferencesRepositoryProvider).syncPreferences({'tourCompleted': true});
      } catch (_) {
        // Offline. The local flag already did the job that matters.
      }
    }());
  }

  Future<void> _claimReward() async {
    final accountId = _accountId;
    final storage = ref.read(guideStorageProvider);
    state = state.copyWith(rewardLoading: true);
    // Pending until the server answers, so an offline finish is paid on a
    // later launch (GuideTips retries it). The server pays once either way.
    await storage.setRewardPending(accountId, true);
    try {
      final reward = await ref.read(guideRepositoryProvider).claimReward();
      await storage.setRewardPending(accountId, false);
      if (!ref.mounted) return;
      final paid = reward.rewarded ? reward.grant?.awarded : null;
      if (state.finishing) {
        state = state.copyWith(rewardLoading: false, rewardXp: paid);
      }
    } catch (_) {
      if (!ref.mounted) return;
      if (state.finishing) state = state.copyWith(rewardLoading: false);
    }
  }

  void _onPane(StudyPaneState? previous, StudyPaneState next) {
    if (!state.active) return;
    final wasMaterials = previous?.showMaterials ?? false;
    if (!wasMaterials && next.showMaterials) signal(GuideSignal.studyPaneShown);
    if (next.showMaterials && next.materialsTab == StudyPaneTabs.assistant) {
      signal(GuideSignal.assistantShown);
    }
    // The last step asks for the uitleg through a verse, but reaching the
    // commentary or the grondtekst some other way is the same lesson learnt.
    final reachedSource = next.showMaterials &&
        (next.materialsTab == StudyPaneTabs.commentary ||
            next.materialsTab == StudyPaneTabs.original) &&
        (!wasMaterials || previous?.materialsTab != next.materialsTab);
    if (reachedSource && state.step?.id == GuideStepId.study) {
      signal(GuideSignal.commentaryOpened);
    }
  }
}

/// The materials pane's tab indexes the guide cares about.
class StudyPaneTabs {
  const StudyPaneTabs._();

  static const commentary = 0;
  static const original = 1;
  static const assistant = 4;
}

class GuideTipsState {
  const GuideTipsState({this.pending = const [], this.showing});

  /// Steps that were skipped and have not been shown as a tip yet.
  final List<GuideStepId> pending;

  /// The tip on screen now.
  final GuideStepId? showing;
}

final guideTipsProvider = NotifierProvider<GuideTips, GuideTipsState>(GuideTips.new);

/// Skipped steps, coming back once each as a tip the first time the reader is
/// on that step's screen again.
///
/// "Again" is deliberate: the guide ends on the very screen its steps live on,
/// and a tip popping up the moment someone closed the guide would be the guide
/// refusing to be closed. So nothing shows while the guide runs, nor for
/// [quietAfterGuide] after it ended; after that, a reader arriving on the
/// screen gets at most one tip per visit.
class GuideTips extends Notifier<GuideTipsState> {
  static const quietAfterGuide = Duration(minutes: 20);

  bool _guideRunning = false;
  DateTime? _guideEndedAt;
  String? _loadedFor;

  @override
  GuideTipsState build() {
    ref.listen<String?>(sessionAccountProvider, (_, id) => _load(id), fireImmediately: true);
    return const GuideTipsState();
  }

  bool eligibleAt(DateTime now) {
    if (_guideRunning) return false;
    final ended = _guideEndedAt;
    return ended == null || now.difference(ended) >= quietAfterGuide;
  }

  void guideStarted() {
    _guideRunning = true;
    if (state.showing != null) state = GuideTipsState(pending: state.pending);
  }

  void guideEnded(List<GuideStepId> unfinished, {DateTime? now}) {
    _guideRunning = false;
    _guideEndedAt = now ?? DateTime.now();
    final merged = <GuideStepId>[
      for (final step in GuideStepId.values)
        if (state.pending.contains(step) || unfinished.contains(step)) step,
    ];
    state = GuideTipsState(pending: merged);
    unawaited(_save(merged));
  }

  /// Puts [step]'s tip on screen and spends it: it will not come back.
  void show(GuideStepId step) {
    final pending = [...state.pending]..remove(step);
    state = GuideTipsState(pending: pending, showing: step);
    unawaited(_save(pending));
  }

  void dismiss() {
    if (state.showing == null) return;
    state = GuideTipsState(pending: state.pending);
  }

  String? get _accountId {
    try {
      return ref.read(authControllerProvider).value?.id;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(List<GuideStepId> pending) =>
      ref.read(guideStorageProvider).setPendingTips(_accountId, pending);

  Future<void> _load(String? accountId) async {
    if (accountId == null || accountId == _loadedFor) return;
    _loadedFor = accountId;
    final storage = ref.read(guideStorageProvider);
    final pending = await storage.pendingTips(accountId);
    if (!ref.mounted || _loadedFor != accountId) return;
    state = GuideTipsState(pending: pending);

    // A guide finished offline still owes its XP. The server pays once, so a
    // retry that crosses an earlier success costs nothing.
    if (!await storage.rewardPending(accountId)) return;
    try {
      await ref.read(guideRepositoryProvider).claimReward();
      await storage.setRewardPending(accountId, false);
    } catch (_) {
      // Still offline: the next launch tries again.
    }
  }
}

/// Where the live widgets register themselves so the overlay can find them.
///
/// A plain process-wide registry rather than a provider or a map of
/// [GlobalKey]s. GlobalKeys were the obvious choice and the wrong one: during a
/// route transition go_router has the outgoing and incoming pages in the tree
/// at once, and two mounted widgets sharing one GlobalKey is a crash, not a
/// warning. Registering a [BuildContext] under a plain string cannot crash -
/// the second registration simply wins, which is also the one the reader is
/// looking at.
class TourAnchors {
  TourAnchors._();

  static final TourAnchors instance = TourAnchors._();

  final Map<String, BuildContext> _byId = {};

  void register(String id, BuildContext context) => _byId[id] = context;

  /// Removes [context] only if it is still the registered one, so a widget
  /// disposing *after* its replacement registered cannot unregister the
  /// replacement.
  void unregister(String id, BuildContext context) {
    if (identical(_byId[id], context)) _byId.remove(id);
  }

  BuildContext? contextFor(String id) {
    final context = _byId[id.split('#').first];
    if (context == null || !context.mounted) return null;
    return context;
  }

  /// The anchor's rectangle in global coordinates, or null while it is not
  /// mounted, not laid out, or off-screen.
  ///
  /// `anchor#Label` is the piece of text reading "Label" inside `anchor`: a
  /// tab label, say, in a tab row that is one shared widget, so the row does
  /// not need an anchor threaded into each of its tabs.
  Rect? rectFor(String id) {
    final context = contextFor(id);
    if (context == null) return null;
    final hash = id.indexOf('#');
    final object = hash < 0
        ? context.findRenderObject()
        : _findText(context as Element, id.substring(hash + 1));
    if (object is! RenderBox || !object.attached || !object.hasSize) return null;
    if (object.size.isEmpty) return null;
    return object.localToGlobal(Offset.zero) & object.size;
  }

  static RenderObject? _findText(Element root, String label) {
    RenderObject? found;
    void visit(Element element) {
      if (found != null) return;
      final widget = element.widget;
      if (widget is RichText && widget.text.toPlainText() == label) {
        found = element.renderObject;
        return;
      }
      element.visitChildElements(visit);
    }

    root.visitChildElements(visit);
    return found;
  }
}

/// Marks a widget as something the guide can point at.
///
/// Wrapping is deliberately invisible: it adds no layout, no painting and no
/// hit-test behaviour, so an anchor can be dropped around any widget without
/// changing how the screen looks or behaves when the guide is not running.
class TourAnchor extends StatefulWidget {
  const TourAnchor({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  State<TourAnchor> createState() => _TourAnchorState();
}

class _TourAnchorState extends State<TourAnchor> {
  @override
  void initState() {
    super.initState();
    TourAnchors.instance.register(widget.id, context);
  }

  @override
  void didUpdateWidget(TourAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      TourAnchors.instance.unregister(oldWidget.id, context);
      TourAnchors.instance.register(widget.id, context);
    }
  }

  @override
  void dispose() {
    TourAnchors.instance.unregister(widget.id, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
