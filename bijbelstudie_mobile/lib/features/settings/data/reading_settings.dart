import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reader typography and app theme, persisted on the device.
///
/// The scale values match `lib/preferenceClasses.ts` on the website so the same
/// choice reads the same in both places. They are stored locally rather than
/// only on the server because the reader must be fully usable offline,
/// including its settings.
enum ReaderFontSize { small, base, large, xlarge }

enum ReaderLineHeight { snug, normal, relaxed, loose }

enum ReaderFontFamily { sans, serif, mono }

extension ReaderFontSizeX on ReaderFontSize {
  String get id => switch (this) {
    ReaderFontSize.small => 'sm',
    ReaderFontSize.base => 'base',
    ReaderFontSize.large => 'lg',
    ReaderFontSize.xlarge => 'xl',
  };

  String get label => switch (this) {
    ReaderFontSize.small => 'Klein',
    ReaderFontSize.base => 'Normaal',
    ReaderFontSize.large => 'Groot',
    ReaderFontSize.xlarge => 'Extra groot',
  };

  double get points => switch (this) {
    ReaderFontSize.small => 15,
    ReaderFontSize.base => 17,
    ReaderFontSize.large => 20,
    ReaderFontSize.xlarge => 23,
  };

  static ReaderFontSize fromId(String? id) => ReaderFontSize.values.firstWhere(
    (v) => v.id == id,
    orElse: () => ReaderFontSize.base,
  );
}

extension ReaderLineHeightX on ReaderLineHeight {
  String get id => switch (this) {
    ReaderLineHeight.snug => 'snug',
    ReaderLineHeight.normal => 'normal',
    ReaderLineHeight.relaxed => 'relaxed',
    ReaderLineHeight.loose => 'loose',
  };

  String get label => switch (this) {
    ReaderLineHeight.snug => 'Compact',
    ReaderLineHeight.normal => 'Normaal',
    ReaderLineHeight.relaxed => 'Ruim',
    ReaderLineHeight.loose => 'Zeer ruim',
  };

  double get factor => switch (this) {
    ReaderLineHeight.snug => 1.4,
    ReaderLineHeight.normal => 1.6,
    ReaderLineHeight.relaxed => 1.8,
    ReaderLineHeight.loose => 2.05,
  };

  static ReaderLineHeight fromId(String? id) => ReaderLineHeight.values.firstWhere(
    (v) => v.id == id,
    orElse: () => ReaderLineHeight.relaxed,
  );
}

extension ReaderFontFamilyX on ReaderFontFamily {
  String get id => switch (this) {
    ReaderFontFamily.sans => 'sans',
    ReaderFontFamily.serif => 'serif',
    ReaderFontFamily.mono => 'mono',
  };

  String get label => switch (this) {
    ReaderFontFamily.sans => 'Schreefloos',
    ReaderFontFamily.serif => 'Schreef',
    ReaderFontFamily.mono => 'Monospace',
  };

  /// The families the website loads for `font-sans` / `font-serif` /
  /// `font-mono` (`app/layout.tsx`, `tailwind.config.ts`).
  String get fontName => switch (this) {
    ReaderFontFamily.sans => 'Inter',
    ReaderFontFamily.serif => 'Lora',
    ReaderFontFamily.mono => 'Geist Mono',
  };

  static ReaderFontFamily fromId(String? id) => switch (id) {
    'serif' => ReaderFontFamily.serif,
    'mono' => ReaderFontFamily.mono,
    _ => ReaderFontFamily.sans,
  };
}

class ReadingSettings {
  const ReadingSettings({
    this.fontSize = ReaderFontSize.base,
    this.lineHeight = ReaderLineHeight.relaxed,
    this.fontFamily = ReaderFontFamily.sans,
    this.showVerseNumbers = true,
    this.themeMode = ThemeMode.system,
    this.dailyReminderMinutes,
    this.lastVersionId = 'statenvertaling',
    this.lastCommentaryId = 'matthew_henry_nl',
  });

  final ReaderFontSize fontSize;
  final ReaderLineHeight lineHeight;
  final ReaderFontFamily fontFamily;
  final bool showVerseNumbers;
  final ThemeMode themeMode;

  /// Minutes past midnight for the daily reading reminder, or null when off.
  final int? dailyReminderMinutes;

  final String lastVersionId;
  final String lastCommentaryId;

  TimeOfDay? get dailyReminderTime => dailyReminderMinutes == null
      ? null
      : TimeOfDay(hour: dailyReminderMinutes! ~/ 60, minute: dailyReminderMinutes! % 60);

  ReadingSettings copyWith({
    ReaderFontSize? fontSize,
    ReaderLineHeight? lineHeight,
    ReaderFontFamily? fontFamily,
    bool? showVerseNumbers,
    ThemeMode? themeMode,
    int? dailyReminderMinutes,
    bool clearReminder = false,
    String? lastVersionId,
    String? lastCommentaryId,
  }) {
    return ReadingSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      showVerseNumbers: showVerseNumbers ?? this.showVerseNumbers,
      themeMode: themeMode ?? this.themeMode,
      dailyReminderMinutes:
          clearReminder ? null : (dailyReminderMinutes ?? this.dailyReminderMinutes),
      lastVersionId: lastVersionId ?? this.lastVersionId,
      lastCommentaryId: lastCommentaryId ?? this.lastCommentaryId,
    );
  }
}

const _kFontSize = 'reader.fontSize';
const _kLineHeight = 'reader.lineHeight';
const _kFontFamily = 'reader.fontFamily';
const _kVerseNumbers = 'reader.showVerseNumbers';
const _kThemeMode = 'app.themeMode';
const _kReminder = 'app.dailyReminderMinutes';
const _kLastVersion = 'reader.lastVersionId';
const _kLastCommentary = 'reader.lastCommentaryId';

final readingSettingsProvider =
    NotifierProvider<ReadingSettingsController, ReadingSettings>(
      ReadingSettingsController.new,
    );

class ReadingSettingsController extends Notifier<ReadingSettings> {
  @override
  ReadingSettings build() {
    _load();
    return const ReadingSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ReadingSettings(
      fontSize: ReaderFontSizeX.fromId(prefs.getString(_kFontSize)),
      lineHeight: ReaderLineHeightX.fromId(prefs.getString(_kLineHeight)),
      fontFamily: ReaderFontFamilyX.fromId(prefs.getString(_kFontFamily)),
      showVerseNumbers: prefs.getBool(_kVerseNumbers) ?? true,
      themeMode: switch (prefs.getString(_kThemeMode)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      dailyReminderMinutes: prefs.getInt(_kReminder),
      lastVersionId: prefs.getString(_kLastVersion) ?? 'statenvertaling',
      lastCommentaryId: prefs.getString(_kLastCommentary) ?? 'matthew_henry_nl',
    );
  }

  Future<void> setFontSize(ReaderFontSize value) async {
    state = state.copyWith(fontSize: value);
    (await SharedPreferences.getInstance()).setString(_kFontSize, value.id);
  }

  Future<void> setLineHeight(ReaderLineHeight value) async {
    state = state.copyWith(lineHeight: value);
    (await SharedPreferences.getInstance()).setString(_kLineHeight, value.id);
  }

  Future<void> setFontFamily(ReaderFontFamily value) async {
    state = state.copyWith(fontFamily: value);
    (await SharedPreferences.getInstance()).setString(_kFontFamily, value.id);
  }

  Future<void> setShowVerseNumbers(bool value) async {
    state = state.copyWith(showVerseNumbers: value);
    (await SharedPreferences.getInstance()).setBool(_kVerseNumbers, value);
  }

  Future<void> setThemeMode(ThemeMode value) async {
    state = state.copyWith(themeMode: value);
    final id = switch (value) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    (await SharedPreferences.getInstance()).setString(_kThemeMode, id);
  }

  Future<void> setDailyReminder(int? minutesPastMidnight) async {
    state = state.copyWith(
      dailyReminderMinutes: minutesPastMidnight,
      clearReminder: minutesPastMidnight == null,
    );
    final prefs = await SharedPreferences.getInstance();
    if (minutesPastMidnight == null) {
      await prefs.remove(_kReminder);
    } else {
      await prefs.setInt(_kReminder, minutesPastMidnight);
    }
  }

  Future<void> setLastVersion(String versionId) async {
    if (state.lastVersionId == versionId) return;
    state = state.copyWith(lastVersionId: versionId);
    (await SharedPreferences.getInstance()).setString(_kLastVersion, versionId);
  }

  Future<void> setLastCommentary(String commentaryId) async {
    if (state.lastCommentaryId == commentaryId) return;
    state = state.copyWith(lastCommentaryId: commentaryId);
    (await SharedPreferences.getInstance()).setString(_kLastCommentary, commentaryId);
  }
}
