import 'dart:async';

import 'package:bijbelstudie_mobile/core/preview/preview_data.dart';
import 'package:bijbelstudie_mobile/core/theme/app_theme.dart';
import 'package:bijbelstudie_mobile/features/levensboom/domain/tree_state.dart';
import 'package:bijbelstudie_mobile/features/levensboom/present/levensboom_providers.dart';
import 'package:bijbelstudie_mobile/features/study/domain/lesson_models.dart';
import 'package:bijbelstudie_mobile/features/study/present/lesson/lesson_complete_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The end of a lesson: the tree that grew, what was earned, and the way on.
///
/// Pumped in both themes because every colour on it is a theme token, and on a
/// phone-tall surface so the whole card - down to the buttons - is laid out.
void main() {
  // The card reads the retention store for the streak; without a store to
  // load it stays empty, and the streak falls back to the tree state's.
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  LessonPayload lesson({bool last = false}) {
    return LessonPayload.fromJson({
      'study': {'id': 'opstanding', 'title': 'De opstanding', 'lessonsTotal': 4},
      'lesson': {'day': 2, 'title': 'Het lege graf', 'estimatedMinutes': 15},
      'steps': ['intro', 'word', 'depth', 'reflection', 'quiz'],
      'passage': {
        'book': 'Johannes',
        'chapter': 20,
        'verseRange': '1-18',
        'verseStart': 1,
        'verseEnd': 18,
      },
      'translation': 'nbg51',
      'translations': [
        {'id': 'nbg51', 'name': 'NBG 1951', 'language': 'nl'},
      ],
      'commentaryId': 'dachsel',
      'content': {
        'intro': {'headline': 'Hoi', 'body': []},
        'depth': {'showMedia': false},
        'reflection': {'question': 'Wat raakt je hier?', 'prompts': []},
        'quiz': {'enabled': true, 'questionCount': 5},
      },
      'outline': [
        {'day': 1, 'title': 'Les 1', 'reference': 'Johannes 19', 'completed': true},
        {'day': 2, 'title': 'Het lege graf', 'reference': 'Johannes 20:1-18', 'completed': false},
        {'day': 3, 'title': 'Aan het meer', 'reference': 'Johannes 21', 'completed': false},
      ],
      if (!last) 'nextLessonDay': 3,
    });
  }

  Future<void> pump(
    WidgetTester tester, {
    required CompletionSummary summary,
    ThemeData? theme,
    bool last = false,
    int? quizScore,
    int? quizTotal,
    TreeStateNotifier Function()? tree,
  }) async {
    tester.view.physicalSize = const Size(420, 1700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          treeStateProvider.overrideWith(tree ?? PreviewTreeNotifier.new),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          home: Scaffold(
            body: LessonCompleteCard(
              lesson: lesson(last: last),
              summary: summary,
              quizScore: quizScore,
              quizTotal: quizTotal,
            ),
          ),
        ),
      ),
    );
    // Fixed pumps rather than `pumpAndSettle`: the tree keeps its ambient sway
    // clock running, so the frame never settles. A second is past the growth
    // bar's animation.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  for (final (name, theme) in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    testWidgets('a first completion shows the growth, the figures and the way on ($name)', (
      tester,
    ) async {
      await pump(
        tester,
        theme: theme,
        summary: const CompletionSummary(
          recorded: true,
          studyCompleted: false,
          xpAwarded: 25,
          nextLessonDay: 3,
        ),
        quizScore: 4,
        quizTotal: 5,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Je boom groeide'), findsOneWidget);
      // The eyebrow is set in caps.
      expect(find.text('LES 2 VAN 4 AFGEROND'), findsOneWidget);
      // What was read and how long it took is one sentence under the
      // headline, not a figure.
      expect(
        find.textContaining('Johannes 20:1-18 gelezen in 15 min'),
        findsOneWidget,
      );
      // The figure strip: XP, the quiz, the streak, and the study's share.
      expect(find.text('+25'), findsOneWidget);
      expect(find.text('XP'), findsOneWidget);
      expect(find.text('4/5'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('dagen op rij'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('Aan het meer'), findsOneWidget);
      expect(find.text('Verder met les 3'), findsOneWidget);
      expect(find.text('Voor nu genoeg'), findsOneWidget);
    });
  }

  testWidgets('a lesson read again says so and claims no growth', (tester) async {
    await pump(
      tester,
      summary: const CompletionSummary(
        recorded: false,
        reason: 'ALREADY_RECORDED',
        studyCompleted: false,
        nextLessonDay: 3,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('LES 2 VAN 4 OPNIEUW GELEZEN'), findsOneWidget);
    expect(find.text('Deze les telde al mee'), findsOneWidget);
    // Nothing was earned, so the XP figure is a dash and says why.
    expect(find.text('—'), findsOneWidget);
    expect(find.text('telde al mee'), findsOneWidget);
    expect(find.text('Je boom groeide'), findsNothing);
    expect(
      find.textContaining('Johannes 20:1-18 gelezen in 15 min'),
      findsOneWidget,
    );
  });

  testWidgets('a level-up names the new level and the badge by its Dutch label', (
    tester,
  ) async {
    await pump(
      tester,
      summary: const CompletionSummary(
        recorded: true,
        studyCompleted: false,
        xpAwarded: 40,
        levelledUp: true,
        // A raw id from `xp.newBadges`, exactly as the server sends it
        // (`lib/gamification.ts`) - never text meant for a reader.
        newBadges: ['firstlesson'],
        nextLessonDay: 3,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Nieuw niveau'), findsOneWidget);
    // The catalogue's Dutch label shows, not the id the server sent.
    expect(find.text('Eerste les'), findsOneWidget);
    expect(find.text('firstlesson'), findsNothing);
    expect(find.textContaining('Je boom groeide naar niveau'), findsOneWidget);
  });

  testWidgets('a badge id the app does not recognise still gets a Dutch label, never the raw id', (
    tester,
  ) async {
    await pump(
      tester,
      summary: const CompletionSummary(
        recorded: true,
        studyCompleted: false,
        xpAwarded: 40,
        levelledUp: true,
        // Not in `BadgeCatalog.serverBadges` - e.g. a badge this build
        // predates. It must not print the identifier at the reader.
        newBadges: ['volhouder'],
        nextLessonDay: 3,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('volhouder'), findsNothing);
    expect(find.text('Nieuwe badge'), findsOneWidget);
  });

  testWidgets('the last lesson of a study leads back to the study', (tester) async {
    await pump(
      tester,
      last: true,
      summary: const CompletionSummary(
        recorded: true,
        studyCompleted: true,
        xpAwarded: 25,
        noteId: 'note-9',
      ),
    );

    expect(tester.takeException(), isNull);
    // The eyebrow says what happened; the headline names what was finished.
    expect(find.text('STUDIE AFGEROND'), findsOneWidget);
    expect(find.text('De opstanding'), findsOneWidget);
    expect(find.text('Je reflectie is bewaard als notitie'), findsOneWidget);
    expect(find.text('Terug naar de studie'), findsOneWidget);
    expect(find.textContaining('Verder met les'), findsNothing);
  });
  testWidgets('with the tree switched off the streak is a plain count', (tester) async {
    await pump(
      tester,
      tree: _DisabledTreeNotifier.new,
      summary: const CompletionSummary(
        recorded: true,
        studyCompleted: false,
        xpAwarded: 25,
        nextLessonDay: 3,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Je boom groeide'), findsNothing);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('dagen op rij'), findsOneWidget);
    expect(
      find.textContaining('Johannes 20:1-18 gelezen in 15 min'),
      findsOneWidget,
    );
    expect(find.text('Verder met les 3'), findsOneWidget);
  });

  testWidgets('without a tree state the card still stands', (tester) async {
    await pump(
      tester,
      tree: _NoTreeNotifier.new,
      summary: const CompletionSummary(
        recorded: true,
        studyCompleted: false,
        xpAwarded: 25,
        nextLessonDay: 3,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Je boom groeide'), findsNothing);
    // No tree and an empty retention store: no streak figure at all, rather
    // than a column reading "0 dagen op rij".
    expect(find.text('dagen op rij'), findsNothing);
    expect(find.text('LES 2 VAN 4 AFGEROND'), findsOneWidget);
    expect(
      find.textContaining('Johannes 20:1-18 gelezen in 15 min'),
      findsOneWidget,
    );
    expect(find.text('Verder met les 3'), findsOneWidget);
  });
}

/// The preview tree with "Boom verbergen" on.
class _DisabledTreeNotifier extends TreeStateNotifier {
  @override
  Future<TreeState> build() async =>
      PreviewData.treeState.copyWith(disabled: true);
}

/// A fetch that never lands: the card before the first gamification response.
class _NoTreeNotifier extends TreeStateNotifier {
  @override
  Future<TreeState> build() => Completer<TreeState>().future;
}
