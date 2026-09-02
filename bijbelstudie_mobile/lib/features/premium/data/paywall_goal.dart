import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the reader said they want out of Bible study.
///
/// Asked once, at the top of the paywall funnel, and then used to phrase the
/// rest of it. The point is not analytics: a reader who has just said "ik wil
/// moeilijke passages begrijpen" and is then shown that exact sentence back,
/// with the features that serve it, is being answered rather than pitched.
///
/// It outlives the funnel because it is also the honest default for what to
/// recommend elsewhere later.
enum StudyGoal {
  understandBible(
    'understand_bible',
    'De Bijbel beter begrijpen',
    Icons.menu_book_outlined,
    'Je wilt de Bijbel beter begrijpen.',
  ),
  difficultPassages(
    'difficult_passages',
    'Moeilijke passages begrijpen',
    Icons.help_outline,
    'Je wilt moeilijke passages begrijpen.',
  ),
  dailyHabit(
    'daily_habit',
    'Een dagelijkse gewoonte opbouwen',
    Icons.local_fire_department_outlined,
    'Je wilt een dagelijkse gewoonte opbouwen.',
  ),
  learnAboutJesus(
    'learn_about_jesus',
    'Meer leren over Jezus',
    Icons.favorite_outline,
    'Je wilt meer leren over Jezus.',
  ),
  theology(
    'theology',
    'Dieper de theologie in',
    Icons.school_outlined,
    'Je wilt dieper de theologie in.',
  );

  const StudyGoal(this.id, this.label, this.icon, this.restated);

  final String id;
  final String label;
  final IconData icon;

  /// The goal said back to the reader as a sentence, for the benefits screen.
  final String restated;

  /// What this app does about that goal. Four lines, all of them things the
  /// app genuinely has - an unmet promise here is a refund and a bad review.
  List<String> get benefits => switch (this) {
    StudyGoal.understandBible => const [
      'Lees met uitleg naast de tekst',
      'Zie de context van elk hoofdstuk',
      'Volg begeleide studies per bijbelboek',
      'Houd bij wat je al gelezen hebt',
    ],
    StudyGoal.difficultPassages => const [
      'Raadpleeg betrouwbare commentaren',
      'Begrijp de context van het gedeelte',
      'Ontdek verwante bijbelteksten',
      'Vraag door over dit gedeelte',
    ],
    StudyGoal.dailyHabit => const [
      'Een vers en een leesmoment per dag',
      'Herinneringen op jouw ritme',
      'Zie je reeks en voortgang groeien',
      'Ga verder waar je gebleven was',
    ],
    StudyGoal.learnAboutJesus => const [
      'Studies over het leven van Jezus',
      'Uitleg bij de evangeliën',
      'Ontdek verwante bijbelteksten',
      'Schrijf je eigen reflecties op',
    ],
    StudyGoal.theology => const [
      'Commentaren van vertrouwde uitleggers',
      'Grondtekst in Hebreeuws en Grieks',
      'Historische en culturele achtergrond',
      'Diepgaande studies met toetsing',
    ],
  };

  static StudyGoal? fromId(String? id) {
    for (final goal in StudyGoal.values) {
      if (goal.id == id) return goal;
    }
    return null;
  }
}

const _kGoalKey = 'paywall.studyGoal';

final studyGoalProvider = NotifierProvider<StudyGoalController, StudyGoal?>(
  StudyGoalController.new,
);

class StudyGoalController extends Notifier<StudyGoal?> {
  @override
  StudyGoal? build() {
    _restore();
    return null;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = StudyGoal.fromId(prefs.getString(_kGoalKey));
    // Never overwrite a choice the reader made while this was loading.
    if (stored != null && state == null) state = stored;
  }

  Future<void> select(StudyGoal goal) async {
    state = goal;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kGoalKey, goal.id);
  }
}
