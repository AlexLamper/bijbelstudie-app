/// Every growth-v2 string, in one place (LEVENSBOOM_GROWTH_PLAN.md §9), so the
/// studio pill, the progress strip, the Groei ladder, the level-up card and the
/// one-time home card say the same thing in the same words. Mirror of the
/// website's `lib/levensboom/growthCopy.ts`.
///
/// The rules (§9.1):
/// - The step is the tree's; the level is the account's. Both are shown, and
///   they never meet in one sentence. A pill or a subtitle may carry both
///   ("Niveau 9 · stap 9 van 20"), a sentence never does.
/// - Phase names are capitalised in pills and headers ("Jonge boom · stap 9
///   van 20") and lowercase inside a sentence ("Je boom is nu een jonge boom").
/// - The tree is "je boom". The copy never says "Levensboom".
library;

import 'catalog.dart';
import 'growth.dart' show GrowthFloor, levelForStep, mature, ringsForStep, stepsTotal, structuralStep;
import 'stages.dart';
import 'traits.dart';

// ---------------------------------------------------------------------------
// Numbers and names
// ---------------------------------------------------------------------------

/// A whole number with the Dutch thousands separator: 2100 → "2.100". Never
/// below 0 (the website's `formatXp`): XP still to go cannot be negative.
String formatCount(int n) {
  final digits = (n < 0 ? 0 : n).toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}

/// A phase name as it reads inside a sentence: "jonge boom".
String phaseInSentence(String name) => name.toLowerCase();

/// "1 jaarring", "3 jaarringen".
String ringsLabel(int rings) => rings == 1 ? '1 jaarring' : '${formatCount(rings)} jaarringen';

/// "stap 9 van 20", lowercase: it always follows a name or a level.
String stepOfTotal(int step) => 'stap $step van $stepsTotal';

// ---------------------------------------------------------------------------
// Pill, header and progress strip (§9.4, §9.5)
// ---------------------------------------------------------------------------

/// The studio pill and the Groei header: "Jonge boom · stap 9 van 20", and past
/// step 20 "Eeuwenoude boom · 3 jaarringen".
String growthPill(String phaseName, int step) {
  if (step > stepsTotal) return '$phaseName · ${ringsLabel(ringsForStep(step))}';
  return '$phaseName · ${stepOfTotal(step)}';
}

/// Where the bar to the next step leads: "nog 740 XP tot stap 10". At step 20
/// the next step is the first jaarring, past it the next one.
String xpToNextStepLabel(int step, int xp) {
  final amount = 'nog ${formatCount(xp)} XP';
  if (step < stepsTotal) return '$amount tot stap ${step + 1}';
  if (step == stepsTotal) return '$amount tot de eerste jaarring';
  return '$amount tot de volgende jaarring';
}

/// Line 1 of the progress strip: "Stap 9 van 20 · nog 740 XP tot stap 10";
/// past step 20 "Eeuwenoude boom · 3 jaarringen · nog 2.100 XP tot de volgende".
String progressStripLine({
  required String phaseName,
  required int step,
  required int xpToNextStep,
}) {
  if (step > stepsTotal) {
    return '$phaseName · ${ringsLabel(ringsForStep(step))} · '
        'nog ${formatCount(xpToNextStep)} XP tot de volgende';
  }
  return 'Stap $step van $stepsTotal · ${xpToNextStepLabel(step, xpToNextStep)}';
}

/// Line 2 of the progress strip: the next level-gated unlock, "nog 340 XP →
/// Palmboom". Shown only when it arrives no later than the next step
/// ([nextUnlockInReach]), so the strip never points past the thing the tree
/// is growing towards.
String nextUnlockLine({required String name, required int xp}) =>
    'nog ${formatCount(xp)} XP → $name';

/// Whether the next unlock lands no later than the tree's next step.
bool nextUnlockInReach({required int unlockLevel, required int levelForNextStep}) =>
    unlockLevel <= levelForNextStep;

// ---------------------------------------------------------------------------
// The Groei ladder (§9.4)
// ---------------------------------------------------------------------------

/// "Stap 9".
String ladderStep(int step) => 'Stap $step';

/// "Niveau 9": the level at which this account stands on a step.
String ladderLevel(int level) => 'Niveau $level';

/// Status of a step already behind the tree.
const String ladderReached = 'Behaald';

/// Status of the step the tree is on: "Nu · 62 %". Rounded down, so it never
/// reads 100 % before the next step is there.
String ladderCurrent(double progress) {
  final pct = (progress.isFinite ? progress : 0.0).clamp(0.0, 1.0);
  final whole = (pct * 100).floor().clamp(0, 99);
  return 'Nu · $whole %';
}

/// Status of a step still ahead: "Niveau 12".
String ladderAhead(int level) => ladderLevel(level);

/// A phase section's range: "stap 7–12", "stap 21+" for the open-ended last.
String phaseRange(int from, int? to) {
  if (to == null) return 'stap $from+';
  if (to == from) return 'stap $from';
  return 'stap $from–$to';
}

/// The one line under the Groei header for an account with a head start from
/// before growth v2, shown until step 20 ([showsFlooredExplainer]).
const String flooredExplainer =
    'Je boom had al een voorsprong van vóór de nieuwe groei. Die houdt hij, en hij '
    'groeit gewoon verder.';

bool showsFlooredExplainer(GrowthFloor? floor, int step) => floor != null && step < stepsTotal;

/// What arrives at [level]: traits, fruit and level-gated catalog items, as
/// the ladder row lists them. The fruit trait is left out, the fruit itself
/// names it.
List<String> arrivalsAtLevel(int level) {
  final fruit = fruitAtLevel(level);
  return [
    for (final trait in kTraitOrder)
      if (trait != TreeTrait.fruit && kTraitLevels[trait] == level) kTraitLabels[trait]!,
    if (fruit != null) 'Vrucht: ${fruit.name.toLowerCase()}',
    for (final item in itemsUnlockedAtLevel(level)) item.name,
  ];
}

/// What maturing adds past step 20, by step (plan §4.5; render-only in the
/// generator), at the steps `growth.dart`'s [mature] names.
final List<({int step, String label})> maturing = [
  (step: mature.knotsFrom.ceil(), label: 'Knoesten in de schors'),
  (step: mature.mossFrom.ceil(), label: 'Mos aan de voet'),
  (step: mature.flareFrom.ceil(), label: 'Wortels boven de grond'),
];

/// The next thing maturing brings, at the level this account reaches it:
/// "Mos aan de voet bij niveau 26". Null once all of it is there.
String? maturingNextLine(int step, [GrowthFloor? floor]) {
  for (final m in maturing) {
    if (m.step > step) return '${m.label} bij niveau ${levelForStep(m.step, floor)}';
  }
  return null;
}

// ---------------------------------------------------------------------------
// The level-up card (§9.3)
// ---------------------------------------------------------------------------

enum LevelUpCase {
  /// The tree crossed into another phase, the Eeuwenoude boom included.
  newPhase,

  /// A new step inside the same phase.
  newStep,

  /// A floored account levelled up without crossing a whole step: the tree
  /// still grew, it did not gain a step.
  noNewStep,

  /// Step 20: fully grown.
  fullyGrown,

  /// Past step 20: one or more jaarringen.
  newRing,
}

class LevelUpCopy {
  const LevelUpCopy({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.line,
    required this.step,
    required this.fromStep,
    required this.fruit,
  });

  final LevelUpCase kind;

  /// "Je boom is gegroeid".
  final String title;

  /// "Niveau 9 · stap 9 van 20", with " - {vrucht}" when a fruit arrived.
  final String subtitle;

  /// One sentence under it, or null when there is nothing more to say.
  final String? line;

  /// The tree's step after the level-up, and before it.
  final int step;
  final int fromStep;
  final SpiritFruit? fruit;
}

/// Geduld and geloof are het-words; every other fruit takes "de".
String _fruitArticle(String name) => name == 'Geduld' || name == 'Geloof' ? 'Het' : 'De';

/// The fruit line the card has always shown, with the article fixed for the
/// two het-words.
String fruitLine(SpiritFruit fruit) =>
    '${_fruitArticle(fruit.name)} ${fruit.name.toLowerCase()} hangt nu aan je boom - '
    'een vrucht van de Geest, ${fruit.reference}.';

/// The trait line; the fruit trait arrives with a named fruit, whose line says more.
String? _traitLine(int level) {
  final trait = traitAtLevel(level);
  return trait != null && trait != TreeTrait.fruit ? kTraitLabels[trait] : null;
}

/// Title, subtitle and line for the level-up card at [level].
///
/// [fromLevel] is the level the reader last saw (`lastSeenLevel`); a jump over
/// several levels is one card, judged from there. [floor] is the account's
/// head start. The cases, first match wins:
///
/// - no whole step crossed (only a floored account's slower steps can do this)
/// - step 20 reached ("volgroeid"; before "new phase" so a jump from 12 to 20
///   still reads as fully grown)
/// - a new phase, the Eeuwenoude boom included
/// - past 20: a jaarring
/// - otherwise a new step in the same phase
///
/// A fruit adds " - {fruit}" to the subtitle and takes the line, as before.
/// One addition to the plan's table (the website does the same): at step 20
/// the jaarring sentence is the only place the reader learns what happens
/// next, and an account without a floor always gets a fruit at level 20 - so
/// there the two lines are joined instead of the fruit replacing it.
LevelUpCopy levelUpCopy({required int level, int? fromLevel, GrowthFloor? floor}) {
  final lvl = level < 1 ? 1 : level;
  final previous = (fromLevel ?? lvl - 1).clamp(1, lvl - 1 < 1 ? 1 : lvl - 1);
  final step = structuralStep(lvl, floor);
  final before = structuralStep(previous, floor);
  final fromStep = before < step ? before : step;
  final phase = phaseForStep(step);
  final fromPhase = phaseForStep(fromStep);
  final fruit = fruitAtLevel(lvl);
  final extra = fruit != null ? fruitLine(fruit) : _traitLine(lvl);
  final suffix = fruit != null ? ' - ${fruit.name}' : '';
  final stepLabel = 'Niveau $lvl · ${stepOfTotal(step)}$suffix';
  final ringLabel = 'Niveau $lvl · ${ringsLabel(ringsForStep(step))}$suffix';

  LevelUpCopy copy(LevelUpCase kind, String title, String subtitle, String? line) => LevelUpCopy(
    kind: kind,
    title: title,
    subtitle: subtitle,
    line: line,
    step: step,
    fromStep: fromStep,
    fruit: fruit,
  );

  if (step == fromStep) {
    final towards = step < stepsTotal
        ? 'Hij groeit verder naar stap ${step + 1}.'
        : 'Hij groeit verder naar de volgende jaarring.';
    return copy(
      LevelUpCase.noNewStep,
      'Je boom is gegroeid',
      'Niveau $lvl$suffix',
      fruit != null ? fruitLine(fruit) : towards,
    );
  }

  if (step == stepsTotal) {
    const grown = 'Vanaf nu komt er met elk niveau een jaarring bij.';
    return copy(
      LevelUpCase.fullyGrown,
      'Je boom is volgroeid',
      stepLabel,
      fruit != null ? '$grown ${fruitLine(fruit)}' : grown,
    );
  }

  if (phase.index > fromPhase.index) {
    return copy(
      LevelUpCase.newPhase,
      'Je boom is nu een ${phaseInSentence(phase.name)}',
      step > stepsTotal ? ringLabel : stepLabel,
      fruit != null ? fruitLine(fruit) : phase.blurb,
    );
  }

  if (step > stepsTotal) {
    final gained = ringsForStep(step) - ringsForStep(fromStep);
    return copy(
      LevelUpCase.newRing,
      gained > 1 ? 'Er zijn $gained jaarringen bij' : 'Er is een jaarring bij',
      ringLabel,
      extra,
    );
  }

  return copy(LevelUpCase.newStep, 'Je boom is gegroeid', stepLabel, extra ?? 'Er is nieuw hout bijgekomen.');
}

// ---------------------------------------------------------------------------
// The one-time announcement (§9.6)
// ---------------------------------------------------------------------------

/// The `seenItems` key that records the card was dismissed.
const String growthAnnouncementKey = 'growth-v2';

const String growthAnnouncementTitle = 'Je boom groeit nu in twintig stappen';

const String growthAnnouncementBody =
    'Vanaf vandaag groeit je boom langzamer en in meer stappen, met elke les en elk '
    'hoofdstuk een stukje. Hij blijft minstens zo groot als hij was. Bij stap 20 is hij '
    'volgroeid; daarna komt er met elk niveau een jaarring bij.';

const String growthAnnouncementOpen = 'Bekijk je groei';
const String growthAnnouncementClose = 'Sluiten';

/// Only accounts from before the launch get the card (the server decides,
/// `announceGrowth`), once, and never while the tree is switched off.
bool showsGrowthAnnouncement({
  required bool announceGrowth,
  required Set<String> seenItems,
  bool disabled = false,
}) => announceGrowth && !disabled && !seenItems.contains(growthAnnouncementKey);
