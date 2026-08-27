import 'dart:async';

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

extension ReaderLineHeightSyncX on ReaderLineHeight {
  /// The id to send to `/preferences`.
  ///
  /// The website only knows `normal`/`relaxed`/`loose` (`lib/preferenceClasses.ts`)
  /// and silently falls back to `relaxed` for anything else — so syncing our
  /// extra `snug` step would turn the reader's tightest setting into its
  /// second-loosest in the browser. `normal` is the closest thing the website
  /// can actually render.
  String get syncId => this == ReaderLineHeight.snug ? 'normal' : id;
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
    this.lastBook,
    this.lastChapter,
    this.lastLocationAt,
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

  /// Where the reader was last left. Null until the first chapter is opened,
  /// which is the only case where Genesis 1 is still the right place to land.
  final String? lastBook;
  final int? lastChapter;

  /// When [lastBook]/[lastChapter] were written, so the reader can tell this
  /// copy apart from the server's on a device that has both. Null for a device
  /// that stored a location before this was recorded.
  final DateTime? lastLocationAt;

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
    String? lastBook,
    int? lastChapter,
    DateTime? lastLocationAt,
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
      lastBook: lastBook ?? this.lastBook,
      lastChapter: lastChapter ?? this.lastChapter,
      lastLocationAt: lastLocationAt ?? this.lastLocationAt,
    );
  }
}

const _kFontSize = 'reader.fontSize';
const _kLineHeight = 'reader.lineHeight';
const _kFontFamily = 'reader.fontFamily';
const _kVerseNumbers = 'reader.showVerseNumbers';
const _kThemeMode = 'app.themeMode';

/// Public so main.dart can re-apply a stored reminder at startup, before the
/// widget tree (and therefore [readingSettingsProvider]) exists to read it.
const kDailyReminderMinutesKey = 'app.dailyReminderMinutes';
const _kReminder = kDailyReminderMinutesKey;
const _kLastVersion = 'reader.lastVersionId';
const _kLastCommentary = 'reader.lastCommentaryId';
const _kLastBook = 'reader.lastBook';
const _kLastChapter = 'reader.lastChapter';
const _kLastLocationAt = 'reader.lastLocationAt';

final readingSettingsProvider =
    NotifierProvider<ReadingSettingsController, ReadingSettings>(
      ReadingSettingsController.new,
    );

class ReadingSettingsController extends Notifier<ReadingSettings> {
  final Completer<void> _loaded = Completer<void>();

  /// True once any setter has run. The disk read in [build] is asynchronous,
  /// so without this a choice made while it is still in flight - the setup
  /// wizard's first screen is often what triggers the read in the first place
  /// - would be silently overwritten by the stored value a moment later.
  bool _written = false;

  /// Completes once the first read from disk is done, successfully or not.
  ///
  /// [build] returns the defaults and fills them in a moment later, so anything
  /// that must not act on the defaults - the reader deciding which chapter to
  /// paint - awaits this instead of racing the notifier's state.
  Future<void> get loaded => _loaded.future;

  @override
  ReadingSettings build() {
    _load();
    return const ReadingSettings();
  }

  Future<void> _load() async {
    try {
      await _readInto();
    } catch (_) {
      // No preferences plugin (tests, an unusual platform): the defaults stand.
      // The completer must still fire or every awaiting caller hangs forever.
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  Future<void> _readInto() async {
    final prefs = await SharedPreferences.getInstance();
    // A setter beat the disk read. Whatever it wrote is both newer and already
    // persisted, so replaying the stored snapshot over it would undo a choice
    // the user has just watched take effect.
    if (_written) return;
    final storedAt = prefs.getInt(_kLastLocationAt);
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
      lastBook: prefs.getString(_kLastBook),
      lastChapter: prefs.getInt(_kLastChapter),
      lastLocationAt: storedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(storedAt),
    );
  }

  Future<void> setFontSize(ReaderFontSize value) async {
    _written = true;
    state = state.copyWith(fontSize: value);
    (await SharedPreferences.getInstance()).setString(_kFontSize, value.id);
  }

  Future<void> setLineHeight(ReaderLineHeight value) async {
    _written = true;
    state = state.copyWith(lineHeight: value);
    (await SharedPreferences.getInstance()).setString(_kLineHeight, value.id);
  }

  Future<void> setFontFamily(ReaderFontFamily value) async {
    _written = true;
    state = state.copyWith(fontFamily: value);
    (await SharedPreferences.getInstance()).setString(_kFontFamily, value.id);
  }

  Future<void> setShowVerseNumbers(bool value) async {
    _written = true;
    state = state.copyWith(showVerseNumbers: value);
    (await SharedPreferences.getInstance()).setBool(_kVerseNumbers, value);
  }

  Future<void> setThemeMode(ThemeMode value) async {
    _written = true;
    state = state.copyWith(themeMode: value);
    final id = switch (value) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    (await SharedPreferences.getInstance()).setString(_kThemeMode, id);
  }

  Future<void> setDailyReminder(int? minutesPastMidnight) async {
    _written = true;
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
    _written = true;
    if (state.lastVersionId == versionId) return;
    state = state.copyWith(lastVersionId: versionId);
    (await SharedPreferences.getInstance()).setString(_kLastVersion, versionId);
  }

  Future<void> setLastCommentary(String commentaryId) async {
    _written = true;
    if (state.lastCommentaryId == commentaryId) return;
    state = state.copyWith(lastCommentaryId: commentaryId);
    (await SharedPreferences.getInstance()).setString(_kLastCommentary, commentaryId);
  }

  /// Remembers where the reader was, so reopening the app lands there rather
  /// than back at Genesis 1.
  ///
  /// The timestamp is what lets the reader compare this copy with the server's
  /// on a device that has both, so it is refreshed even when the chapter has
  /// not changed.
  Future<void> setLastLocation({required String book, required int chapter}) async {
    _written = true;
    final now = DateTime.now();
    state = state.copyWith(lastBook: book, lastChapter: chapter, lastLocationAt: now);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastBook, book);
    await prefs.setInt(_kLastChapter, chapter);
    await prefs.setInt(_kLastLocationAt, now.millisecondsSinceEpoch);
  }
}
