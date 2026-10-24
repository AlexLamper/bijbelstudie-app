Implement the "Achtergrondmuziek" feature in bijbelstudie_mobile.

The full spec is in design_handoff_achtergrondmuziek/README.md. Read it fully first. The HTML prototype in the same folder is a design reference only; open it in a browser to see the interactions. Build only the final variants (kiezer = origineel, menu = donker in light colours, bubble = wit).

Follow CLAUDE.md conventions: feature-first under lib/features/music/, Riverpod providers in present/, Dutch UI strings, AppTheme tokens where a hex matches.

Work in this order and run `flutter analyze` after each step:
1. MusicState + MusicPlayerController (global NotifierProvider) wrapping one audioplayers AudioPlayer (loop, volume, sleep timer, stop with undo snapshot). iOS background audio + Android audio focus.
2. Track list + icons (lib/features/music/data/music_tracks.dart). Use placeholder asset paths assets/music/*.m4a and tell me which files to add.
3. Note button in the reader tool row (read_screen.dart), Pro-gated via hasProProvider.
4. "Kies muziek" bottom sheet with search, Alles/Muziek/Natuur filter, icon rows, "Laatst" label.
5. Pill/bubble overlay in MainScaffold: tap opens menu, swipe down shrinks, auto-shrink after 3.5 s while readerChromeVisibleProvider is false.
6. Music menu sheet (big icon circle, red Stop, teal play/pause, timer, volume, track chips).
7. "Muziek gestopt" undo message (4 s).
8. A widget test for the controller (play → pause → stop → undo) in test/music_player_test.dart.

Ask me before adding any new dependency.
