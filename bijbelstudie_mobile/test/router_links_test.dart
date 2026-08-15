import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bijbelstudie_mobile/core/router/app_router.dart';

/// Every literal destination in the app has to resolve to a registered route.
///
/// App review 1.0(5) was rejected under guideline 2.1(a) because it did not:
/// four call sites navigated to `/home`, which the router never declared, so
/// registering an account landed on go_router's error page with no way out.
/// A route rename is invisible to the compiler, so this is the only thing that
/// catches the next one.
void main() {
  final container = ProviderContainer();
  final router = container.read(routerProvider);
  tearDownAll(container.dispose);

  /// `context.go('/x')`, `.push`, `.replace`, `.pushReplacement` — literal
  /// single-quoted paths only. Anything interpolated is skipped: the test can
  /// only judge what it can read statically.
  final call = RegExp(
    r"""context\.(?:go|push|replace|pushReplacement)\(\s*'(/[^'$]*)'""",
  );

  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  final destinations = <String, List<String>>{};
  for (final file in dartFiles) {
    for (final match in call.allMatches(file.readAsStringSync())) {
      destinations.putIfAbsent(match.group(1)!, () => []).add(file.path);
    }
  }

  test('the scan actually found the navigation calls', () {
    // Guards against the regex silently matching nothing after a refactor,
    // which would turn every assertion below into a no-op.
    expect(destinations, isNotEmpty);
  });

  group('every navigation target resolves', () {
    for (final entry in destinations.entries) {
      test(entry.key, () {
        final match = router.configuration.findMatch(Uri.parse(entry.key));
        expect(
          match.isError,
          isFalse,
          reason:
              'No route is registered for "${entry.key}", navigated to from:\n'
              '  ${entry.value.join('\n  ')}\n'
              'Add the route, or point the call at an existing one.',
        );
      });
    }
  });

  test('/home is still registered, for links persisted by older builds', () {
    // `findMatch` resolves the route table only — redirects run later, during
    // navigation — so this asserts the part that actually broke: `/home` no
    // longer falls through to the error page.
    expect(router.configuration.findMatch(Uri.parse('/home')).isError, isFalse);
  });
}
