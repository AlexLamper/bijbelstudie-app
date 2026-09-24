/// What the API hands out about *someone else's* tree: enough to draw it,
/// nothing else. Mirror of the website's `lib/levensboom/publicCard.ts`.
library;

import 'catalog.dart';
import 'growth.dart';
import 'stages.dart';

/// How far someone else's tree is (the card's `growth`), computed by the
/// server with that account's floor.
class PublicTreeGrowth {
  const PublicTreeGrowth({
    required this.position,
    required this.step,
    required this.frac,
    required this.floor,
    this.phaseId,
    this.phaseName,
    this.phaseIndex,
  });

  /// Before growth v2 public trees drew at a fixed half-way point in their
  /// level; a server that serves no `growth` still gets exactly that.
  static const double fallbackFrac = 0.5;

  /// Effective position `e`.
  final double position;

  /// The structural step.
  final int step;

  /// 0..1 within the level.
  final double frac;
  final GrowthFloor? floor;

  /// The served phase (`{id, name, index}`), when there was one.
  final String? phaseId;
  final String? phaseName;
  final int? phaseIndex;

  /// The same numbers from the level alone, without a floor.
  factory PublicTreeGrowth.local(int level, {double frac = fallbackFrac}) {
    return PublicTreeGrowth(
      position: effectivePosition(level, frac),
      step: structuralStep(level),
      frac: frac,
      floor: null,
    );
  }

  /// Parses the card's `growth`, defensively; anything missing is computed
  /// from [level] (with the served floor and frac, when there are).
  static PublicTreeGrowth fromJson(Object? raw, {required int level}) {
    if (raw is! Map) return PublicTreeGrowth.local(level);
    final floor = GrowthFloor.fromJson(raw['floor']);
    final servedFrac = raw['frac'];
    final frac = servedFrac is num && servedFrac.isFinite
        ? servedFrac.toDouble().clamp(0.0, 1.0)
        : fallbackFrac;
    final servedPosition = raw['position'];
    final servedStep = raw['step'];
    final phase = raw['phase'];
    return PublicTreeGrowth(
      position: servedPosition is num && servedPosition.isFinite && servedPosition >= 1
          ? servedPosition.toDouble()
          : effectivePosition(level, frac, floor),
      step: servedStep is num && servedStep.isFinite && servedStep >= 1
          ? servedStep.toInt()
          : structuralStep(level, floor),
      frac: frac,
      floor: floor,
      phaseId: phase is Map && phase['id'] is String ? phase['id'] as String : null,
      phaseName: phase is Map && phase['name'] is String ? phase['name'] as String : null,
      phaseIndex: phase is Map && phase['index'] is num && (phase['index'] as num).isFinite
          ? (phase['index'] as num).toInt()
          : null,
    );
  }

  /// The phase by [step], in the server's words when it served them.
  StageInfo get phase {
    final local = phaseForStep(step);
    final known = stageById(phaseId);
    if (known == null) return local;
    final at = kStages.indexOf(known);
    final next = at + 1 < kStages.length ? kStages[at + 1] : null;
    return StageInfo(
      def: StageDef(
        stage: known.stage,
        name: phaseName == null || phaseName!.isEmpty ? known.name : phaseName!,
        from: known.from,
        to: known.to,
        blurb: known.blurb,
      ),
      index: phaseIndex ?? at,
      nextLevel: next?.from,
      nextName: next?.name,
    );
  }
}

class PublicTreeCard {
  const PublicTreeCard({
    required this.seed,
    required this.level,
    required this.avatar,
    required this.health,
    required this.disabled,
    PublicTreeGrowth? growth,
  }) : _growth = growth;

  final String seed;
  final int level;
  final AvatarChoice avatar;
  final double health;

  /// "Boom tonen" off means no tree anywhere, other people's screens included.
  final bool disabled;

  final PublicTreeGrowth? _growth;

  /// Where the tree is: served, or computed from [level] for a server that
  /// predates growth v2.
  PublicTreeGrowth get growth => _growth ?? PublicTreeGrowth.local(level);

  double get position => growth.position;
  int get step => growth.step;
  double get frac => growth.frac;
  GrowthFloor? get floor => growth.floor;

  /// The phase, by step.
  StageInfo get phase => growth.phase;

  /// Same as [phase]; the name used before growth v2.
  StageInfo get stage => phase;

  static PublicTreeCard? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final seed = raw['seed'] as String? ?? '';
    if (seed.isEmpty) return null;
    final level = (raw['level'] as num?)?.toInt() ?? 1;
    return PublicTreeCard(
      seed: seed,
      level: level,
      avatar: AvatarChoice.fromJson(raw['avatar']),
      health: (raw['health'] as num?)?.toDouble() ?? 1,
      disabled: raw['disabled'] == true,
      growth: raw['growth'] is Map ? PublicTreeGrowth.fromJson(raw['growth'], level: level) : null,
    );
  }
}
