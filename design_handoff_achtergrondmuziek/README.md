# Handoff: Achtergrondmuziek (background music while reading)

## Overview
Pro users can play calm instrumental music or nature sounds while reading the Bible. They tap a music-note button in the reader's tool row, pick a sound, and a small **pill** player appears above the chapter pager. When the user swipes the pill down or scrolls the chapter, it shrinks to a **bubble** in the corner. Tapping the pill or bubble opens the **music menu** (pause, stop, timer, volume, switch sound). One global player keeps playing across every tab.

## About the design files
`Muziek prototype.dc.html` is a **design reference built in HTML**. It is not code to ship. Rebuild it in the Flutter app (`bijbelstudie_mobile/`) using the existing patterns: Riverpod providers, `AppTheme` tokens, `app_widgets.dart` components and feature-first folders. Open the HTML file in a browser to click through the full flow. The prototype also contains alternative designs behind tweak options. **Only the final choices below are to be built.**

## Fidelity
**High fidelity.** Colours, sizes, copy and timings are final. Where an `AppTheme` token already matches a hex value below, use the token.

---

## Where it goes in the repo

| Piece | Location |
|---|---|
| Player state + audio | new `lib/features/music/` (`data/music_tracks.dart`, `domain/music_models.dart`, `present/music_player_controller.dart`) |
| Note button | reader tool row in `features/bible/present/read_screen.dart` (next to search, before "Aa") |
| Pill + bubble overlay | `MainScaffold` (the `ShellRoute` builder in `core/router/app_router.dart`), so it lives above every tab |
| Music list sheet | `features/music/present/music_picker_sheet.dart` |
| Music menu sheet | `features/music/present/music_menu_sheet.dart` |
| Undo message | `features/music/present/music_stopped_toast.dart` |
| Pro gate | `hasProProvider` (`features/premium/present/pro_access_provider.dart`). Non-Pro users see the existing upgrade prompt (`upgrade_prompt.dart`) |
| Shrink trigger | `readerChromeVisibleProvider` (`reader_chrome.dart`). When the reader hides its chrome while scrolling, the pill shrinks |
| Playback | `audioplayers` (already a dependency). `ReleaseMode.loop`, one shared `AudioPlayer` |

**Platform setup**
- iOS: add `audio` to `UIBackgroundModes` in `ios/Runner/Info.plist`, so music keeps playing with the screen locked. Set `AudioContextIOS(category: AVAudioSessionCategory.playback, options: {mixWithOthers: false})`.
- Android: request audio focus via `AudioContextAndroid(usageType: AndroidUsageType.media, contentType: AndroidContentType.music, audioFocus: AndroidAudioFocus.gain)`.
- Pause automatically when another app takes audio focus or a call comes in.

---

## State

```dart
enum MusicPhase { idle, playing }   // the sheets are routes/modals, not phases
class MusicState {
  MusicPhase phase;      // idle | playing
  int trackIndex;        // 0–5
  int? lastTrackIndex;   // for the "Laatst" label (persist in shared_preferences)
  bool paused;
  bool mini;             // pill shrunk to bubble
  bool expandedFromBubble;
  int timerIndex;        // 0 Uit, 1 15 min, 2 30 min, 3 60 min
  double volume;         // 0–1, default 0.5 (persist)
}
```
Provider: `musicPlayerProvider = NotifierProvider<MusicPlayerController, MusicState>` (not autoDispose, so it's global).

Actions: `play(index)`, `select(index)` (switch track while playing), `togglePause()`, `stop()` (keeps a snapshot for undo), `undoStop()`, `shrink()`, `expand()`, `cycleTimer()`, `setVolume(v)`.

**Sleep timer:** when set, start a `Timer`. When it fires, fade the volume to 0 over 3 s, then call `stop()` without showing the undo message.

---

## Tracks

| # | Name | Category | Subtitle (list) | Icon (24×24 stroke path, stroke-width 1.8) |
|---|---|---|---|---|
| 0 | Stille piano | Muziek | Piano · zacht en traag | `M3 5h18v14H3z M8 5v8 M12 5v14 M16 5v8` |
| 1 | Regen | Natuur | Natuur · zachte regen | `M7 15a4 4 0 0 1-.6-7.95A5.5 5.5 0 0 1 17 7.5a3.75 3.75 0 0 1 .5 7.5z M8 18l-1 2.5 M12 18l-1 2.5 M16 18l-1 2.5` |
| 2 | Strijkers | Muziek | Ensemble · warme strijkers | `M3 12h2 M7 8v8 M11 5v14 M15 8v8 M19 10v4` |
| 3 | Akoestisch | Muziek | Gitaar · fingerpicking | `M12 3v9 M10 3h4 M12 12a4.5 4.5 0 1 0 0 9 4.5 4.5 0 0 0 0-9z M12 16.5h.01` |
| 4 | Beek in het bos | Natuur | Natuur · stromend water | `M3 9c2 0 2.5-2 4.5-2S10 9 12 9s2.5-2 4.5-2S19 9 21 9 M3 15c2 0 2.5-2 4.5-2S10 15 12 15s2.5-2 4.5-2S19 15 21 15` |
| 5 | Orgel | Muziek | Orgel · ingetogen | `M5 20v-8 M9 20V8 M12 20V4 M15 20V8 M19 20v-8 M3 20h18` |

Draw the icons with `CustomPaint` + `parseSvgPathData` (from `path_drawing`), or export them to SVG and use `flutter_svg` (already a dependency). Stroke caps and joins: round.

**Audio sources:** CC0/CC-BY loops from Musopen (piano, strings, organ), Freesound (rain, stream) and Kevin MacLeod / incompetech (acoustic). Save them as `.m4a`, 2–4 min seamless loops. Either bundle them in `assets/music/` (about 10–30 MB) or host them on the server and cache them on first play. **Check every licence, and add CC-BY credits to a "Muziek" section in settings.**

---

## Screens and components

Font: Inter everywhere. Colours used:
`ink #111827`, `ink2 #374151`, `muted #6B7280`, `faint #9CA3AF`, `line #E5E7EB`, `surface2 #F3F4F6`, `surface3 #F9FAFB`, `teal600 #0D9488`, `teal700 #0F766E`, `teal50 #F0FDFA`, `teal100 #CCFBF1`, `red600 #DC2626`, `red700 #B91C1C`, `red50 #FEF2F2`, `red200 #FECACA`.

### 1. Note button (reader tool row)
- 40×36 hit area, radius 10, music-note icon 20px, stroke 1.9, colour `ink`.
- While music is on: background `teal50`, icon `teal700`.
- Tap → if idle: open the **music list sheet**. If playing: open the **music menu sheet**.
- Hidden for non-Pro users? **No.** Show it and open the upgrade prompt on tap (a PRO badge appears in the sheet header for Pro users).

### 2. Music list sheet ("Kies muziek")
Modal bottom sheet, white, top radius 22, shadow `0 -8 30 rgba(17,24,39,.18)`, barrier `rgba(17,24,39,.28)`.
- Grabber 36×4, radius 2, `line`, 8px from top.
- Header row (padding 14 20 0): "Kies muziek" 17/700 `ink` · PRO badge (height 18, padding 0 6, 1px `#D1D5DB` border, radius 99, 9.5/700, letter-spacing .4, `teal700`) · spacer · "Sluit" 13.5/600 `teal600`.
- Body padding 4 20 34.
- Intro: "Rustige muziek zonder tekst. Speelt door als je verder leest." 13/1.5 `muted`, margin 6 0 12.
- **Search field:** height 40, radius 12, `surface2`, padding 0 12, search icon 16 `muted`, placeholder "Zoek muziek" 14/400. Filters on name + subtitle, case-insensitive.
- **Filter chips** (gap 6, margin 10 0 6): "Alles", "Muziek", "Natuur". Height 30, padding 0 12, radius 99, 12.5px. Selected: `teal600` bg, white text, 600. Unselected: white, 1px inset `line`, `ink2`, 500.
- **Rows** (padding 10 0, 1px `surface2` top border, gap 12):
  - Icon tile 42×42, radius 12. Natuur: `teal50` bg + `teal600` stroke. Muziek: `surface2` bg + `ink2` stroke. Icon 20px.
  - Name 14.5/500 `ink`. If it was the last track played, a "Laatst" pill sits beside the name: 10.5/600 `teal700` on `teal100`, padding 2 7, radius 99.
  - Subtitle 12/400 `faint`, 1px below.
  - Play circle 34×34, 1px inset `line`, play triangle 13px `ink2`.
- Empty state: `Niets gevonden voor "<query>"`, centred, 13.5 `faint`, padding 28 0.
- Tap row → `play(index)`, close the sheet, clear the search.

### 3. Pill (expanded player)
Overlay in `MainScaffold`, centred horizontally, **14px above the chapter pager** (the bar with Vorige / Volgende).
- 236×46, radius 99, white, shadow `0 6 20 rgba(17,24,39,.14)` + 1px `line` ring. Padding left 16, right 4, gap 8.
- Note icon 17 `teal600` · name 13.5/600, ellipsis · 1×20 divider `line` · pause/play 34×34 (icon 15 `ink`) · cross 34×34 (icon 15 `muted`).
- First time only: a hint above the pill (bottom 70): "Veeg omlaag om te verkleinen", 11.5/600 white on `teal700`, height 26, radius 99. Hide it after the first swipe (persist).
- **Tap the pill body or name → open the music menu.** Pause → `togglePause()`. Cross → `stop()`. The buttons must not also open the menu.
- **Swipe down > 24px → `shrink()`.** While dragging, translate the pill with the finger (down only). Release under 24px → spring back.

### 4. Bubble (shrunk pill, style "wit")
The same widget animates into the bubble. Don't swap it for a second widget.
- 44×44 circle, **16px from the right and 16px from the bottom** of the reading area. White, shadow `0 4 14 rgba(17,24,39,.12)` + 1px `line` ring. Only the note icon (17px, `teal600`) is visible. The other content fades out (opacity, 200 ms).
- Tap → `expand()`. If the reader is still scrolled (chrome hidden), shrink back automatically after **3.5 s**. A scroll of 60+ px also shrinks it, but no sooner than 600 ms after expanding.
- Animation: left/width/height/bottom/padding 350 ms `Cubic(.2,.8,.2,1)`. Background and shadow 250 ms.
- When the reader shows its chrome again (scrolled to top), the bubble stays a bubble until it's tapped.

### 5. Music menu sheet (final: light version of "donker")
Modal bottom sheet, white, top radius 22, same barrier and shadow as the list sheet.
- Grabber 36×4 `line`.
- Top row (padding 10 16 0): chevron-down 34×34 (closes, icon 18 `muted`) · centred "ACHTERGRONDMUZIEK" 11/600, letter-spacing 1.4, `muted` · PRO badge.
- Body: centred column, padding 18 24 32.
  - **Big circle** 128×128. Natuur: `teal50` bg + `teal600` icon. Muziek: `surface2` bg + `ink2` icon. Track icon 46px, stroke 1.6. Rings: `0 0 0 12 rgba(13,148,136,.06)`, `0 0 0 26 rgba(13,148,136,.03)`.
  - Name 22/700 `ink`, margin-top 30.
  - Status 13/400 `muted`, margin-top 5: `<subtitle part after "· "> · <status>`. Status is "Speelt door", "Gepauzeerd", or "Stopt na 15/30/60 min".
  - **Controls row** (gap 28, margin-top 22, top-aligned):
    - **Stop (red):** 48×48, radius 14, `red50` bg, 1px inset `red200`, stop square 11×11 radius 2.2 `red600`. Label "Stop" 11/600 `red700`, gap 6.
    - **Play/Pause:** 60×60 circle `teal600`, white icon 22, shadow `0 6 16 rgba(13,148,136,.28)`.
    - **Timer:** 48×48, radius 14, 1px inset `line`, clock icon 19 `ink2`. Label 11/500 `muted`: "Timer" or "15 min" etc. Tap cycles Uit → 15 → 30 → 60.
  - **Volume** (margin-top 20): speaker-low icon 18 `muted` · slider (`teal600` active) · speaker-high icon 18 `muted`.
  - **Track chips** (margin-top 18), horizontal scroll, gap 8, bleeding to the right edge: height 36, padding 0 13 0 10, radius 99, gap 7, 13px. Icon 15 (track icon). Selected: `teal50` bg, 1.5px inset `teal600`, `teal700`, 600. Unselected: white, 1px inset `line`, `ink2`, 500. Tap → `select(index)` (crossfade 400 ms, keeps playing).
- Stop → `stop()` and close the sheet.

### 6. "Muziek gestopt" message (undo)
- Left/right 16, 14px above the pager, height 46, radius 14, white, shadow `0 6 20 rgba(17,24,39,.14)` + 1px `line` ring, padding 0 14, gap 10.
- Note icon 16 `teal600` · "Muziek gestopt" 13.5/500 `ink` · "Ongedaan maken" 600 `teal600`.
- Shows for **4 s**. Undo → resumes the same track and position, with the pill expanded.
- Enter/exit: opacity 250 ms + translateY 16→0, 350 ms `Cubic(.2,.8,.2,1)`.

---

## Flow (matches the 7 steps in the prototype)
1. Tap the note in the reader tool row.
2. Pick a sound → it starts playing and the sheet closes.
3. The pill appears above the pager.
4. Swipe it down or scroll the chapter → it becomes a bubble in the corner.
5. Tap the bubble → it expands, then shrinks again after 3.5 s if the user is still reading.
6. Tap the pill → the music menu opens (pause, timer, volume, switch sound).
7. Stop (red button or the cross) → "Muziek gestopt" with undo.

## Edge cases
- Music keeps playing across tabs and routes. The pill/bubble shows on every tab except full-screen routes such as the paywall and onboarding.
- Respect reduced motion (`MediaQuery.disableAnimations`): no slide animations, only instant state changes.
- During the guided tour (`tourControllerProvider.active`), hide the pill.
- If Pro expires while music is playing, finish the current session and gate the next start.
- Persist: volume, last track, hint-seen. Don't auto-resume music on app launch.

## Files
- `Muziek prototype.dc.html`: the clickable prototype. Open it in a browser. Final settings: **kiezer = origineel**, **menu = donker**, **bubble = wit**.
- `support.js`: runtime the prototype needs to open.
- `CLAUDE_CODE_PROMPT.md`: paste this into Claude Code.
