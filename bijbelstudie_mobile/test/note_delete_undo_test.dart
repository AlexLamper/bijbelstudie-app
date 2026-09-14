import 'package:bijbelstudie_mobile/core/ui/timed_snack_bar.dart';
import 'package:bijbelstudie_mobile/features/notes/domain/note_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StudyNote restore after delete', () {
    final webPassage = StudyNote.fromSyncRecord({
      'id': 'web-f81d4fae-7dec-11d0-a765-00a0c91e6bf6',
      'kind': 'note',
      'updatedAt': '2026-09-01T10:00:00.000Z',
      'data': {
        'book': 'Genesis',
        'chapter': 1,
        'verse': 1,
        'verseEnd': 5,
        'verseText': 'In het begin',
        'noteText': 'Schepping',
        'translation': 'statenvertaling',
        'highlightColor': 'blue',
        'tags': ['begin'],
      },
    });

    test('keeps a website passage range in the reference and payload', () {
      expect(webPassage.reference, 'Genesis 1:1-5');
      final data = webPassage.toRequestData();
      expect(data['verseEnd'], 5);
      expect(data['verseReference'], 'Genesis 1:1-5');
    });

    test('withNewId changes only the id, so undo is not refused by the tombstone', () {
      final copy = webPassage.withNewId('11111111-2222-3333-4444-555555555555');
      expect(copy.id, isNot(webPassage.id));
      expect(copy.toRequestData(), webPassage.toRequestData());
    });
  });

  testWidgets('an action SnackBar dismisses itself even with accessible navigation', (
    tester,
  ) async {
    late ScaffoldMessengerState messenger;
    await tester.pumpWidget(
      MediaQuery(
        // An enabled accessibility service - the case where Flutter's own
        // timeout leaves a SnackBar with an action up forever.
        data: const MediaQueryData(accessibleNavigation: true),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                messenger = ScaffoldMessenger.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    showTimedSnackBar(
      messenger,
      SnackBar(
        content: const Text('Notitie verwijderd'),
        duration: kActionSnackBarDuration,
        action: SnackBarAction(label: 'Ongedaan maken', onPressed: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Notitie verwijderd'), findsOneWidget);

    await tester.pump(kActionSnackBarDuration + const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Notitie verwijderd'), findsNothing);
  });
}
