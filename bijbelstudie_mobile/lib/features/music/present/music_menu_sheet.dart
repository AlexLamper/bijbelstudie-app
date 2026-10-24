import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/lucide_icon.dart';
import '../data/music_tracks.dart';
import '../domain/music_models.dart';
import 'music_player_controller.dart';
import 'music_widgets.dart';

/// The music menu: what is playing, stop / play-pause / sleep timer, volume,
/// and the other sounds to switch to.
Future<void> showMusicMenuSheet(BuildContext context) {
  return showMusicSheet<void>(context, (_) => const _MusicMenuSheet());
}

class _MusicMenuSheet extends ConsumerWidget {
  const _MusicMenuSheet();

  static String _status(MusicState state) {
    if (state.paused) return 'Gepauzeerd';
    final minutes = state.timerMinutes;
    if (minutes != null) return 'Stopt na $minutes min';
    return 'Speelt door';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final state = ref.watch(musicPlayerProvider);
    final controller = ref.read(musicPlayerProvider.notifier);
    final track = kMusicTracks[state.trackIndex];

    // The session can end under the open sheet - the sleep timer runs out.
    // Only while this sheet is the top route: the Stop button pops first, and
    // must not have this pop a second route behind it.
    ref.listen(musicPlayerProvider.select((s) => s.isPlaying), (was, now) {
      if (was == true && !now && (ModalRoute.of(context)?.isCurrent ?? false)) {
        Navigator.of(context).pop();
      }
    });

    final label = TextStyle(fontFamily: AppTheme.sansFontName, fontSize: 11, height: 1.2);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MusicSheetGrabber(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _IconTap(
                        semantics: 'Sluiten',
                        onTap: () => Navigator.of(context).pop(),
                        child: LucideIcon(
                          MusicIcons.chevronDown,
                          size: 18,
                          color: AppTheme.inkMuted,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'ACHTERGRONDMUZIEK',
                      textAlign: TextAlign.center,
                      style: label.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                        color: AppTheme.inkMuted,
                      ),
                    ),
                  ),
                  // As wide as the chevron's slot, so the title is centred on
                  // the sheet rather than on what is left of the row.
                  const SizedBox(
                    width: 44,
                    child: Align(alignment: Alignment.centerRight, child: MusicProBadge()),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: Column(
                children: [
                  const SizedBox(height: 26),
                  Container(
                    width: 128,
                    height: 128,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: musicTileFill(track),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: AppTheme.teal.withValues(alpha: 0.06), spreadRadius: 12),
                        BoxShadow(color: AppTheme.teal.withValues(alpha: 0.03), spreadRadius: 26),
                      ],
                    ),
                    child: LucideIcon(
                      track.iconPaths,
                      size: 46,
                      color: musicTileInk(track),
                      strokeWidth: 1.6,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    track.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.sansFontName,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${track.mood} · ${_status(state)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.sansFontName,
                      fontSize: 13,
                      color: AppTheme.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SideControl(
                        semantics: 'Muziek stoppen',
                        fill: AppTheme.destructiveTint,
                        border: AppTheme.destructive.withValues(alpha: 0.3),
                        icon: LucideIcon(MusicIcons.stop, size: 22, color: AppTheme.destructive),
                        label: Text(
                          'Stop',
                          style: label.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.destructive,
                          ),
                        ),
                        onTap: () {
                          AppHaptics.light();
                          Navigator.of(context).pop();
                          controller.stop();
                        },
                      ),
                      const SizedBox(width: 28),
                      Semantics(
                        button: true,
                        label: state.paused ? 'Afspelen' : 'Pauzeren',
                        excludeSemantics: true,
                        child: Pressable(
                          child: GestureDetector(
                            onTap: () {
                              AppHaptics.light();
                              controller.togglePause();
                            },
                            child: Container(
                              width: 60,
                              height: 60,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppTheme.teal,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.teal.withValues(alpha: 0.28),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: LucideIcon(
                                state.paused ? MusicIcons.play : MusicIcons.pause,
                                size: 22,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 28),
                      _SideControl(
                        semantics: state.timerMinutes == null
                            ? 'Slaaptimer: uit'
                            : 'Slaaptimer: ${state.timerMinutes} minuten',
                        fill: AppTheme.paperRaised,
                        border: AppTheme.rule,
                        icon: LucideIcon(MusicIcons.clock, size: 19, color: AppTheme.inkSoft),
                        label: Text(
                          state.timerMinutes == null ? 'Timer' : '${state.timerMinutes} min',
                          style: label.copyWith(
                            fontWeight: FontWeight.w500,
                            color: AppTheme.inkMuted,
                          ),
                        ),
                        onTap: () {
                          AppHaptics.selection();
                          controller.cycleTimer();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      LucideIcon(MusicIcons.volumeLow, size: 18, color: AppTheme.inkMuted),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            activeTrackColor: AppTheme.teal,
                            inactiveTrackColor: AppTheme.rule,
                            thumbColor: AppTheme.teal,
                            overlayColor: AppTheme.teal.withValues(alpha: 0.12),
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                          ),
                          child: Slider(
                            value: state.volume,
                            semanticFormatterCallback: (v) => 'Volume ${(v * 100).round()} procent',
                            onChanged: controller.setVolume,
                          ),
                        ),
                      ),
                      LucideIcon(MusicIcons.volumeHigh, size: 18, color: AppTheme.inkMuted),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
            // Bleeds off the right edge, so it reads as "there is more".
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 24, right: 24),
                itemCount: kMusicTracks.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => _TrackChip(
                  track: kMusicTracks[i],
                  selected: i == state.trackIndex,
                  onTap: () {
                    AppHaptics.selection();
                    controller.select(i);
                  },
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _IconTap extends StatelessWidget {
  const _IconTap({required this.semantics, required this.onTap, required this.child});

  final String semantics;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(width: 34, height: 34, child: Center(child: child)),
      ),
    );
  }
}

/// Stop and Timer: a 48x48 rounded square over a small label.
class _SideControl extends StatelessWidget {
  const _SideControl({
    required this.semantics,
    required this.fill,
    required this.border,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String semantics;
  final Color fill;
  final Color border;
  final Widget icon;
  final Widget label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: Pressable(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 60,
            child: Column(
              children: [
                const SizedBox(height: 6),
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: fill,
                    border: Border.all(color: border),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: icon,
                ),
                const SizedBox(height: 6),
                label,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackChip extends StatelessWidget {
  const _TrackChip({required this.track, required this.selected, required this.onTap});

  final MusicTrack track;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final ink = selected ? AppTheme.tealStrong : AppTheme.inkSoft;
    return Semantics(
      button: true,
      selected: selected,
      label: track.name,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.fromLTRB(10, 0, 13, 0),
          decoration: BoxDecoration(
            color: selected ? AppTheme.tealTint : AppTheme.paperRaised,
            border: Border.all(
              color: selected ? AppTheme.teal : AppTheme.rule,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LucideIcon(track.iconPaths, size: 15, color: ink, strokeWidth: 1.8),
              const SizedBox(width: 7),
              Text(
                track.name,
                style: TextStyle(
                  fontFamily: AppTheme.sansFontName,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
