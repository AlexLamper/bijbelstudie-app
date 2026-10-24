import 'package:shared_preferences/shared_preferences.dart';

/// The three things about background music that survive a restart: the
/// volume, the last track (for "Laatst") and whether the swipe hint has been
/// seen. Device-wide rather than per account - they are about this phone and
/// these ears. Playback itself never resumes on launch.
class MusicPrefs {
  const MusicPrefs({this.volume, this.lastTrackId, this.hintSeen = false});

  static const _volumeKey = 'music.volume';
  static const _lastTrackKey = 'music.lastTrack';
  static const _hintSeenKey = 'music.hintSeen';

  final double? volume;
  final String? lastTrackId;
  final bool hintSeen;

  static Future<MusicPrefs> load() async {
    final prefs = await SharedPreferences.getInstance();
    return MusicPrefs(
      volume: prefs.getDouble(_volumeKey),
      lastTrackId: prefs.getString(_lastTrackKey),
      hintSeen: prefs.getBool(_hintSeenKey) ?? false,
    );
  }

  static Future<void> saveVolume(double volume) async =>
      (await SharedPreferences.getInstance()).setDouble(_volumeKey, volume);

  static Future<void> saveLastTrack(String id) async =>
      (await SharedPreferences.getInstance()).setString(_lastTrackKey, id);

  static Future<void> saveHintSeen() async =>
      (await SharedPreferences.getInstance()).setBool(_hintSeenKey, true);
}
