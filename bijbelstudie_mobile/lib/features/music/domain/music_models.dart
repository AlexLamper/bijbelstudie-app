/// Background music while reading - a Pro feature.
///
/// The player itself is `MusicPlayerController`; this file holds only the
/// plain values it hands around.
library;

enum MusicCategory {
  music('Muziek'),
  nature('Natuur');

  const MusicCategory(this.label);

  /// The filter chip in the picker.
  final String label;
}

/// Where a recording came from and under which licence, shown in Instellingen
/// under "Muziek". Every track the app ships is public domain or CC0, so no
/// credit is legally required; it is shown anyway, because the people who
/// recorded and released these deserve to be named.
class MusicCredit {
  const MusicCredit({
    required this.work,
    required this.performer,
    required this.licence,
    required this.sourceUrl,
  });

  /// What is played, e.g. "J.S. Bach - Air (BWV 1068)".
  final String work;
  final String performer;

  /// "Publiek domein" or "CC0".
  final String licence;

  /// The file's page on Wikimedia Commons, where the licence is stated.
  final String sourceUrl;
}

class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.name,
    required this.category,
    required this.subtitle,
    required this.iconPaths,
    required this.asset,
    required this.credit,
  });

  /// Stable key, persisted as the last track played.
  final String id;
  final String name;
  final MusicCategory category;

  /// "Piano · zacht en traag". The part after "· " doubles as the status line
  /// in the music menu.
  final String subtitle;

  /// SVG `<path>` elements on Lucide's 24x24 stroked frame (`LucideIcon`).
  final String iconPaths;

  /// Relative to `assets/`, the way audioplayers' `AssetSource` wants it.
  final String asset;
  final MusicCredit credit;

  bool get isNature => category == MusicCategory.nature;

  /// "zacht en traag" from "Piano · zacht en traag".
  String get mood {
    final i = subtitle.indexOf('· ');
    return i < 0 ? subtitle : subtitle.substring(i + 2);
  }
}

enum MusicPhase { idle, playing }

/// The sleep timer's steps, cycled by the timer button: off, then minutes.
const List<int?> kMusicTimerMinutes = [null, 15, 30, 60];

class MusicState {
  const MusicState({
    this.phase = MusicPhase.idle,
    this.trackIndex = 0,
    this.lastTrackIndex,
    this.paused = false,
    this.mini = false,
    this.expandedFromBubble = false,
    this.timerIndex = 0,
    this.volume = 0.5,
    this.showStoppedMessage = false,
    this.hintSeen = true,
  });

  final MusicPhase phase;
  final int trackIndex;

  /// The track played most recently, for the "Laatst" label in the picker.
  /// Persisted; null on a device that never played anything.
  final int? lastTrackIndex;
  final bool paused;

  /// The pill is shrunk to the bubble in the corner.
  final bool mini;

  /// The pill was opened from the bubble, so it goes back to being one when
  /// the reader carries on reading.
  final bool expandedFromBubble;

  /// Index into [kMusicTimerMinutes]; 0 is off.
  final int timerIndex;

  /// 0-1. Persisted.
  final double volume;

  /// "Muziek gestopt" with its undo is showing.
  final bool showStoppedMessage;

  /// "Veeg omlaag om te verkleinen" has done its job. Persisted. Starts true
  /// so a device that has not loaded its preferences yet never flashes it.
  final bool hintSeen;

  bool get isPlaying => phase == MusicPhase.playing;
  int? get timerMinutes => kMusicTimerMinutes[timerIndex];

  MusicState copyWith({
    MusicPhase? phase,
    int? trackIndex,
    int? lastTrackIndex,
    bool? paused,
    bool? mini,
    bool? expandedFromBubble,
    int? timerIndex,
    double? volume,
    bool? showStoppedMessage,
    bool? hintSeen,
  }) {
    return MusicState(
      phase: phase ?? this.phase,
      trackIndex: trackIndex ?? this.trackIndex,
      lastTrackIndex: lastTrackIndex ?? this.lastTrackIndex,
      paused: paused ?? this.paused,
      mini: mini ?? this.mini,
      expandedFromBubble: expandedFromBubble ?? this.expandedFromBubble,
      timerIndex: timerIndex ?? this.timerIndex,
      volume: volume ?? this.volume,
      showStoppedMessage: showStoppedMessage ?? this.showStoppedMessage,
      hintSeen: hintSeen ?? this.hintSeen,
    );
  }
}
