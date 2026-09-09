# Avatar Notifications & Generative Scenes — implementation plan

Companion to `RETENTION_PLAN.md`. That document owns *when* a notification fires
(the nudge ladder, the cap, quiet hours, §4.3's type table). **This document owns
what it looks like**: the Levensboom on every notification, the burned-in streak
and countdown, and the generative nature scenes that replace the daily-verse
photographs.

Goal: a first-week user who has downloaded the app and drifted gets a notification
that is unmistakably *theirs* — their tree, their streak, their remaining hours —
in the same visual language as the app. The Duolingo pattern (mascot + streak
number + "left to keep your streak"), executed with the tree.

Scope decision: **one release, nothing ships half-done** (D14).

---

## 0. Decisions taken

| # | Decision | Value |
|---|---|---|
| D1 | Which types carry the image | **All of them**, `dailyVerse` included |
| D2 | Image content | Tree + streak number + remaining time, burned into the PNG |
| D3 | iOS depth | `DarwinNotificationAttachment` + a proper thumbnail crop. **No** Notification Content Extension, **no** Live Activity |
| D4 | Android depth | `BigPictureStyle` + progress. (See D7 — the existing action buttons are removed) |
| D5 | Render moment | On app → `paused`, one image per type; the per-day countdown text is burned per scheduled day |
| D6 | Countdown meaning | **Until midnight** — matches `retentionDayKey()`, always true |
| D7 | Action buttons | **None.** ⚠️ See §10: buttons already exist today; this is a removal |
| D8 | Daily-verse art | Generative scenes in avatar style, seed = the date; the 76 JPGs are deleted |
| D9 | Motion | Slow light shift + drifting clouds; off under `MediaQuery.disableAnimations` |
| D10 | Daily-verse notification | Same generative scene, verse burned in |
| D11 | Streak number source | Server streak, local `RetentionStore.state.localStreak` as fallback |
| D12 | Name in copy | Only `milestone` and win-back (`dormant`/`treeWilting`) |
| D13 | Framing on risk | Loss frame — the tree as it will look tomorrow (as `treeWilting` already does) |
| D14 | Rollout | One release |
| D15 | Permission timing | Multiple earned triggers, first one wins |
| D16 | `dailyVerse` and the cap | Stays exempt from the ≤1/day engagement cap |
| D17 | Settings preview button | No |
| D18 | Plan location | This file; `RETENTION_PLAN.md` stays the source for the ladder itself |

---

## 1. Current state

### Already built (do not rebuild)

- `lib/core/notifications/notification_service.dart`
  - `NotifType` = `studyReminder, streakAtRisk, streakLost, lessonHalfway,
    weeklyGoal, milestone, dormant, dailyVerse, treeWilting` with id ranges,
    channels, quiet-hour clamping, deep-link tap handling.
  - `_detailsFor(...)` (`:395`) already accepts `TreeImageFiles?` and maps it to
    `FilePathAndroidBitmap` large icon + `BigPictureStyleInformation` + a Darwin
    attachment. **The image pipe exists; almost nothing feeds it.**
- `lib/features/levensboom/data/tree_image.dart` — `renderTreeImages()` paints
  `TreePainter` through a `PictureRecorder` with no widget tree, writes a
  1024×640 scene PNG and a 256×256 portrait, has a 400 ms budget and degrades to
  scene-only, returns `null` on any failure.
- `lib/core/notifications/notification_scheduler.dart` — `_PlannedNotification`
  carries `images` (`:167`); only two producers set it: `treeWilting` with
  `healthOverride: 0.5` (`:524`) and `milestone` (`:646`).
- Permission is already **earned**, not asked in onboarding: `setup_flow_screen.dart`
  only writes intent (`pendingPermissionRequest`), and the Dutch pre-permission
  sheet + `requestPermission()` runs after the first finished lesson
  (`lesson_screen.dart:333`). `RETENTION_PLAN.md` §4.6 describes exactly this.
- `lib/features/levensboom/domain/scenes.dart` — 8 `SceneSpec`s, `Backdrop`
  enum (`meadow, hills, lake, dunes, mountain, wall, garden, stars`), `SkyStops`.
- `tree_view.dart` (1467 lines) — `TreePainter` paints sky, backdrop, tree and
  decor; backdrop routines live at `:581`–`:880`.
- `daily_verse_card.dart` (1163 lines) — `_VerseFace` (`:309`) draws
  `Image.asset(photo)` (`:350`), `_PhotoScrim` (`:700`), and a hard-coded
  `const List<String> _photos` of 76 entries at `:1002`.

### The gap

1. Seven of nine notification types are text-only.
2. No streak number, no countdown, no level — the image is the tree alone.
3. The daily verse uses stock photography (5.1 MB of JPGs) that has nothing to do
   with the avatar.
4. Permission is asked at exactly one moment; a reader who never starts a *study*
   never sees the ask.

---

## 2. Architecture

Three new units, one extraction, no new dependencies.

```
levensboom/present/tree_view.dart
        │  (extract, no behaviour change)
        ▼
levensboom/present/backdrop_painter.dart      ← sky + backdrop, tree-free
        │
        ├──────────────► levensboom/domain/verse_scene.dart      (D8)
        │                   seed = date → SceneSpec + cloud/light params
        │
        └──────────────► levensboom/data/notification_canvas.dart (D2)
                            scene/tree + chrome (streak, countdown, level)
                                   │
                                   ▼
                            core/notifications/notification_art.dart
                              lifecycle, cache, file naming, budgets
                                   │
                                   ▼
                            notification_scheduler.dart  (feeds `images:`)
```

### 2.1 `backdrop_painter.dart` (extraction)

Move the sky-gradient and `Backdrop` switch out of `TreePainter` into free
functions:

```dart
void paintSky(Canvas canvas, Size size, SkyStops stops);
void paintBackdrop(Canvas canvas, Size size, Backdrop backdrop,
    TreePalette palette, TreeDecor decor, {double timeMs = 0, double parallax = 0});
```

`TreePainter` then calls them. Pure refactor — **`tree_generator.dart`,
`species.dart`, `catalog.dart` and `stages.dart` are not touched**, so
`test/levensboom_parity_test.dart` and the website mirror in `lib/levensboom/*.ts`
stay untouched. (CLAUDE.md's "edit both repos in one pass" rule does not apply
here: the painter is Flutter-only.)

### 2.2 `verse_scene.dart` (new, domain)

```dart
class VerseScene {
  final Backdrop backdrop;
  final SkyStops sky;
  final double cloudSeed, lightPhase;
  final Brightness textOn;   // which scrim/typography the card must use
}
VerseScene verseSceneForDay(DateTime day);   // deterministic, seed = yyyymmdd
```

- Seed via the existing `rng.dart` hash so the same day gives the same scene on
  every device (a shared daily image the reader can screenshot and send on).
- ~20 distinct looks come from `backdrop × sky palette × time-of-day tint`, not
  from 20 hard-coded specs: 8 backdrops × dawn/day/dusk/night skies × cloud seed.
- `textOn` is computed from the sky's luminance so the verse never lands white on
  a pale dawn.
- Golden rule: **no tree in the verse scene by default.** The daily verse is the
  Word, not the avatar; the tree appears only in the notification variant if we
  later want it (D10 keeps it scene-only).

### 2.3 `notification_canvas.dart` (new, data)

One function, one output, driven by a small spec object:

```dart
enum NotifArtKind { tree, verse }

class NotifArtSpec {
  final NotifArtKind kind;
  final TreeState? tree;          // required for kind.tree
  final double? healthOverride;   // loss frame (D13)
  final VerseScene? scene;        // required for kind.verse
  final int? streak;              // burned streak chip, null = no chip
  final String? countdown;        // 'Nog 3 uur' — already resolved to text
  final int? level;               // progress ring
  final double? levelFrac;
  final String? verseText, verseRef;
}

Future<NotifArtFiles?> renderNotificationArt(NotifArtSpec spec, {String name});
```

Renders through the same `PictureRecorder` path `tree_image.dart` already proved.
`tree_image.dart`'s `renderTreeImages` becomes a thin wrapper over this so the two
existing call sites keep working during the refactor.

**Chrome layer** (drawn on top of the scene, inside the canvas):

- Streak chip, bottom-left: flame glyph + big numeral + `dagen`. Numeral in the
  same display face the app uses for the streak ring; drawn with `TextPainter`.
- Countdown pill, bottom-right: `Nog 3 uur` (D6). Omitted when the type has no
  deadline.
- Level ring, top-right: thin arc, `Niveau 6` under it. Omitted on `verse` art.
- A bottom scrim (`LinearGradient`, transparent → 55 % ink) so chrome stays legible
  on any sky.

### 2.4 Canvas geometry

| Output | Size | Consumer | Notes |
|---|---|---|---|
| `*-scene.png` | 1024×512 (2:1) | Android `BigPictureStyle`, iOS attachment full view | 2:1 is Android's expanded ratio; 1024×640 today gets cropped top and bottom |
| `*-thumb.png` | 512×512 | iOS attachment thumbnail, Android `largeIcon` | iOS centre-crops the attachment for the collapsed banner — a square render is the only way to control what survives (D3) |
| Safe area | inner 6 % margin | both | Chrome never inside the outer 6 %; Android OEMs crop differently |

`hideExpandedLargeIcon: true` stays, so the thumbnail disappears when expanded and
the 2:1 scene owns the expanded view.

---

## 3. Render lifecycle (D5)

**Where:** a new `core/notifications/notification_art.dart`, called from the
existing `app_lifecycle` hook that already re-arms `dormant` on `paused`.

**What runs on `paused`:**

1. Read `TreeState` (already in memory) and the streak (see §5).
2. Render **one image per art variant**, not per scheduled notification:
   - `tree-healthy` — current health, growth frame
   - `tree-wilting` — `healthOverride: 0.5`, loss frame
   - `tree-milestone` — celebration flag on
   - `verse-<yyyymmdd>` — today's and tomorrow's verse scene
3. Countdown text differs per scheduled day, so chrome is drawn in a **second,
   cheap pass**: the base scene PNG is decoded once and re-composited with the
   day's chip text into `<type>-<slot>.png`. Rendering the tree is the expensive
   part (~120–250 ms); re-compositing chrome is ~10 ms.
4. Total budget **900 ms**, checked between steps like `tree_image.dart` already
   does. Over budget → keep what exists, skip the rest, log nothing.
5. Files live in `getTemporaryDirectory()/levensboom/notif/`, overwritten by name,
   never accumulating. A sweep deletes anything older than 21 days on each run.

**Failure is always silent and always degrades to text.** `images == null` already
produces a valid, plain notification.

**Staleness rule:** if the newest art is older than 7 days (app not opened), the
scheduler falls back to the `tree-wilting` art for every type — which is exactly
right, because a 7-day absence means the tree *has* wilted.

---

## 4. Per-type wiring (D1, D12, D13)

`notification_scheduler.dart` gains one helper, `_artFor(NotifType, ctx)`, and
every `_PlannedNotification` gets `images:` from it.

| Type | Art | Frame | Streak chip | Countdown | Name in copy |
|---|---|---|---|---|---|
| `studyReminder` | `tree-healthy` | growth | yes, if ≥ 2 | — | no |
| `streakAtRisk` | `tree-wilting` | **loss** | yes | **yes** (to midnight) | no |
| `streakLost` | `tree-wilting` | loss | shows the streak that was lost | — | no |
| `lessonHalfway` | `tree-healthy` | growth | yes, if ≥ 2 | — | no |
| `weeklyGoal` behind | `tree-healthy` | growth | week progress instead of streak | days left in week | no |
| `weeklyGoal` met | `tree-milestone` | growth | yes | — | no |
| `milestone` | `tree-milestone` | growth | yes | — | **yes** |
| `dormant` | `tree-wilting` | loss | last known streak | — | **yes** |
| `treeWilting` | `tree-wilting` | loss | yes | — | **yes** |
| `dailyVerse` | `verse-<date>` | — | no | — | no |

Copy stays in `notification_copy.dart`; add a `{name}` token resolved from the
profile's first name, and **only** register it in the `milestone`, `dormant` and
`treeWilting` pools (D12). Empty name → the variant falls back to a nameless line
in the same pool, never to `", je boom..."`.

New Dutch lines needed (§5 of `RETENTION_PLAN.md` gets the additions):

- `streakAtRisk` with a countdown now says the number in the body too, because the
  burned text does not scale with the OS font size: *"Nog 3 uur om je reeks van 12
  dagen te bewaren."*
- `milestone` with name: *"{name}, je boom staat op niveau {level}."*
- `dormant`/`treeWilting` with name: *"{name}, je boom mist wat licht."*

---

## 5. Streak number (D11)

```
serverStreak = DashboardData.streak from the cached dashboard
localStreak  = RetentionStore.state.localStreak
```

Rule, in `notification_art.dart`:

1. If the cached dashboard is < 36 h old → use `serverStreak`.
2. Else → use `localStreak`.
3. If both are absent or the value is < 2 → **draw no chip.** A "1" is not a
   streak and drawing it teaches the reader the number is noise.

`reconcileServerStreak()` already exists and runs on dashboard load, so the two
converge on every open.

---

## 6. Daily verse: generative scenes (D8, D9, D10)

### 6.1 In-app card

- `_VerseFace` (`daily_verse_card.dart:309`) swaps `Image.asset(photo)` for a
  `CustomPaint(painter: VerseScenePainter(scene, timeMs))`.
- `_PhotoScrim` stays; its opacity becomes a function of `scene.textOn`.
- `_ExpandedVerseScreen` (`:600`) uses the same painter at full-bleed size, sharing
  the existing hero tag `daily-verse-card`.
- Delete `const List<String> _photos` (`:1002`–`:1163`) and
  `assets/images/daytext/` (76 files, 5.1 MB); drop the `assets/images/daytext/`
  line from `pubspec.yaml`. History keeps them (commit `33061f8`).

### 6.2 Motion (D9)

One `Ticker` in `_DailyVerseCardState`, driving a single `timeMs`:

- Light: the sky gradient's stop positions shift on a 90-second sine — a slow
  brightening and dimming, never more than 4 % luminance.
- Clouds: 2–3 blurred blobs translating at 6–14 px/minute, wrapping at the edge.
- Nothing else moves. No particles (D9 chose light + clouds).
- **Stops entirely** when: `MediaQuery.of(context).disableAnimations` is true, the
  card is off-screen (`VisibilityDetector` is not a dependency — use the existing
  scroll-aware pattern in `dashboard_screen.dart`), or the app is not `resumed`.
- Target: ≤ 1 % CPU on a mid-range Android. The painter repaints only the sky and
  cloud layers; the backdrop silhouettes are cached in a `Picture`.

### 6.3 Notification variant (D10)

`verse-<yyyymmdd>.png` = the same scene, plus the verse text and reference burned
in at 1024×512, and the reference repeated in the notification body so screen
readers and large-font users still get it. Text is wrapped by `TextPainter` and
**truncated at 180 characters** with an ellipsis — long verses go to the app.

---

## 7. Permission triggers (D15)

Keep the existing post-first-lesson sheet. Generalise it into one place so every
trigger shows the same sheet and the same guard applies:

**New:** `lib/core/notifications/permission_moment.dart`

```dart
enum PermissionMoment { firstLesson, chaptersRead, firstStreak, firstMilestone }
Future<void> maybeAskForNotifications(WidgetRef ref, PermissionMoment moment);
```

Guard: the existing `RetentionStore.markPermissionAsked()` /
`state.permissionAsked` — **asked once, ever**, whichever moment lands first.
After a "Nu niet", the only way back is Settings (unchanged).

Triggers, each firing only on a *success* moment, never on app open:

| Moment | Hook | Condition |
|---|---|---|
| `firstLesson` | `lesson_screen.dart:333` (exists) | first `_finish` success |
| `chaptersRead` | `read_screen.dart`, where a chapter is marked read | 3rd distinct chapter in `readChapters` |
| `firstStreak` | `RetentionStore.markCompleted()` | `localStreak` reaches 2 |
| `firstMilestone` | milestone detection in the scheduler | first badge or first study finished |

Sheet copy stays as `RETENTION_PLAN.md` §4.6 has it, with one added line for the
non-lesson moments: *"Je hebt net je derde hoofdstuk gelezen."* / *"Twee dagen op
rij — mooi."* The tree is drawn in the sheet (reuse `MiniTree`) so the ask is
visually continuous with what the notification will look like.

Hard rule, unchanged: **never in onboarding, never on first launch.**

---

## 8. Frequency and suppression (D16)

- `dailyVerse` stays exempt from the ≤1/day engagement cap; `milestone` stays
  exempt. Everything else keeps `RETENTION_PLAN.md` §4.4's ladder untouched.
- Practical ceiling per day: 1 daily verse + 1 nudge (+ a rare milestone).
- The art layer changes nothing about *when* anything fires.

---

## 9. Testing

| Test | File | Asserts |
|---|---|---|
| Scene determinism | `test/verse_scene_test.dart` (new) | same date → identical `VerseScene`; 30 consecutive days produce ≥ 12 distinct backdrop+sky pairs |
| Chrome layout | `test/notification_canvas_test.dart` (new) | streak chip omitted at `streak < 2`; countdown omitted without a deadline; text never crosses the 6 % safe area |
| Art selection | `test/notification_art_test.dart` (new) | `_artFor` returns wilting art for `streakAtRisk`/`dormant`, milestone art for `milestone`, verse art for `dailyVerse` |
| Streak source | same file | dashboard < 36 h wins; stale dashboard falls back to local; `< 2` draws nothing |
| Permission | `test/permission_moment_test.dart` (new) | four moments, first one asks, the rest are no-ops |
| Parity | `test/levensboom_parity_test.dart` (existing) | **must stay green untouched** — proof the extraction did not reach the generator |
| Regression | `test/screen_render_test.dart` (existing) | dashboard still renders with the painter replacing the photo |

Run individually (`flutter test test/<file>.dart`), per CLAUDE.md. Golden images
are *not* added — they are brittle across platforms and the canvas is already
covered by layout assertions.

---

## 10. ⚠️ Flagged: the action buttons already exist

D7 says "no buttons". But `notification_service.dart:418` already ships
`AndroidNotificationAction('LATER', 'Later vandaag')` and `('OPEN', 'Openen')` for
every capped type, with the iOS `engagement` category behind it and a handler
wired through `NotificationService.onAction`.

So D7 is a **removal of working behaviour**, not the addition of nothing. My
question implied Android had no buttons; that was wrong.

Recommendation: keep `Later vandaag` (a snooze is the cheapest way to avoid a
notification being swiped away, and it is the one control that prevents an
uninstall), drop nothing else. If the decision stands as answered, the change is:
delete the `actions:` block at `:418`, delete `_engagementCategory` from the iOS
details, and drop the now-dead `onAction` branch. **Confirm before I remove it.**

---

## 11. Risks and limits

| Risk | Mitigation |
|---|---|
| iOS attachment size — Apple caps images around 10 MB and validates on delivery | 1024×512 PNG lands at 150–400 KB. Assert < 2 MB before attaching; skip the attachment above that |
| Android big-picture bitmap memory on low-RAM devices | 1024×512 ARGB ≈ 2 MB, well inside the notification bitmap budget; `hideExpandedLargeIcon` avoids holding two |
| Burned text does not scale with OS font size (accessibility) | Every burned fact is repeated in the title/body, which do scale. Nothing is image-only |
| Countdown burned at schedule time drifts if the device sleeps across a day boundary | Text is per scheduled day (§3.3) and says "to midnight", which is the same statement all day |
| The tree changes after art is rendered but before the notification fires | Art re-renders on every `paused`; worst case the tree is one session out of date. Acceptable — it is a portrait, not a dashboard |
| Removing 76 assets breaks a test fixture | `test/screenshot_fixtures.dart` (66 KB — grep, never open) must be checked for `daytext` references before deletion |
| App Review | No new entitlement, no new target, no background execution. Nothing here changes the review surface (D3 deliberately avoids the extension) |
| Website parity | Untouched. Only the Flutter painter is refactored |

---

## 12. Work packages (one release, D14)

**WP1 — extraction, no behaviour change**
- [x] `tree_view.dart` → new `backdrop_painter.dart`; `TreePainter` delegates.
- [x] `flutter test test/levensboom_parity_test.dart` green, unchanged.

**WP2 — canvas**
- [x] `notification_canvas.dart`: `NotifArtSpec`, `NotifArtFiles`,
      `renderNotificationArt`, chrome (streak chip, countdown pill, level ring,
      scrim), 1024×512 + 512×512.
- [x] `tree_image.dart` becomes a wrapper; its two existing call sites unchanged.
- [x] `test/notification_canvas_test.dart`.

**WP3 — verse scenes**
- [x] `verse_scene.dart` + `VerseScenePainter`.
- [x] `test/verse_scene_test.dart`.

**WP4 — lifecycle**
- [x] `notification_art.dart`: render-on-paused, cache dir, naming, 900 ms budget,
      21-day sweep, staleness rule, streak source (§5).
- [x] `test/notification_art_test.dart`.

**WP5 — scheduler wiring**
- [x] `_artFor(NotifType, ctx)` in `notification_scheduler.dart`; every planned
      notification gets `images:` per §4's table.
- [x] `notification_copy.dart`: `{name}` token, new countdown-aware
      `streakAtRisk` lines, name variants for `milestone`/`dormant`/`treeWilting`.

**WP6 — daily verse**
- [x] `daily_verse_card.dart`: painter replaces `Image.asset`, ticker for motion,
      reduce-motion + off-screen + not-resumed guards, expanded screen.
- [x] Delete `_photos`, delete `assets/images/daytext/`, drop the `pubspec.yaml`
      asset line — **after** grepping `test/screenshot_fixtures.dart`.
- [x] `dailyVerse` art in the scheduler (verse burned in, 180-char truncation).

**WP7 — permission moments**
- [x] `permission_moment.dart`; refactor `lesson_screen.dart:333` onto it.
- [x] Hooks in `read_screen.dart` (3rd chapter), `retention_store.markCompleted`
      (streak 2), milestone detection (first badge/study).
- [x] `MiniTree` in the sheet; `test/permission_moment_test.dart`.

**WP8 — close-out**
- [ ] D7 resolution (§10) - still open, see below.
- [x] `flutter analyze` clean; the affected test files green individually.
- [x] `RETENTION_PLAN.md` §4.6 and §5 updated to point here.

---

## 13. Metrics to watch after release

Additions to `RETENTION_PLAN.md` §9: permission grant rate split by
`PermissionMoment`; notification → open rate split by `NotifType` and by
image-present; `streakAtRisk` open rate before/after the countdown; daily-verse
card dwell time after the photo swap; uninstall rate in the first 7 days.

---

## 14. As built (2026-09-09)

WP1–WP7 are implemented; `flutter analyze lib` is clean and every affected test
file passes individually. Five things landed differently from §2–§7, all of them
simplifications found while wiring it up:

1. **Art is rendered from the scheduler's write loop, not from a separate
   on-`paused` pass.** `NotificationScheduler.recompute` already runs on both
   `resumed` and `paused`, and it is the only place that knows which candidates
   survived the ladder. `NotificationArt` is created per run, renders lazily and
   memoises by art name, so the fourteen `dailyVerse` one-shots of a batch share
   one render and a candidate the ladder dropped costs nothing. Same effect as
   §3, fewer renders.
2. **No per-day countdown re-composite.** `streakAtRisk` is a today-only
   notification (`RETENTION_PLAN.md` §4.3), so exactly one countdown image is
   ever live. The "decode the base PNG and re-draw the chrome" pass in §3.3 was
   never needed.
3. **D11 needed no new bookkeeping.** `RetentionStore.reconcileServerStreak`
   already adopts the server streak wholesale, so `state.localStreak` *is* the
   server value whenever the dashboard has been seen, and carries on locally
   between opens — which is the rule §5 asked for.
4. **`RetentionState.completionsEver` is new** (persisted alongside
   `localStreak`), incremented in `markCompleted`. It is what makes the counted
   permission moments possible: "three chapters" was not derivable from anything
   the store already kept.
5. **`test/screen_render_test.dart` now pumps under
   `MediaQuery(disableAnimations: true)`.** The Start tab carries ambient motion
   now, and `pumpAndSettle` never settles while an animation runs. This is the
   same switch `screenshots_test.dart` already used, and the widget honours it in
   production too.

### Files

| New | |
|---|---|
| `lib/features/levensboom/present/backdrop_painter.dart` | `TreeFraming`, `TreeDecor`, `TreeFrame`, `measureTreeFrame`, `extentWithAnimals`, `mixin SceneLayers` (sky, clouds, far/near backdrop, ground, foreground, animals) |
| `lib/features/levensboom/domain/verse_scene.dart` | `VerseScene`, `verseSceneForDay`, `verseSceneKey`, `verseScenePalette` |
| `lib/features/levensboom/present/verse_scene_painter.dart` | `VerseSceneArt` (day-cached), `VerseScenePainter` |
| `lib/features/levensboom/present/verse_scene_backdrop.dart` | the animated widget: 5 fps, stops on reduced motion and off-route |
| `lib/features/levensboom/data/notification_canvas.dart` | `NotifArtSpec`, `renderNotificationArt`, the chrome (streak chip, countdown pill, level ring, scrim, verse) |
| `lib/core/notifications/notification_art.dart` | per-run art policy, memo, budget, `hoursToMidnight`, `sweep` |
| `lib/core/notifications/permission_moment.dart` | `PermissionMoment`, `permissionMomentEarned`, `maybeAskForNotifications`, `maybeAskAfterReading`, the sheet with `MiniTree` |
| `test/verse_scene_test.dart`, `test/notification_art_test.dart`, `test/permission_moment_test.dart` | 19 tests |

| Changed | |
|---|---|
| `tree_view.dart` | −740 lines, mixes in `SceneLayers`, re-exports the moved types |
| `tree_image.dart` | now a wrapper over `renderNotificationArt` |
| `notification_scheduler.dart` | `NotificationArt` in the write loop; `{hours}` token for `streakAtRisk`; eager `renderTreeImages` calls removed |
| `notification_copy.dart` | `ar9`/`ar10` (hours in words), `tw5`/`dm8` (name on the win-backs) |
| `retention_store.dart` | `completionsEver` |
| `daily_verse_card.dart` | `VerseSceneBackdrop` replaces `Image.asset`; `_photos` and `dailyVersePhoto` deleted |
| `lesson_screen.dart`, `read_screen.dart` | both go through `permission_moment.dart` |
| `pubspec.yaml`, `assets/images/daytext/` | asset line and 76 JPGs (5.1 MB) removed |

### Follow-up: art is not repainted while nothing has changed

`NotificationArt._render` names each file after a fingerprint of everything that
would make the picture different - seed, level, progress, health, species,
scene, animal, streak, countdown, celebration - and reuses the file on disk when
that fingerprint is unchanged. The scheduler runs on every foreground *and*
every background, so without this each app open repainted a tree and encoded two
PNGs identical to the ones already cached, competing with the Start tab for the
same frames. Superseded fingerprints for a kind are deleted as soon as a new one
is written, so the cache holds one picture per kind rather than one per day.

### Still open

- **D7 (§10).** The action buttons were left in place. They already existed and
  work; removing them is a deliberate loss of the snooze, so it waits for a
  decision rather than being done silently.
