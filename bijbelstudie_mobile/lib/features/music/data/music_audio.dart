import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The one platform player behind background music, kept behind an interface
/// so `MusicPlayerController` can be tested without a platform channel.
///
/// A source is an asset path relative to `assets/` or an https URL. [start]
/// and [switchTo] throw when the source cannot be loaded (a streamed track
/// with no connection), so the controller can fall back.
abstract class MusicAudio {
  /// Starts [source] from the beginning at [volume]. It plays once; the end
  /// arrives on [completions].
  Future<void> start(String source, {required double volume});

  /// Swaps the source under a playing player without touching its state.
  Future<void> switchTo(String source);

  /// One event each time a track plays to its end.
  Stream<void> get completions;

  Future<void> pause();
  Future<void> resume();

  /// Back to the start of the current track.
  Future<void> restart();

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
/// session away from music that is playing, and with it playback with the
/// ringer off. The chime checks this and leaves the session alone.
abstract final class MusicAudioSession {
  static bool inUse = false;
}

class AudioplayersMusicAudio implements MusicAudio {
  AudioPlayer? _player;
  final _completions = StreamController<void>.broadcast();

  /// Music the reader chose to hear: the `playback` category, so it plays with
  /// the ringer off, and not mixed with other apps. It plays only while the
  /// app is in front: there is no background audio mode, and the controller
  /// pauses it when the app goes away. On Android a full audio-focus request:
  /// another app taking focus, or a call, pauses us, and a transient loss
  /// resumes on its own (audioplayers' FocusManager).
  static final AudioContext _context = AudioContext(
    iOS: AudioContextIOS(category: AVAudioSessionCategory.playback, options: const {}),
    android: const AudioContextAndroid(
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gain,
    ),
  );

  Future<AudioPlayer> _ensure() async {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer(playerId: 'background_music');
    await player.setReleaseMode(ReleaseMode.stop);
    player.onPlayerComplete.listen((_) => _completions.add(null));
    return _player = player;
  }

  static Source _source(String source) =>
      source.startsWith('http') ? UrlSource(source) : AssetSource(source);

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Future<void> start(String source, {required double volume}) async {
    final player = await _ensure();
    // Every start, not once: the chime or another player may have changed the
    // shared session since.
    await player.setAudioContext(_context);
    MusicAudioSession.inUse = true;
    await player.stop();
    await player.play(_source(source), volume: volume);
  }

  @override
  Future<void> switchTo(String source) async {
    final player = await _ensure();
    await player.setSource(_source(source));
    await player.resume();
  }

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> restart() async => _player?.seek(Duration.zero);

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
    await _completions.close();
  }
}

final musicAudioProvider = Provider<MusicAudio>((ref) {
  final audio = AudioplayersMusicAudio();
  ref.onDispose(audio.dispose);
  return audio;
});
