import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/reading_settings.dart';

/// The light/dark choice, as stored by [ReadingSettingsController].
///
/// A separate provider rather than a `select` at every call site: the root
/// widget in main.dart watches it to resolve `AppTheme`'s brightness, so it
/// must not rebuild the whole app when an unrelated reading preference
/// changes.
final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(readingSettingsProvider.select((s) => s.themeMode)),
);

extension ThemeModeLabelX on ThemeMode {
  /// Dutch label, used by both the setup wizard and the settings screen.
  String get label => switch (this) {
    ThemeMode.light => 'Licht',
    ThemeMode.dark => 'Donker',
    ThemeMode.system => 'Systeem',
  };

  IconData get icon => switch (this) {
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
    ThemeMode.system => Icons.brightness_auto_outlined,
  };

  /// The order the two explicit choices are offered in, with "follow the
  /// device" last — it is the default, so it reads as the fallback.
  static const List<ThemeMode> pickerOrder = [
    ThemeMode.light,
    ThemeMode.dark,
    ThemeMode.system,
  ];
}
