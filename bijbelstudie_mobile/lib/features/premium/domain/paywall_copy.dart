import '../data/paywall_goal.dart';

/// The paywall's headline and benefit lines, chosen for the reader in front of
/// it.
///
/// The old paywall showed every reader the same four lines with "Offline
/// lezen" first - arguably the least compelling Pro feature for a study app -
/// and a reader blocked on notes or music landed on a list that mentioned
/// neither. `PaywallGate.benefit` was documented as "lift to the top" but
/// nothing read it. This is what reads it.
///
/// Every line here is a real Pro feature also named in `kProBenefits`; the
/// keys below are those titles, so the two lists cannot drift apart unseen
/// (see the paywall copy test).
class PaywallCopy {
  const PaywallCopy._();

  static const defaultHeadline = 'Verdiep je studie met Pro';

  /// Short paywall lines keyed by `kProBenefits` title, in the default order:
  /// the two features people actually come for first.
  static const Map<String, String> lines = {
    'Alle commentaren': 'Alle commentaren: Matthew Henry en Dachsel',
    'Meer AI-vragen': '200 AI-vragen per dag in plaats van 3',
    'Grondtekst': 'Grondtekst in Hebreeuws en Grieks',
    'Onbeperkt notities': 'Onbeperkt notities bij elk vers',
    'Offline lezen': 'Offline lezen, zonder verbinding',
    'Achtergrondmuziek': 'Rustige achtergrondmuziek bij het lezen',
  };

  /// How many lines the design has room for above the plans.
  static const int shown = 4;

  /// Per gate (`PaywallGate.id`): what the blocked reader was after, as the
  /// headline. Gates without one fall back to the goal or the default.
  static const Map<String, String> gateHeadlines = {
    'ai': 'Blijf doorvragen met Pro',
    'commentary': 'Lees elk commentaar met Pro',
    'grondtekst': 'Lees de grondtekst met Pro',
    'offline': 'Lees overal, ook zonder verbinding',
    'notities': 'Schrijf onbeperkt notities met Pro',
    'muziek': 'Lees met rustige muziek met Pro',
    'crossrefs': 'Zie alle verwante teksten met Pro',
    'levensboom': 'Laat je boom groeien in elke stijl',
  };

  /// The benefit a stated goal makes most relevant, lifted to the top.
  static String? goalBenefit(StudyGoal goal) => switch (goal) {
    StudyGoal.understandBible => 'Alle commentaren',
    StudyGoal.difficultPassages => 'Alle commentaren',
    StudyGoal.dailyHabit => 'Offline lezen',
    StudyGoal.learnAboutJesus => 'Meer AI-vragen',
    StudyGoal.theology => 'Grondtekst',
  };

  static String goalHeadline(StudyGoal goal) => switch (goal) {
    StudyGoal.understandBible => 'Begrijp de Bijbel beter met Pro',
    StudyGoal.difficultPassages => 'Begrijp ook de moeilijke passages',
    StudyGoal.dailyHabit => 'Maak van bijbelstudie een gewoonte',
    StudyGoal.learnAboutJesus => 'Leer Jezus beter kennen met Pro',
    StudyGoal.theology => 'Ga dieper de theologie in met Pro',
  };

  /// Per entry point (`?source=`), for the moments that have something
  /// specific to say. Only true statements: the referral week did end, the
  /// streak was reached.
  static const Map<String, String> sourceHeadlines = {
    'app_referral_end': 'Je Pro-week is voorbij. Ga verder met Pro',
    'app_streak': 'Mooi volgehouden! Ga nog dieper met Pro',
  };

  /// The headline: a gate the reader just hit wins over the moment that
  /// opened the offer, then a goal they stated earlier, then the default.
  static String headline({String? gateId, StudyGoal? goal, String? source}) {
    final forGate = gateId == null ? null : gateHeadlines[gateId];
    if (forGate != null) return forGate;
    final forSource = source == null ? null : sourceHeadlines[source];
    if (forSource != null) return forSource;
    if (goal != null) return goalHeadline(goal);
    return defaultHeadline;
  }

  /// The [shown] lines, with the gate's benefit first, then the goal's, then
  /// the default order. A lifted benefit that is not in the default top four
  /// (notes, music) pushes the last one out rather than making the list longer.
  static List<String> benefits({String? gateBenefit, StudyGoal? goal}) {
    final order = <String>[];
    void add(String? key) {
      if (key != null && lines.containsKey(key) && !order.contains(key)) order.add(key);
    }

    add(gateBenefit);
    if (goal != null) add(goalBenefit(goal));
    lines.keys.forEach(add);
    return [for (final key in order.take(shown)) lines[key]!];
  }
}
