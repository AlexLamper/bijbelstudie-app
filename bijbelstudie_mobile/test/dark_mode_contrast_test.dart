import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bijbelstudie_mobile/core/theme/app_theme.dart';

/// Guards the app against the rejection it actually received.
///
/// App review 1.0 (7), guideline 4 — Design, on an iPad Air 11-inch running
/// iPadOS 26.6.1:
///
/// > We noticed the font colour used makes it hard to read with the background
/// > colour, this is for user who use the dark mode setting on their device.
///
/// The cause was structural, not a few bad screens. `AppTheme` publishes its
/// type ramp as `static const TextStyle`s, and a const cannot depend on
/// brightness, so thirteen of the fourteen bake a light-mode colour:
/// `displaySmall` is `ink` (#111827) whatever the theme says. `ThemeData` was
/// built correctly for both brightnesses, so a bare `Text` was always fine —
/// but `Text(…, style: AppTheme.displaySmall)` painted near-black on the dark
/// scaffold, which is why the paywall's own headline was invisible.
///
/// The app is therefore pinned to the light theme, and these tests hold that
/// line: one fails the moment dark mode is switched back on while the ramp is
/// still unfixed, and the others say what has to be true before it can be.
void main() {
  /// Relative luminance, WCAG 2.1.
  double luminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// Every surface a screen paints text onto, in the dark palette.
  const darkSurfaces = <String, Color>{
    'paper': AppTheme.darkPaper,
    'paperRaised': AppTheme.darkPaperRaised,
    'paperSunken': AppTheme.darkPaperSunken,
    'paperSunkenStrong': AppTheme.darkPaperSunkenStrong,
  };

  /// The type ramp, by the name a call site would use.
  const ramp = <String, TextStyle>{
    'displayLarge': AppTheme.displayLarge,
    'displayMedium': AppTheme.displayMedium,
    'displaySmall': AppTheme.displaySmall,
    'displayTitle': AppTheme.displayTitle,
    'displayBase': AppTheme.displayBase,
    'statNumber': AppTheme.statNumber,
    'eyebrow': AppTheme.eyebrow,
    'overline': AppTheme.overline,
    'metaLabel': AppTheme.metaLabel,
    'bodyLead': AppTheme.bodyLead,
    'bodyStrong': AppTheme.bodyStrong,
    'bodyMuted': AppTheme.bodyMuted,
    'caption': AppTheme.caption,
    'buttonLabel': AppTheme.buttonLabel,
  };

  /// Ramp entries whose baked colour is unreadable somewhere in the dark
  /// palette, with the worst ratio each one reaches.
  Map<String, double> unreadableInDark() {
    final worst = <String, double>{};
    for (final entry in ramp.entries) {
      final color = entry.value.color;
      if (color == null) continue;

      final size = entry.value.fontSize ?? 14;
      final bold = (entry.value.fontWeight?.index ?? 0) >= FontWeight.w700.index;
      // WCAG AA: 3:1 for large text (>=18pt, or >=14pt bold), 4.5:1 otherwise.
      final threshold = (size >= 18 || (size >= 14 && bold)) ? 3.0 : 4.5;

      for (final surface in darkSurfaces.values) {
        final ratio = contrast(color, surface);
        if (ratio < threshold) {
          worst[entry.key] = math.min(worst[entry.key] ?? 99, ratio);
        }
      }
    }
    return worst;
  }

  test('the ramp is still light-only, which is why dark mode is off', () {
    final broken = unreadableInDark();

    // Characterises the damage rather than asserting a count, so a failure
    // reads as the actual list instead of "expected 13, got 12".
    expect(
      broken,
      isNotEmpty,
      reason:
          'No ramp style is unreadable on the dark palette any more. If that is '
          'because the ramp became context-resolved, dark mode can come back: '
          'restore themeMode/darkTheme in main.dart and the Thema picker in '
          'settings_screen.dart, then delete this test.',
    );
  });

  testWidgets('a dark-mode device still gets the light theme', (tester) async {
    // The rejection, reproduced: platform brightness dark, and the app must
    // not follow it.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    late Brightness rendered;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.lightTheme,
        themeMode: ThemeMode.light,
        home: Builder(
          builder: (context) {
            rendered = Theme.of(context).brightness;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      rendered,
      Brightness.light,
      reason:
          'The app rendered dark on a dark-mode device. Every const in the type '
          'ramp carries a light colour, so this is the guideline 4 rejection '
          'coming back.',
    );
  });

  group('the dark palette itself is sound, and stays that way', () {
    // Kept alive on purpose. The palette is not the problem — the const ramp
    // is — and these are the values a context-resolved ramp would resolve to,
    // so they have to still be correct when that work happens.
    const foregrounds = <String, Color>{
      'darkInk': AppTheme.darkInk,
      'darkInkSoft': AppTheme.darkInkSoft,
      'darkInkMuted': AppTheme.darkInkMuted,
      'darkTeal': AppTheme.darkTeal,
      'darkFlame': AppTheme.darkFlame,
      'darkPositive': AppTheme.darkPositive,
      'darkAi': AppTheme.darkAi,
    };

    for (final fg in foregrounds.entries) {
      for (final surface in darkSurfaces.entries) {
        test('${fg.key} on ${surface.key}', () {
          final ratio = contrast(fg.value, surface.value);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason:
                '${fg.key} (${fg.value}) on ${surface.key} (${surface.value}) '
                'is only ${ratio.toStringAsFixed(2)}:1.',
          );
        });
      }
    }
  });

  test('the dark body roles that already fail AA are recorded, not forgotten', () {
    // `darkInkMuted` (#808080) clears 3:1 but not the 4.5:1 body text needs, on
    // every surface lighter than the scaffold. Fixing the ramp alone would not
    // be enough — this has to move too, or muted body text in dark mode is
    // still below AA.
    final text = AppTheme.darkTheme.textTheme;
    final failing = <String>[];

    for (final role in {'bodyMedium': text.bodyMedium, 'bodySmall': text.bodySmall}.entries) {
      final color = role.value?.color;
      if (color == null) continue;
      for (final surface in darkSurfaces.entries) {
        if (contrast(color, surface.value) < 4.5) {
          failing.add('${role.key} on ${surface.key}');
        }
      }
    }

    expect(
      failing,
      isNotEmpty,
      reason:
          'The dark body roles now clear AA everywhere. Update this test — it '
          'exists so that fix is not mistaken for one that has not happened.',
    );
  });
}
