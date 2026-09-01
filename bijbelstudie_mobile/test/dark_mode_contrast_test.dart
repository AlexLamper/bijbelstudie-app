import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bijbelstudie_mobile/core/theme/app_theme.dart';

/// Guards the app against the rejection it actually received.
///
/// App review 1.0 (7), guideline 4 - Design, on an iPad Air 11-inch running
/// iPadOS 26.6.1:
///
/// > We noticed the font colour used makes it hard to read with the background
/// > colour, this is for user who use the dark mode setting on their device.
///
/// The cause was structural, not a few bad screens. `AppTheme` published its
/// type ramp as `static const TextStyle`s, and a const cannot depend on
/// brightness, so thirteen of the fourteen baked a light-mode colour:
/// `displaySmall` was `ink` (#111827) whatever the theme said. The ramp and
/// the semantic palette are brightness-resolved getters now, fed by
/// [AppTheme.applyBrightness] from the root widget in main.dart, and dark mode
/// is back on.
///
/// These tests are what keeps it shippable: every ramp style, resolved in dark
/// brightness, has to clear WCAG AA against every surface a screen paints on.
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

  /// WCAG AA: 3:1 for large text (>=18pt, or >=14pt bold), 4.5:1 otherwise.
  double thresholdFor(TextStyle style) {
    final size = style.fontSize ?? 14;
    final bold = (style.fontWeight?.index ?? 0) >= FontWeight.w700.index;
    return (size >= 18 || (size >= 14 && bold)) ? 3.0 : 4.5;
  }

  /// Every surface a screen paints text onto, in the dark palette.
  const darkSurfaces = <String, Color>{
    'paper': AppTheme.darkPaper,
    'paperRaised': AppTheme.darkPaperRaised,
    'paperSunken': AppTheme.darkPaperSunken,
    'paperSunkenStrong': AppTheme.darkPaperSunkenStrong,
  };

  /// The type ramp, by the name a call site would use, resolved against the
  /// brightness that is current when this runs.
  Map<String, TextStyle> ramp() => <String, TextStyle>{
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

  // The flag is process-wide, so every test here puts it back. A test file
  // that leaked dark brightness would quietly recolour the render tests.
  setUp(() => AppTheme.applyBrightness(Brightness.dark));
  tearDown(() => AppTheme.applyBrightness(Brightness.light));

  test('the ramp resolves against brightness rather than baking a colour', () {
    AppTheme.applyBrightness(Brightness.light);
    final light = ramp();
    AppTheme.applyBrightness(Brightness.dark);
    final dark = ramp();

    final unchanged = <String>[];
    for (final entry in dark.entries) {
      if (entry.value.color == null) continue; // buttonLabel inherits.
      if (entry.value.color == light[entry.key]!.color) {
        unchanged.add(entry.key);
      }
    }

    expect(
      unchanged,
      isEmpty,
      reason:
          'These ramp styles paint the same colour in both brightnesses, so '
          'they are back to being light-only: $unchanged. That is the '
          'guideline 4 rejection.',
    );
  });

  group('every ramp style clears AA on every dark surface', () {
    for (final name in ramp().keys) {
      for (final surface in darkSurfaces.entries) {
        test('$name on ${surface.key}', () {
          final style = ramp()[name]!;
          final color = style.color;
          if (color == null) return; // Inherits from the ThemeData role.

          final threshold = thresholdFor(style);
          final ratio = contrast(color, surface.value);
          expect(
            ratio,
            greaterThanOrEqualTo(threshold),
            reason:
                '$name ($color, ${style.fontSize}pt ${style.fontWeight}) on '
                '${surface.key} (${surface.value}) is only '
                '${ratio.toStringAsFixed(2)}:1, below $threshold:1. Move the '
                'dark palette value - never the threshold.',
          );
        });
      }
    }
  });

  testWidgets('a dark-mode device gets the dark theme', (tester) async {
    // The rejection, reproduced: platform brightness dark. main.dart passes
    // the stored ThemeMode straight through, so `system` is what a device
    // that has never been asked resolves with.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    late ThemeData rendered;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: Builder(
          builder: (context) {
            rendered = Theme.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(rendered.brightness, Brightness.dark);
    expect(rendered.scaffoldBackgroundColor, AppTheme.darkPaper);
  });

  group('the dark palette itself is sound, and stays that way', () {
    const foregrounds = <String, Color>{
      'darkInk': AppTheme.darkInk,
      'darkInkSoft': AppTheme.darkInkSoft,
      'darkInkMuted': AppTheme.darkInkMuted,
      'darkInkFaint': AppTheme.darkInkFaint,
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

  test('the dark body roles clear AA, not just the large-text ratio', () {
    // `--muted-foreground` on the website is #808080, which clears 3:1 but not
    // the 4.5:1 body text needs on #333333. The app deliberately runs a
    // lighter value; this is what stops it drifting back.
    final text = AppTheme.darkTheme.textTheme;
    final failing = <String>[];

    for (final role in {
      'bodyLarge': text.bodyLarge,
      'bodyMedium': text.bodyMedium,
      'bodySmall': text.bodySmall,
      'labelMedium': text.labelMedium,
      'labelSmall': text.labelSmall,
    }.entries) {
      final color = role.value?.color;
      if (color == null) continue;
      for (final surface in darkSurfaces.entries) {
        final ratio = contrast(color, surface.value);
        if (ratio < 4.5) {
          failing.add(
            '${role.key} on ${surface.key} (${ratio.toStringAsFixed(2)}:1)',
          );
        }
      }
    }

    expect(failing, isEmpty, reason: 'Below AA in dark mode: $failing');
  });
}
