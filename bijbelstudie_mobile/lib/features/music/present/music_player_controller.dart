import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/music_audio.dart';
import '../data/music_prefs.dart';
import '../data/music_tracks.dart';
import '../domain/music_models.dart';

/// The one background-music player, shared by every tab.
///
/// Global on purpose (not autoDispose): the music keeps playing when the
/// reader that started it is gone, and the pill in `MainScaffold`, the note
/// button in the reader and both sheets all read the same state.
///
/// Nothing here checks Pro. The surfaces that *start* a session do (the
/// picker and the note button), so a reader whose Pro lapses mid-session
/// finishes that session and is asked at the next start.
class MusicPlayerController extends Notifier<MusicState> {
  late MusicAudio _audio;

  Timer? _sleepTimer;
  Timer? _stoppedTimer;
  Timer? _volumeSaveTimer;
  Timer? _fadeTimer;
  Completer<void>? _fadeDone;
  AppLifecycleListener? _lifecycle;
  StreamSubscription<void>? _completions;

  /// The app went out of sight while playing, so the music was paused with it
  /// and comes back when the app does.
  bool _pausedForHide = false;

  /// [_onShow] just resumed the player, so the stall check that follows on
  /// resume has nothing to find out.
  bool _resumedOnShow = false;

  /// Platform calls run one after the other, so a fast double tap cannot
  /// interleave a crossfade with a pause.
  Future<void> _queue = Future.value();

  /// [stop] only pauses at first, so "Ongedaan maken" can carry on from the
  /// same spot; the player is released when the message runs out.
  bool _stopPending = false;
  bool _pausedBeforeStop = false;
  bool _fadingOut = false;

  static const stoppedMessageDuration = Duration(seconds: 4);
  static const sleepFadeDuration = Duration(seconds: 3);

  /// Each half of the 400 ms crossfade when switching tracks.
  static const switchFadeHalf = Duration(milliseconds: 200);

  /// "Vorige" this far into a track starts it over instead.
  static const restartThreshold = Duration(seconds: 3);

  @override
  MusicState build() {
    _audio = ref.watch(musicAudioProvider);
    _lifecycle = AppLifecycleListener(
      onHide: _onHide,
      onShow: _onShow,
      onResume: () => unawaited(_syncAfterResume()),
      onDetach: () => stop(silent: true),
    );
    _completions = _audio.completions.listen((_) => _onTrackEnd());
    ref.onDispose(() {
      _sleepTimer?.cancel();
      _stoppedTimer?.cancel();
      _volumeSaveTimer?.cancel();
      _cancelFade();
      _lifecycle?.dispose();
      unawaited(_completions?.cancel());
    });
    unawaited(_loadPrefs());
    return const MusicState();
  }

  MusicTrack get currentTrack => kMusicTracks[state.trackIndex];

  Future<void> _loadPrefs() async {
    try {
      final prefs = await MusicPrefs.load();
      final last = kMusicTracks.indexWhere((t) => t.id == prefs.lastTrackId);
      state = state.copyWith(
        volume: prefs.volume,
        lastTrackIndex: last < 0 ? null : last,
        hintSeen: prefs.hintSeen,
      );
    } catch (_) {
      // Defaults are fine; the next change writes them.
    }
  }

  void _run(Future<void> Function() op) {
    _queue = _queue.then((_) => op()).catchError((Object _) {});
  }

  /// Loads [index] through [load]. A streamed track that will not load (no
  /// connection) gives way to its playlist's bundled track, so there is still
  /// music; the menu says why.
  Future<void> _load(int index, Future<void> Function(String source) load) async {
    final track = kMusicTracks[index];
    try {
      await load(musicSourceOf(track));
      if (state.offline && !track.bundled) state = state.copyWith(offline: false);
    } catch (_) {
      // Already moved on (a fast skip queued behind this): that load follows.
      if (track.bundled || !state.isPlaying || state.trackIndex != index) return;
      final fallback = musicBundledIn(track.category);
      state = state.copyWith(trackIndex: fallback, offline: true);
      await load(musicSourceOf(kMusicTracks[fallback]));
    }
  }

  /// Starts [index] from the top, with the pill expanded. The rest of its
  /// playlist follows.
  void play(int index) {
    if (index < 0 || index >= kMusicTracks.length) return;
    _clearStopped();
    _cancelFade();
    _sleepTimer?.cancel();
    _fadingOut = false;
    state = state.copyWith(
      phase: MusicPhase.playing,
      trackIndex: index,
      lastTrackIndex: index,
      paused: false,
      mini: false,
      expandedFromBubble: false,
      timerIndex: 0,
      showStoppedMessage: false,
    );
    unawaited(MusicPrefs.saveLastTrack(kMusicTracks[index].id).catchError((Object _) {}));
    final volume = state.volume;
    _run(() => _load(index, (source) => _audio.start(source, volume: volume)));
  }

  /// Switches track while playing, with a short crossfade. Choosing a track
  /// means wanting to hear it, so a paused player starts again.
  void select(int index) {
    if (!state.isPlaying) return play(index);
    if (index == state.trackIndex || index < 0 || index >= kMusicTracks.length) return;
    _switch(index, fade: !state.paused);
  }

  void _switch(int index, {required bool fade}) {
    state = state.copyWith(trackIndex: index, lastTrackIndex: index, paused: false);
    unawaited(MusicPrefs.saveLastTrack(kMusicTracks[index].id).catchError((Object _) {}));
    _run(() async {
      if (fade) await _ramp(state.volume, 0, switchFadeHalf);
      await _audio.setVolume(0);
      await _load(index, _audio.switchTo);
      await _ramp(0, state.volume, switchFadeHalf);
    });
  }

  /// "Volgende": the next track in the playlist, round to the first.
  void next() {
    if (!state.isPlaying) return;
    _switch(musicStep(state.trackIndex, 1), fade: !state.paused);
  }

  /// "Vorige": the start of this track when it is under way, like every music
  /// player, else the track before it.
  void previous() {
    if (!state.isPlaying) return;
    final index = state.trackIndex;
    _run(() async {
      final at = await _audio.position();
      if (!state.isPlaying || state.trackIndex != index) return;
      if (at != null && at > restartThreshold) {
        if (state.paused) state = state.copyWith(paused: false);
        await _audio.restart();
        await _audio.resume();
      } else {
        _switch(musicStep(index, -1), fade: !state.paused);
      }
    });
  }

  /// A track played to its end: on to the next, without a fade - the track
  /// faded itself out.
  void _onTrackEnd() {
    if (!state.isPlaying || state.paused || _fadingOut) return;
    _switch(musicStep(state.trackIndex, 1), fade: false);
  }

  /// Music belongs to the open app: it pauses when the app goes out of sight
  /// (home, app switcher, locked screen) and carries on when it is back.
  void _onHide() {
    if (!state.isPlaying || state.paused) return;
    _pausedForHide = true;
    _run(_audio.pause);
  }

  void _onShow() {
    if (!_pausedForHide) return;
    _pausedForHide = false;
    if (!state.isPlaying || state.paused) return;
    _resumedOnShow = true;
    _run(_audio.resume);
  }

  void togglePause() {
    if (!state.isPlaying) return;
    final paused = !state.paused;
    state = state.copyWith(paused: paused);
    _run(paused ? _audio.pause : _audio.resume);
  }

  /// Ends the session. [silent] skips "Muziek gestopt" and its undo - the
  /// sleep timer stops that way, because nobody is there to undo it.
  void stop({bool silent = false}) {
    if (!state.isPlaying) return;
    _sleepTimer?.cancel();
    _cancelFade();
    _fadingOut = false;
    _stoppedTimer?.cancel();
    if (silent) {
      _stopPending = false;
      state = state.copyWith(
        phase: MusicPhase.idle,
        paused: false,
        mini: false,
        expandedFromBubble: false,
        timerIndex: 0,
        showStoppedMessage: false,
      );
      _run(_audio.stop);
      return;
    }
    _pausedBeforeStop = state.paused;
    _stopPending = true;
    state = state.copyWith(
      phase: MusicPhase.idle,
      mini: false,
      expandedFromBubble: false,
      timerIndex: 0,
      showStoppedMessage: true,
    );
    _run(_audio.pause);
    _stoppedTimer = Timer(stoppedMessageDuration, _clearStopped);
  }

  /// "Ongedaan maken": the same track from the same spot, pill expanded.
  void undoStop() {
    if (!_stopPending) return;
    _stoppedTimer?.cancel();
    _stopPending = false;
    state = state.copyWith(
      phase: MusicPhase.playing,
      paused: _pausedBeforeStop,
      mini: false,
      expandedFromBubble: false,
      showStoppedMessage: false,
    );
    if (!_pausedBeforeStop) _run(_audio.resume);
  }

  /// The message ran out (or a new sound started): release the player if it
  /// was only paused for the undo.
  void _clearStopped() {
    _stoppedTimer?.cancel();
    if (state.showStoppedMessage) state = state.copyWith(showStoppedMessage: false);
    if (_stopPending) {
      _stopPending = false;
      _run(_audio.stop);
    }
  }

  void shrink() {
    if (!state.isPlaying || state.mini) return;
    state = state.copyWith(mini: true, expandedFromBubble: false);
    // The hint teaches that the pill gets out of the way; once it has, by a
    // swipe or a scroll, the lesson is learnt.
    if (!state.hintSeen) markHintSeen();
  }

  void expand() {
    if (!state.isPlaying || !state.mini) return;
    state = state.copyWith(mini: false, expandedFromBubble: true);
  }

  void markHintSeen() {
    state = state.copyWith(hintSeen: true);
    unawaited(MusicPrefs.saveHintSeen().catchError((Object _) {}));
  }

  /// Uit → 15 → 30 → 60 → Uit. Each step restarts the countdown.
  void cycleTimer() {
    if (!state.isPlaying) return;
    final next = (state.timerIndex + 1) % kMusicTimerMinutes.length;
    state = state.copyWith(timerIndex: next);
    _sleepTimer?.cancel();
    final minutes = kMusicTimerMinutes[next];
    if (minutes != null) _sleepTimer = Timer(Duration(minutes: minutes), _onSleepTimer);
  }

  void _onSleepTimer() {
    if (!state.isPlaying) return;
    _fadingOut = true;
    _run(() async {
      if (!state.paused) await _ramp(state.volume, 0, sleepFadeDuration);
      if (_fadingOut && state.isPlaying) stop(silent: true);
      _fadingOut = false;
    });
  }

  void setVolume(double volume) {
    final v = volume.clamp(0.0, 1.0);
    state = state.copyWith(volume: v);
    if (!_fadingOut && _fadeTimer == null) unawaited(_audio.setVolume(v).catchError((Object _) {}));
    _volumeSaveTimer?.cancel();
    _volumeSaveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(MusicPrefs.saveVolume(v).catchError((Object _) {}));
    });
  }

  /// iOS pauses the player for a phone call (and Android for another app
  /// taking audio focus) without telling audioplayers. Coming back, check the
  /// position still moves; if it does not, show the session as paused so the
  /// play button tells the truth - rather than forcing playback back on and
  /// taking the audio away from whatever paused us.
  Future<void> _syncAfterResume() async {
    if (_resumedOnShow) {
      _resumedOnShow = false;
      return;
    }
    if (!state.isPlaying || state.paused) return;
    try {
      final first = await _audio.position();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final second = await _audio.position();
      if (first == null || second == null) return;
      if (second == first && state.isPlaying && !state.paused) {
        state = state.copyWith(paused: true);
      }
    } catch (_) {
      /* leave the state as it is */
    }
  }

  Future<void> _ramp(double from, double to, Duration duration) {
    _cancelFade();
    final done = Completer<void>();
    _fadeDone = done;
    const step = Duration(milliseconds: 50);
    final steps = math.max(1, duration.inMilliseconds ~/ step.inMilliseconds);
    var i = 0;
    _fadeTimer = Timer.periodic(step, (timer) {
      i++;
      final v = from + (to - from) * (i / steps);
      unawaited(_audio.setVolume(v).catchError((Object _) {}));
      if (i >= steps) _cancelFade();
    });
    return done.future;
  }

  /// Stops a ramp and completes its future, so a queued operation waiting on
  /// it never hangs the queue.
  void _cancelFade() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    final done = _fadeDone;
    _fadeDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }
}

final musicPlayerProvider = NotifierProvider<MusicPlayerController, MusicState>(
  MusicPlayerController.new,
);
