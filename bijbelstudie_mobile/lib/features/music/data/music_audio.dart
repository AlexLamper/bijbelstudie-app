import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The one platform player behind background music, kept behind an interface
/// so `MusicPlayerController` can be tested without a platform channel.
abstract class MusicAudio {
  /// Starts [asset] from the beginning, looping, at [volume].
  Future<void> start(String asset, {required double volume});

  /// Swaps the source under a playing player without touching its state.
  Future<void> switchTo(String asset);

  Future<void> pause();
  Future<void> resume();

  /// Stops and releases the source.
  Future<void> stop();
  Future<void> setVolume(double volume);

  /// Where the player is, or null when it cannot say. Used to notice that the
  /// platform paused us behind our back (a phone call on iOS).
  Future<Duration?> position();

  Future<void> dispose();
}

/// Whether background music holds the audio session right now.
///
/// On iOS the AVAudioSession is shared by every player in the process, so the
/// level-up chime's "ambient, respect the silent switch" context would take the
/// session away from music that is playing - and with it, playback behind a
/// locked screen. The chime checks this and leaves the session alone.
abstract final class MusicAudioSession {
  static bool inUse = false;
}

class AudioplayersMusicAudio implements MusicAudio {
  AudioPlayer? _player;

  /// Music the reader chose to hear: the `playback` category, so it plays with
  /// the ringer off and keeps going with the screen locked (`UIBackgroundModes:
  /// audio` in Info.plist), and not mixed with other apps. On Android a full
  /// audio-focus request: another app taking focus, or a call, pauses us, and
  /// a transient loss resumes on its own (audioplayers' FocusManager). The
  /// wake lock (`stayAwake`, WAKE_LOCK in the manifest) keeps the CPU up while
  /// the screen is off.
  static final AudioContext _context = AudioContext(
    iOS: AudioContextIOS(category: AVAudioSessionCategory.playback, options: const {}),
    android: const AudioContextAndroid(
      stayAwake: true,
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gain,
    ),
  );

  Future<AudioPlayer> _ensure() async {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer(playerId: 'background_music');
    await player.setReleaseMode(ReleaseMode.loop);
    return _player = player;
  }

  @override
  Future<void> start(String asset, {required double volume}) async {
    final player = await _ensure();
    // Every start, not once: the chime or another player may have changed the
    // shared session since.
    await player.setAudioContext(_context);
    MusicAudioSession.inUse = true;
    await player.stop();
    await player.play(AssetSource(asset), volume: volume);
  }

  @override
  Future<void> switchTo(String asset) async {
    final player = await _ensure();
    await player.setSource(AssetSource(asset));
    await player.resume();
  }

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> resume() async {
    final player = _player;
    if (player == null) return;
    await player.setAudioContext(_context);
    MusicAudioSession.inUse = true;
    await player.resume();
  }

  @override
  Future<void> stop() async {
    MusicAudioSession.inUse = false;
    await _player?.stop();
  }

  @override
  Future<void> setVolume(double volume) async => _player?.setVolume(volume);

  @override
  Future<Duration?> position() async => _player?.getCurrentPosition();

  @override
  Future<void> dispose() async {
    MusicAudioSession.inUse = false;
    await _player?.dispose();
    _player = null;
  }
}

final musicAudioProvider = Provider<MusicAudio>((ref) {
  final audio = AudioplayersMusicAudio();
  ref.onDispose(audio.dispose);
  return audio;
});
