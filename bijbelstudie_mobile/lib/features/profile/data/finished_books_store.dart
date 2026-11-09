import 'package:shared_preferences/shared_preferences.dart';

/// The books the bookcase last showed as finished, so the page can tell a book
/// finished since the last visit (worth a small celebration) from one finished
/// long ago. Kept on the device per account, like
/// `BibleProgressSeenStore` does for the Start card's milestones.
class FinishedBooksStore {
  const FinishedBooksStore._();

  /// Key prefix in SharedPreferences; the account id follows after a dot.
  static const kKey = 'profile.bookcase.finished';

  static String _key(String? userId) =>
      userId == null || userId.isEmpty ? kKey : '$kKey.$userId';

  /// The finished book names last seen, or null when the case never showed.
  static Future<Set<String>?> read(String? userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_key(userId))?.toSet();
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String? userId, Set<String> books) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key(userId), books.toList()..sort());
    } catch (_) {
      // No preferences plugin: the next visit treats the case as new.
    }
  }
}
