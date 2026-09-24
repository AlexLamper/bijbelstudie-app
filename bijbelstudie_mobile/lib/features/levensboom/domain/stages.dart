/// The five growth phases: bands of growth steps with a name. Mirror of the
/// website's `lib/levensboom/stages.ts`.
///
/// Growth v2 (LEVENSBOOM_GROWTH_PLAN.md §4.1): the tree grows in 20 steps, one
/// per level, and the phase is what the strip under the avatar, the Groei
/// ladder and the level-up card call it - "Jonge boom · stap 9 van 20" reads as
/// something that happened, where "niveau 9" reads as a counter. From step 21
/// the tree is an Eeuwenoude boom and keeps maturing; every step past 20 is a
/// "jaarring".
///
/// The ids are the v1 stage ids, unchanged, so nothing that stores or compares
/// them breaks. `zaailing` is shown as "Scheut".
///
/// The step is the tree's; the level is the account's. For an account without
/// a growth floor they are the same number, with one they can differ
/// (`growth.dart`), which is why this takes a step and not a level. The
/// server serves the phase too (`levensboom.growth.phase`), so a build older
/// than a band change still shows the right word: prefer `TreeState.phase`.
library;

enum TreeStage { kiem, zaailing, jongeBoom, volwassenBoom, eeuwenoudeBoom }

const Map<TreeStage, String> kStageIds = {
  TreeStage.kiem: 'kiem',
  TreeStage.zaailing: 'zaailing',
  TreeStage.jongeBoom: 'jonge_boom',
  TreeStage.volwassenBoom: 'volwassen_boom',
  TreeStage.eeuwenoudeBoom: 'eeuwenoude_boom',
};

class StageDef {
  const StageDef({
    required this.stage,
    required this.name,
    required this.from,
    required this.to,
    required this.blurb,
  });

  final TreeStage stage;
  final String name;

  /// First growth step of the band.
  final int from;

  /// Last growth step of the band, or null for the open-ended last phase.
  final int? to;

  /// One line for the ladder and the level-up card.
  final String blurb;

  String get id => kStageIds[stage]!;
}

const List<StageDef> kStages = [
  StageDef(
    stage: TreeStage.kiem,
    name: 'Kiem',
    from: 1,
    to: 2,
    blurb: 'Het zaadje is open; de eerste blaadjes staan boven de grond.',
  ),
  StageDef(
    stage: TreeStage.zaailing,
    name: 'Scheut',
    from: 3,
    to: 6,
    blurb: 'Een jonge scheut die houtig wordt, met blad na blad.',
  ),
  StageDef(
    stage: TreeStage.jongeBoom,
    name: 'Jonge boom',
    from: 7,
    to: 12,
    blurb: 'De eerste takken; de kroon krijgt vorm.',
  ),
  StageDef(
    stage: TreeStage.volwassenBoom,
    name: 'Volwassen boom',
    from: 13,
    to: 20,
    blurb: 'Een volle kroon die elke stap breder wordt.',
  ),
  StageDef(
    stage: TreeStage.eeuwenoudeBoom,
    name: 'Eeuwenoude boom',
    from: 21,
    to: null,
    blurb: 'Volgroeid. Met elk niveau komt er een jaarring bij.',
  ),
];

/// A phase with its place in the table (the website's `Stage`).
class StageInfo {
  const StageInfo({
    required this.def,
    required this.index,
    required this.nextLevel,
    required this.nextName,
  });

  final StageDef def;
  final int index;

  /// First step of the next phase, or null on the last one. Named `nextLevel`
  /// because that is the key the v1 payload served; it is a step now - see
  /// [nextStep].
  final int? nextLevel;
  final String? nextName;

  TreeStage get stage => def.stage;
  String get id => def.id;
  String get name => def.name;

  /// First growth step of the band.
  int get from => def.from;

  /// Last growth step of the band, or null for the open-ended last phase.
  int? get to => def.to;
  String get blurb => def.blurb;

  /// First step of the next phase, or null on the last one.
  int? get nextStep => nextLevel;
}

StageInfo phaseForStep(int step) {
  final s = step < 1 ? 1 : step;
  var index = 0;
  for (var i = 0; i < kStages.length; i++) {
    if (s >= kStages[i].from) index = i;
  }
  final next = index + 1 < kStages.length ? kStages[index + 1] : null;
  return StageInfo(
    def: kStages[index],
    index: index,
    nextLevel: next?.from,
    nextName: next?.name,
  );
}

/// The phase an account without a growth floor is in at `level`.
///
/// Deprecated: use `phaseForStep(growth.step)` (or `TreeState.phase`): with a
/// floor the step runs ahead of the level. Kept so the callers that still
/// pass a level compile until they move.
StageInfo stageForLevel(int level) => phaseForStep(level);

StageDef? stageById(String? id) {
  for (final stage in kStages) {
    if (stage.id == id) return stage;
  }
  return null;
}
