import 'tour_controller.dart';

/// What the guide says and shows at any moment: the words on the card, the
/// gesture the hand acts out and the widget it acts it out on.
///
/// A pure function of the guide's state and what is on screen ([GuideView]),
/// so every phase of every step can be checked in a unit test without
/// pumping a reader.

enum GuideGesture { none, tap, longPress, swipeLeft }

class GuideCue {
  const GuideCue({
    required this.text,
    this.gesture = GuideGesture.none,
    this.anchors = const [],
    this.needsReturn = false,
  });

  final String text;
  final GuideGesture gesture;

  /// Where to act it out, best first: the first one that is on screen wins.
  final List<String> anchors;

  /// The reader has wandered off the step's screen: the card offers a way
  /// back instead of pointing at something that is not there.
  final bool needsReturn;
}

/// What the app is showing, as far as the guide cares.
class GuideView {
  const GuideView({
    required this.onStudy,
    required this.showMaterials,
    required this.materialsTab,
  });

  /// `/study` - the Bijbel tab - is the current route.
  final bool onStudy;
  final bool showMaterials;
  final int materialsTab;
}

class GuideCopy {
  const GuideCopy._();

  static const overline = 'Probeer het zelf';

  static String title(GuideStepId step) => switch (step) {
    GuideStepId.mark => 'Markeer een vers',
    GuideStepId.swipe => 'Veeg naar de studie',
    GuideStepId.ask => 'Vraag het de assistent',
    GuideStepId.study => 'Open de uitleg bij een vers',
  };

  static String task(GuideTask task) => switch (task) {
    GuideTask.longPress => 'Houd een vers ingedrukt',
    GuideTask.pickColour => 'Kies een kleur',
    GuideTask.writeNote => 'Schrijf een korte notitie',
    GuideTask.swipeToStudy => 'Veeg over de tekst naar links',
    GuideTask.openAssistant => 'Tik op Assistent',
    GuideTask.askQuestion => 'Stel een vraag',
    GuideTask.openStudy => 'Kies Commentaar, Grondtekst of Kruisverwijzingen',
  };

  static String success(GuideStepId step, {required bool fallback}) {
    if (fallback) {
      return switch (step) {
        GuideStepId.ask =>
          'De assistent kan nu even geen antwoord geven. Hij staat altijd '
              'klaar onder Studie, probeer het later nog eens.',
        _ =>
          'Opslaan lukte nu niet, maar zo werkt het. Probeer het later '
              'gerust nog eens.',
      };
    }
    return switch (step) {
      GuideStepId.mark =>
        'Gelukt! Je markeringen en notities vind je ook terug onder Notities.',
      GuideStepId.swipe =>
        'Hier staan commentaar, grondtekst, achtergrond en de assistent bij '
            'dit hoofdstuk. Veeg naar rechts en je bent terug bij de tekst.',
      GuideStepId.ask =>
        'Gelukt! De assistent kent het hoofdstuk dat je open hebt. Lees het '
            'antwoord rustig en tik dan op Volgende.',
      GuideStepId.study =>
        'Gelukt! Zo open je bij elk vers de uitleg die erbij hoort.',
    };
  }

  /// The question offered first in the assistant, about the verse the reader
  /// just marked.
  static String verseQuestion(int verse) => 'Wat betekent vers $verse?';

  static const returnLabel = 'Terug naar de oefening';
  static const nextLabel = 'Volgende';
  static const lastLabel = 'Afronden';
  static const skipLabel = 'Overslaan';
  static const closeLabel = 'Rondleiding stoppen';
}

GuideCue cueFor(GuideState state, GuideView view) {
  final step = state.step;
  if (step == null) return const GuideCue(text: '');
  if (state.stepDone) {
    return GuideCue(text: GuideCopy.success(step.id, fallback: state.fallback));
  }

  final surface = state.surface;
  if (surface == GuideSurface.noteEditor) {
    return const GuideCue(text: 'Typ een paar woorden en tik op Opslaan.');
  }
  final away = !view.onStudy || view.showMaterials != step.onStudyPane;
  // A sheet can be up over any screen; what is in it decides the cue below.
  if (away && surface == GuideSurface.none) {
    // The swipe step is the one place where being on the other pane is the
    // goal rather than a detour, and it is already done by then.
    return GuideCue(
      text: !view.onStudy
          ? 'Ga terug naar de Bijbel om verder te oefenen.'
          : step.onStudyPane
              ? 'Ga terug naar Studie om verder te oefenen.'
              : 'Ga terug naar de tekst om verder te oefenen.',
      needsReturn: true,
    );
  }

  final done = state.done;
  switch (step.id) {
    case GuideStepId.mark:
      if (surface == GuideSurface.sheet) {
        if (!done.contains(GuideTask.pickColour)) {
          return const GuideCue(
            text: 'Kies een kleur. Het vers krijgt meteen die markering.',
            gesture: GuideGesture.tap,
            anchors: [TourAnchorIds.sheetColours],
          );
        }
        return const GuideCue(
          text: 'Tik nu op Notitie toevoegen.',
          gesture: GuideGesture.tap,
          anchors: [TourAnchorIds.sheetNote],
        );
      }
      final String text;
      if (!done.contains(GuideTask.longPress)) {
        text = 'Houd een vers een moment ingedrukt.';
      } else if (!done.contains(GuideTask.pickColour)) {
        text = 'Houd het vers nog eens ingedrukt en kies een kleur.';
      } else {
        text = 'Houd het vers nog eens ingedrukt en tik op Notitie toevoegen.';
      }
      return GuideCue(
        text: text,
        gesture: GuideGesture.longPress,
        anchors: const [TourAnchorIds.firstVerse, TourAnchorIds.readerText],
      );

    case GuideStepId.swipe:
      if (surface != GuideSurface.none) {
        return const GuideCue(text: 'Sluit dit venster en veeg dan over de tekst naar links.');
      }
      return const GuideCue(
        text: 'Veeg met je vinger over de tekst naar links. Zo ga je van de '
            'Bijbeltekst naar de studie bij dit hoofdstuk.',
        gesture: GuideGesture.swipeLeft,
        anchors: [TourAnchorIds.readerText],
      );

    case GuideStepId.ask:
      if (surface != GuideSurface.none) {
        return const GuideCue(text: 'Sluit dit venster en tik dan op Assistent.');
      }
      if (view.materialsTab != StudyPaneTabs.assistant) {
        return const GuideCue(
          text: 'Tik bovenaan op Assistent.',
          gesture: GuideGesture.tap,
          anchors: [TourAnchorIds.aiTab, TourAnchorIds.studyMaterialsTabs],
        );
      }
      if (state.asking) {
        return const GuideCue(text: 'Even geduld, het antwoord komt eraan…');
      }
      final verse = state.verse;
      return GuideCue(
        text: verse == null
            ? 'Tik op een voorbeeldvraag of typ je eigen vraag over dit hoofdstuk.'
            : 'Tik op "${GuideCopy.verseQuestion(verse)}" of typ je eigen vraag.',
        gesture: GuideGesture.tap,
        anchors: const [TourAnchorIds.aiSuggestion, TourAnchorIds.aiComposer],
      );

    case GuideStepId.study:
      if (surface == GuideSurface.sheet) {
        return const GuideCue(
          text: 'Kies Commentaar, Grondtekst of Kruisverwijzingen.',
          gesture: GuideGesture.tap,
          anchors: [TourAnchorIds.sheetCommentary],
        );
      }
      return const GuideCue(
        text: 'Houd een vers ingedrukt en open de uitleg erbij.',
        gesture: GuideGesture.longPress,
        anchors: [TourAnchorIds.firstVerse, TourAnchorIds.readerText],
      );
  }
}

/// The one-time tip for a step the reader skipped, shown the next time they
/// are on its screen.
GuideCue tipFor(GuideStepId step) => switch (step) {
  GuideStepId.mark => const GuideCue(
    text: 'Tip: houd een vers ingedrukt om het te markeren of er een notitie '
        'bij te schrijven.',
    gesture: GuideGesture.longPress,
    anchors: [TourAnchorIds.firstVerse, TourAnchorIds.readerText],
  ),
  GuideStepId.swipe => const GuideCue(
    text: 'Tip: veeg over de tekst naar links voor commentaar, grondtekst en '
        'de assistent bij dit hoofdstuk.',
    gesture: GuideGesture.swipeLeft,
    anchors: [TourAnchorIds.readerText],
  ),
  GuideStepId.ask => const GuideCue(
    text: 'Tip: onder Assistent stel je een vraag over het hoofdstuk dat je '
        'leest.',
    gesture: GuideGesture.tap,
    anchors: [TourAnchorIds.aiTab, TourAnchorIds.studyMaterialsTabs],
  ),
  GuideStepId.study => const GuideCue(
    text: 'Tip: houd een vers ingedrukt en kies Commentaar, Grondtekst of '
        'Kruisverwijzingen voor de uitleg bij dat vers.',
    gesture: GuideGesture.longPress,
    anchors: [TourAnchorIds.firstVerse, TourAnchorIds.readerText],
  ),
};

/// Whether [step]'s tip belongs on what is showing now.
bool tipFits(GuideStepId step, GuideView view) {
  if (!view.onStudy) return false;
  return switch (step) {
    GuideStepId.ask => view.showMaterials,
    _ => !view.showMaterials,
  };
}
