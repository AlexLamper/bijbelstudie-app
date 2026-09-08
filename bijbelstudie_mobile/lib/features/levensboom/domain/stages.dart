/// The five growth stages: level bands with a name. Mirror of the website's
/// `lib/levensboom/stages.ts`.
///
/// The stage is what the strip under the avatar, the Groei timeline and the
/// level-up card call the tree - "Jonge boom" reads as something that
/// happened, where "niveau 4" reads as a counter. The server serves it too, so
/// a build older than a band change still shows the right word.
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
    required this.blurb,
  });

  final TreeStage stage;
  final String name;

  /// First level of the band.
  final int from;

  /// One line for the timeline.
  final String blurb;

  String get id => kStageIds[stage]!;
}

const List<StageDef> kStages = [
  StageDef(stage: TreeStage.kiem, name: 'Kiem', from: 1, blurb: 'Twee blaadjes boven de grond.'),
  StageDef(stage: TreeStage.zaailing, name: 'Zaailing', from: 2, blurb: 'De eerste vertakking.'),
  StageDef(
    stage: TreeStage.jongeBoom,
    name: 'Jonge boom',
    from: 4,
    blurb: 'Een echte kroon; bloesem in het voorjaar.',
  ),
  StageDef(
    stage: TreeStage.volwassenBoom,
    name: 'Volwassen boom',
    from: 8,
    blurb: 'Vol in het blad en de eerste vrucht.',
  ),
  StageDef(
    stage: TreeStage.eeuwenoudeBoom,
    name: 'Eeuwenoude boom',
    from: 16,
    blurb: 'Een tweede stam; blijft altijd groeien.',
  ),
];

class StageInfo {
  const StageInfo({
    required this.def,
    required this.index,
    required this.to,
    required this.nextLevel,
    required this.nextName,
  });

  final StageDef def;
  final int index;

  /// Last level of the band, or null for the open-ended last stage.
  final int? to;

  /// First level of the next stage, or null on the last one.
  final int? nextLevel;
  final String? nextName;

  TreeStage get stage => def.stage;
  String get id => def.id;
  String get name => def.name;
  int get from => def.from;
  String get blurb => def.blurb;
}

StageInfo stageForLevel(int level) {
  final lvl = level < 1 ? 1 : level;
  var index = 0;
  for (var i = 0; i < kStages.length; i++) {
    if (lvl >= kStages[i].from) index = i;
  }
  final next = index + 1 < kStages.length ? kStages[index + 1] : null;
  return StageInfo(
    def: kStages[index],
    index: index,
    to: next == null ? null : next.from - 1,
    nextLevel: next?.from,
    nextName: next?.name,
  );
}

StageDef? stageById(String? id) {
  for (final stage in kStages) {
    if (stage.id == id) return stage;
  }
  return null;
}
