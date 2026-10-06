import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/present/auth_controller.dart';

/// What the "Tekst van de dag" card paints behind the verse. The order is the
/// order of the pages the reader swipes through on the card.
enum DailyVerseBackground {
  /// The day's nature photo (`assets/images/daytext/`), the default.
  photo,

  /// The reader's own progress tree.
  tree,
}

/// The reader's chosen background, remembered on the device per account so
/// two people sharing a phone do not overwrite each other's choice.
final dailyVerseBackgroundProvider =
    NotifierProvider<DailyVerseBackgroundStore, DailyVerseBackground>(
      DailyVerseBackgroundStore.new,
    );

/// Key prefix in SharedPreferences; the account id follows after a dot.
const kDailyVerseBackgroundKey = 'daytext.background';

class DailyVerseBackgroundStore extends Notifier<DailyVerseBackground> {
  String _key = kDailyVerseBackgroundKey;

  @override
  DailyVerseBackground build() {
    // Rebuilds on sign-in, sign-out and account switch, so each account
    // reads its own choice.
    final userId = ref.watch(
      authControllerProvider.select((auth) => auth.value?.id),
    );
    _key = userId == null || userId.isEmpty
        ? kDailyVerseBackgroundKey
        : '$kDailyVerseBackgroundKey.$userId';
    _load(_key);
    return DailyVerseBackground.photo;
  }

  Future<void> _load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted || key != _key) return;
      final stored = prefs.getString(key);
      // 'landscape' was the painted scene this page showed before the photos.
      if (stored == 'landscape') {
        state = DailyVerseBackground.photo;
        return;
      }
      for (final value in DailyVerseBackground.values) {
        if (value.name == stored) state = value;
      }
    } catch (_) {
      // No preferences plugin: the default, for this session only.
    }
  }

  Future<void> select(DailyVerseBackground value) async {
    if (state == value) return;
    state = value;
    final key = _key;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value.name);
    } catch (_) {
      // Kept in memory; the next launch falls back to the default.
    }
  }
}
