import 'package:bijbelstudie_mobile/core/theme/app_theme.dart';
import 'package:bijbelstudie_mobile/core/ui/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for "switching the theme leaves the settings titles in the
/// old colour until you leave the screen and come back".
///
/// main.dart keys `MaterialApp.router` on the brightness so a theme switch
/// discards the whole subtree. go_router's Navigator carries a GlobalKey,
/// though, so the framework reparents the deactivated Navigator - routes and
/// all - into the new MaterialApp instead of destroying it. On reactivation
/// only elements with inherited dependencies get `didChangeDependencies()`;
/// a const-constructed widget whose build reads only `AppTheme` statics has
/// none, is handed the identical const instance by its rebuilt parent, and is
/// never rebuilt. This harness reproduces exactly that structure.
class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  /// Fixed across rebuilds, like the key go_router allocates for its Navigator.
  final navigatorKey = GlobalKey<NavigatorState>();
  Brightness brightness = Brightness.light;

  void switchTo(Brightness value) => setState(() => brightness = value);

  @override
  Widget build(BuildContext context) {
    // Same order as main.dart: repoint the tokens, then rebuild the keyed app.
    AppTheme.applyBrightness(brightness);
    return MaterialApp(
      key: ValueKey(brightness),
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: Navigator(
        key: navigatorKey,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          // Const on purpose: this is how screens construct their headers.
          builder: (_) => const Scaffold(body: SectionHeader(title: 'Thema')),
        ),
      ),
    );
  }
}

void main() {
  tearDown(() => AppTheme.applyBrightness(Brightness.light));

  testWidgets('a const SectionHeader takes the new ink colour after a keyed theme switch',
      (tester) async {
    await tester.pumpWidget(const _Harness());
    final harness = tester.state<_HarnessState>(find.byType(_Harness));
    Color? titleColor() => tester.widget<Text>(find.text('Thema')).style?.color;

    expect(titleColor(), AppTheme.lightInk);
    final navigatorBefore = harness.navigatorKey.currentState;
    expect(navigatorBefore, isNotNull);

    harness.switchTo(Brightness.dark);
    await tester.pumpAndSettle();

    // The GlobalKey made the framework reparent the Navigator rather than
    // recreate it - the very thing that keeps the stale elements alive.
    expect(harness.navigatorKey.currentState, same(navigatorBefore),
        reason: 'the keyed MaterialApp should reparent, not recreate, the Navigator');
    expect(titleColor(), AppTheme.darkInk,
        reason: 'the section title must repaint with the dark ink token');
  });
}
