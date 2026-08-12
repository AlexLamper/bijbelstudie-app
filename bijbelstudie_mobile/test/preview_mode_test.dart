import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bijbelstudie_mobile/core/config/preview_config.dart';
import 'package:bijbelstudie_mobile/core/preview/preview_data.dart';
import 'package:bijbelstudie_mobile/core/theme/app_theme.dart';
import 'package:bijbelstudie_mobile/features/bible/present/read_screen.dart';
import 'package:bijbelstudie_mobile/features/dashboard/present/dashboard_screen.dart';

void main() {
  test('preview mode is off unless the dart-define is passed', () {
    // The suite runs without --dart-define=PREVIEW=true, so this must be false.
    // Together with the kReleaseMode guard this keeps canned data out of
    // anything shipped to a store.
    expect(PreviewConfig.enabled, isFalse);
  });

  testWidgets('preview scope serves canned data to the dashboard', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      PreviewData.scope(
        MaterialApp(theme: AppTheme.lightTheme, home: const DashboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    // Name comes from the canned profile.
    expect(find.textContaining('Preview'), findsWidgets);
  });

  testWidgets('preview scope serves canned scripture to the reader', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      PreviewData.scope(
        MaterialApp(theme: AppTheme.lightTheme, home: const ReadScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('In den beginne schiep God'), findsOneWidget);
  });
}
