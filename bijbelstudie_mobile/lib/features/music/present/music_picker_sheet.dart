import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/lucide_icon.dart';
import '../../premium/present/paywall_route.dart';
import '../../premium/present/pro_access_provider.dart';
import '../data/music_tracks.dart';
import '../domain/music_models.dart';
import 'music_player_controller.dart';
import 'music_widgets.dart';

/// "Kies muziek": every track, searchable and filtered by playlist. A track
/// chosen here plays on into the rest of its playlist.
///
/// Open to everyone - a reader without Pro sees exactly what Pro offers. Only
/// pressing play is gated: the sheet closes and the paywall opens on the
/// price with "Achtergrondmuziek hoort bij Pro." above it.
Future<void> showMusicPickerSheet(BuildContext context) {
  return showMusicSheet<void>(context, (_) => const _MusicPickerSheet());
}

class _MusicPickerSheet extends ConsumerStatefulWidget {
  const _MusicPickerSheet();

  @override
  ConsumerState<_MusicPickerSheet> createState() => _MusicPickerSheetState();
}

class _MusicPickerSheetState extends ConsumerState<_MusicPickerSheet> {
  final _search = TextEditingController();
  /// Null is "Alles".
  MusicCategory? _filter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<int> get _visible {
    final query = _search.text.trim().toLowerCase();
    return [
      for (var i = 0; i < kMusicTracks.length; i++)
        if (_matches(kMusicTracks[i], query)) i,
    ];
  }

  bool _matches(MusicTrack track, String query) {
    if (_filter != null && track.category != _filter) return false;
    if (query.isEmpty) return true;
    return track.title.toLowerCase().contains(query) ||
        track.subtitle.toLowerCase().contains(query);
  }

  void _pick(int index) {
    AppHaptics.light();
    final hasPro = ref.read(hasProProvider);
    // Captured before the pop: the sheet's context is gone after it.
    final router = GoRouter.maybeOf(context);
    _search.clear();
    Navigator.of(context).pop();
    if (!hasPro) {
      // The play press is both the refusal and the way through, so it counts
      // as the hit and the click at once - the reader never sees a separate
      // prompt to click on.
      final analytics = ref.read(analyticsProvider);
      analytics.track(AnalyticsEvents.paywallHit, {'surface': 'music'});
      analytics.track(AnalyticsEvents.paywallCtaClicked, {'surface': 'music'});
      openPaywallWith(router, gate: PaywallGate.music);
      return;
    }
    ref.read(musicPlayerProvider.notifier).play(index);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final last = ref.watch(musicPlayerProvider.select((s) => s.lastTrackIndex));
    final hasPro = ref.watch(hasProProvider);
    final visible = _visible;
    final query = _search.text.trim();
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MusicSheetGrabber(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  Text(
                    'Kies muziek',
                    style: TextStyle(
                      fontFamily: AppTheme.sansFontName,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const MusicProBadge(),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Sluit',
                        style: TextStyle(
                          fontFamily: AppTheme.sansFontName,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.teal,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    hasPro
                        ? 'Piano, lofi en orgel, zonder tekst. Speelt door als je verder leest.'
                        : 'Piano, lofi en orgel, zonder tekst. Speelt door als je verder leest. '
                              'Achtergrondmuziek hoort bij Pro.',
                    style: TextStyle(
                      fontFamily: AppTheme.sansFontName,
                      fontSize: 13,
                      height: 1.5,
                      color: AppTheme.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SearchField(controller: _search, onChanged: () => setState(() {})),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (filter, label) in [
                        (null, 'Alles'),
                        for (final c in MusicCategory.values) (c, c.label),
                      ])
                        _FilterChip(
                          label: label,
                          selected: _filter == filter,
                          onTap: () {
                            if (_filter == filter) return;
                            AppHaptics.selection();
                            setState(() => _filter = filter);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
            Flexible(
              child: visible.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 62),
                      child: Text(
                        'Niets gevonden voor "$query"',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AppTheme.sansFontName,
                          fontSize: 13.5,
                          color: AppTheme.inkFaint,
                        ),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        34 + MediaQuery.paddingOf(context).bottom,
                      ),
                      children: [
                        for (final (n, i) in visible.indexed) ...[
                          // Under "Alles" the playlists get a heading each.
                          if (_filter == null &&
                              (n == 0 ||
                                  kMusicTracks[visible[n - 1]].category !=
                                      kMusicTracks[i].category))
                            _PlaylistHeading(kMusicTracks[i].category),
                          _TrackRow(
                            track: kMusicTracks[i],
                            isLast: last == i,
                            locked: !hasPro,
                            onTap: () => _pick(i),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final style = TextStyle(
      fontFamily: AppTheme.sansFontName,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: AppTheme.ink,
    );
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.paperSunken,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        children: [
          LucideIcon(MusicIcons.search, size: 16, color: AppTheme.inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (_) => onChanged(),
              textInputAction: TextInputAction.search,
              style: style,
              cursorColor: AppTheme.teal,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Zoek muziek',
                hintStyle: style.copyWith(color: AppTheme.inkMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTheme.teal : AppTheme.paperRaised,
            border: selected ? null : Border.all(color: AppTheme.rule),
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.sansFontName,
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? Colors.white : AppTheme.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistHeading extends StatelessWidget {
  const _PlaylistHeading(this.category);

  final MusicCategory category;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        category.label.toUpperCase(),
        style: TextStyle(
          fontFamily: AppTheme.sansFontName,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: AppTheme.inkMuted,
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.isLast,
    required this.locked,
    required this.onTap,
  });

  final MusicTrack track;
  final bool isLast;

  /// No Pro: the row still plays "play", but the press leads to the paywall.
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Semantics(
      button: true,
      label: '${track.title}, ${track.subtitle}${isLast ? ', laatst gespeeld' : ''}. '
          '${locked ? 'Hoort bij Pro' : 'Afspelen'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.paperSunken)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: musicTileFill(track.category),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: LucideIcon(
                  track.category.iconPaths,
                  size: 20,
                  color: musicTileInk(track.category),
                  strokeWidth: 1.8,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTheme.sansFontName,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.ink,
                            ),
                          ),
                        ),
                        if (isLast) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.tealSoft,
                              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                            ),
                            child: Text(
                              'Laatst',
                              style: TextStyle(
                                fontFamily: AppTheme.sansFontName,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.tealStrong,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      track.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.sansFontName,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppTheme.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.rule),
                ),
                child: LucideIcon(MusicIcons.play, size: 13, color: AppTheme.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
