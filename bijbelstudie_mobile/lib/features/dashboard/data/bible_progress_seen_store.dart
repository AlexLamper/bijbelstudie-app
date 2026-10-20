import 'package:shared_preferences/shared_preferences.dart';

/// The share of the Bible the "Je Bijbel" card last showed this reader, so it
/// can tell a milestone crossed since then from one passed long ago. Kept on
/// the device per account, like the verse card's background choice.
class BibleProgressSeenStore {
  const BibleProgressSeenStore._();

  /// Key prefix in SharedPreferences; the account id follows after a dot.
  static const kKey = 'home.bibleProgress.lastSeen';

  static String _key(String? userId) =>
      userId == null || userId.isEmpty ? kKey : '$kKey.$userId';

  /// The last percentage shown (0-100), or null when the card never showed.
  static Future<double?> read(String? userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_key(userId));
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String? userId, double percent) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_key(userId), percent);
    } catch (_) {
      // No preferences plugin: the next launch treats the card as new.
    }
  }
}
