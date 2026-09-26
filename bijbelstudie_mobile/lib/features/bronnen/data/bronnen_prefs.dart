import 'package:shared_preferences/shared_preferences.dart';

/// The two small Bronnen preferences: where the reader was in each work, and
/// whether every Scripture reference opens with its text.
class BronnenPrefs {
  const BronnenPrefs._();

  static const expandAllKey = 'bronnen.expandRefs';
  static String positionKey(String slug) => 'bronnen.position.$slug';

  static Future<String?> position(String slug) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(positionKey(slug));
    } catch (_) {
      return null;
    }
  }

  static Future<void> setPosition(String slug, String sectionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(positionKey(slug), sectionId);
    } catch (_) {
      // Not remembering a page is harmless.
    }
  }

  static Future<bool> expandAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(expandAllKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setExpandAll(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(expandAllKey, value);
    } catch (_) {
      // The toggle still works for this session.
    }
  }
}
