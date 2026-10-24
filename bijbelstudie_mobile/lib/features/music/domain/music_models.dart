/// Background music while reading - a Pro feature.
///
/// The player itself is `MusicPlayerController`; this file holds only the
/// plain values it hands around.
library;

/// The three playlists. A track plays on into the next one of its own kind.
enum MusicCategory {
  piano('Piano', '<path d="M3 5h18v14H3z"/><path d="M8 5v8"/><path d="M12 5v14"/>'
      '<path d="M16 5v8"/>'),
  lofi('Lofi', '<path d="M3 14v-2a9 9 0 0 1 18 0v2"/>'
      '<path d="M3 14h3v6H4a1 1 0 0 1-1-1z"/><path d="M21 14h-3v6h2a1 1 0 0 0 1-1z"/>'),
  organ('Orgel', '<path d="M5 20v-8"/><path d="M9 20V8"/><path d="M12 20V4"/>'
      '<path d="M15 20V8"/><path d="M19 20v-8"/><path d="M3 20h18"/>');

  const MusicCategory(this.label, this.iconPaths);

  /// The filter chip in the picker and the playlist chip in the menu.
  final String label;

  /// SVG `<path>` elements on Lucide's 24x24 stroked frame (`LucideIcon`).
  final String iconPaths;
}

/// Where a recording came from and under which licence, shown in Instellingen
/// under "Muziek". Every track is public domain, CC0 or CC BY; the credit is
/// shown for all of them, because the people who recorded and released these
/// deserve to be named, and CC BY asks for it.
class MusicCredit {
  const MusicCredit({
    required this.performer,
    required this.licence,
    required this.sourceUrl,
  });

  final String performer;

  /// "Publiek domein", "CC0" or "CC BY 3.0".
  final String licence;

  /// The page where the licence is stated.
  final String sourceUrl;
}

class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.category,
    required this.file,
    required this.credit,
    this.bundled = false,
  });

  /// Stable key, persisted as the last track played.
  final String id;

  /// "Clair de lune".
  final String title;

  /// The composer for piano and organ, the maker for lofi.
  final String artist;
  final MusicCategory category;

  /// File name, e.g. `piano_debussy_clair_de_lune.m4a`.
  final String file;
  final MusicCredit credit;

  /// Shipped inside the app, so its playlist still plays without a
  /// connection. The rest stream from the site.
  final bool bundled;

  /// "Debussy" in "Piano · Debussy".
  String get subtitle => '${category.label} · $artist';
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
    this.offline = false,
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

  /// A streamed track would not load, so the playlist's bundled track plays
  /// instead. Cleared by the next stream that loads.
  final bool offline;

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
    bool? offline,
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
      offline: offline ?? this.offline,
    );
  }
}
