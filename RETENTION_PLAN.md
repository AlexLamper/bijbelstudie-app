# Retention & Re-engagement Plan — BijbelStudie mobile

Goal: make people come back on **their chosen study cadence** (daily, 3×/week, weekly, …)
the way Duolingo does, but tasteful — quiet, encouraging, scripture-flavoured, never
guilt-tripping, never spammy. Hard ceiling: **≤ 1 engagement notification per day**
(+ optionally the daily verse), and **never a notification for something already done**.

All paths are relative to `bijbelstudie_mobile/` unless noted. The Next.js backend is the
**separate** repo `C:\Projects\bijbelstudie`.

---

## 1. Current state

### Already exists

| Area | What | File / symbol |
|---|---|---|
| Local notif plugin | `flutter_local_notifications: ^18.0.1`, `timezone: ^0.10.0` | `pubspec.yaml:59-60` |
| Notif service | `ReminderService` — one type only ("daily reading reminder"). `initialise()`, `requestPermission()`, `scheduleDaily({hour,minute})`, `cancelDaily()`, `currentStatus()` → `ReminderStatus(available,permitted,pending)` | `lib/core/notifications/reminder_service.dart`; `reminderServiceProvider` |
| Rolling copy | Fetches a 14-day batch of pre-personalised variants from backend `GET /api/v1/notifications/copy?type=daily_reading&days=14`, caches in SharedPreferences (`reminder_copy_batch_v1`), `bundledFallback` (4 Dutch variants), `batchDays=14`, `refetchWhenRemainingBelow=5`, `.cacheOnly()` ctor for cold start | `lib/core/notifications/reminder_copy.dart`; `ReminderVariant{variantId,title,body,deepLink}`, `ReminderCopySource` |
| Session top-up | `reminderCopyRefreshProvider` — once per session from dashboard, re-arms batch if `needsRefresh()` | `lib/core/notifications/reminder_refresh.dart` |
| Cold-start re-arm | `_initReminders()` reads `kDailyReminderMinutesKey`, re-schedules from cache | `lib/main.dart:57-122` |
| Notif IDs / channel | Single Android channel `daily_reading` / "Dagelijkse herinnering", `Importance.defaultImportance`. IDs `1001..1014` (`_dailyReminderId=1001`, one one-shot per day, **not** `matchDateTimeComponents`), `AndroidScheduleMode.inexactAllowWhileIdle`, `UILocalNotificationDateInterpretation.absoluteTime` | `reminder_service.dart:33-49,107-123` |
| Streak (server) | `POST /streak` → `StreakResult{streak,freezes,newBadges}`. Server owns all rules: bump once/calendar-day, spend a freeze to bridge one missed day (**Pro only**), grant a freeze every 5th day, re-evaluate badges | `lib/features/dashboard/data/dashboard_repository.dart:75-82,145-169` |
| Streak (display) | `DashboardData{streak, freezes, weekDays:List<WeekDay>, weekTotal, badges:List<String>, lastRead, readChapters}` from single `GET /dashboard` | `lib/features/dashboard/data/dashboard_models.dart:164-265`; `dashboardProvider` (autoDispose) in `lib/features/dashboard/present/dashboard_providers.dart:8` |
| Home streak pill | Header shows `if (data.streak > 0)` → "`N dag/dagen`" pill; `_HeroCard` = continue-**reading** (chapter) card; `DailyVerseCard` | `lib/features/dashboard/present/dashboard_screen.dart:137-142,161,179,215` |
| Local study progress | `StudyPlan{studyId,versionId,commentaryId,cadence,completedDays:Set<int>,startedAt}`; `StudyCadence{daily,everyOtherDay,threePerWeek,weekly,ownPace}` with `.lessonsPerWeek` (7 / 3.5 / 3 / 1 / null) + Dutch `.label`; persisted to SharedPreferences key `studies.plans` (one JSON blob); `setLessonDone`, `start`, `reset` | `lib/features/studies/data/study_plan_store.dart`; `studyPlansProvider` |
| Server enrollment (already models cadence + reminders!) | `StudyEnrollment{status, rhythm:StudyRhythm, reminderDays:List<int> (0=Sun), depth, currentLessonDay, currentStep:StudyStep, lessonsTotal, lessonsCompleted, remindersEnabled, reminderMinutes, reminderTimezone, startedAt, lastActivityAt, completedAt}`; `StudyRhythm{daily,threePerWeek(Mon/Wed/Fri),weekly,ownDays,free}`; `.progress`, `.resumeStep` | `lib/features/studies/data/enrollment_models.dart`; `enrollment_repository.dart` (`/study-enrollments` CRUD); `studyEnrollmentsProvider` |
| Lesson completion | `lesson_screen.dart::_finish()` → `lessonRepository.complete(studyId, day, completeStep, reflectionText)` (`POST … complete:true`, server grants XP / rolls enrollment) → `ref.invalidate(serverStudyLessonsProvider)` + `ref.invalidate(studyEnrollmentsProvider)` → `LessonCompleteCard` ("Les X van Y afgerond" / "Studie afgerond") | `lib/features/study/present/lesson/lesson_screen.dart:186-220`; `lesson_repository.dart:117-181`; `lesson_complete_card.dart` |
| Mid-lesson cursor | `_bestEffort()` fire-and-forget patches `currentStep` on lesson open and every step move → **"left halfway" state is already captured server-side** (`enrollment.currentStep`, `currentLessonDay`) | `lesson_screen.dart:100-142` |
| Chapter read ping | `read_screen.dart:217` → `dashboardRepository.recordRead(...)` (server marks read + logs session) | `lib/features/bible/present/read_screen.dart:175,217` |
| Permission ask (today) | Requested **during onboarding**, wizard step 3 (`_reminderPresets`), `service.requestPermission()` | `lib/features/onboarding/present/setup_flow_screen.dart:441-464` — and from settings on enable |
| Settings UI | `_ReminderSection` / `_ReminderTile`: single toggle + `showTimePicker` (default 08:00); enable → `requestPermission()` + `scheduleDaily`; disable → `cancelDaily()` + `setDailyReminder(null)`; `_reminderStatusProvider` | `lib/features/settings/present/settings_screen.dart:221-337` |
| Reminder pref storage | `ReadingSettings.dailyReminderMinutes` (int? minutes past midnight), `.dailyReminderTime`; key `kDailyReminderMinutesKey='app.dailyReminderMinutes'` (public for `main.dart`); `setDailyReminder(int?)` | `lib/features/settings/data/reading_settings.dart:155,170-188,232,348-358`; `readingSettingsProvider` |
| Local-state precedent | SharedPreferences-backed Notifier stores: `studies.plans`, `daytext.history` (`DailyVerseStore`, capped list). `ContentCache` (sqflite `bijbelstudie_content.db`) is **chapter cache only** — not for retention state | `daily_verse_store.dart`; `lib/core/db/content_cache.dart:20-73` |

### Missing / broken

- **`tz.local` is never set.** `reminder_service.dart` calls `tz.initializeTimeZones()` but
  never `tz.setLocalLocation(...)`, and there is **no `flutter_timezone` dependency**. So
  `tz.local` = UTC and `_nextInstanceOf()` builds the fire time in UTC. A user in UTC+2 who
  picks 08:00 is reminded at **10:00 local**. This must be fixed in Phase 1 (add
  `flutter_timezone`, call `tz.setLocalLocation` in `initialise()`).
- **No notification-tap handler.** `_plugin.initialize()` passes no
  `onDidReceiveNotificationResponse`; no `getNotificationAppLaunchDetails()` call.
  `payload: variant.deepLink` is written but nothing consumes it — tapping the reminder
  just opens the app wherever it was.
- **App never calls `POST /streak`.** `bumpStreak()` has no caller in `lib/` (only the repo
  definition + a preview stub). The server streak advances only as a side effect of other
  endpoints, if at all.
- **No notion of "studied today" on-device**, so no local logic can suppress a reminder for
  a day already done.
- **One notification type, one channel.** No streak-at-risk, no halfway, no win-back, no
  weekly-goal, no milestone, no dormant, no daily-verse notification.
- **No frequency cap / priority ladder / quiet hours.**
- **Reminder is cadence-blind.** It fires every day regardless of the user picking
  "3× per week"; it does not read `StudyCadence` / `StudyRhythm` at all.
- **No home re-entry surface** beyond the reading hero and a bare streak pill: no
  weekly-goal ring, no "continue **lesson**", no "not done today" nudge.
- **Two parallel cadence models** — local `StudyCadence` (`study_plan_store.dart`) and
  server `StudyRhythm` (`enrollment_models.dart`). Only the server one carries
  `reminderDays` / `reminderMinutes` / `reminderTimezone`.
- **Permission asked too early** (onboarding wizard, before any value delivered).

---

## 2. Streak & progress model

### Principle

The server streak (`GET /dashboard.streak`) stays the **source of truth for the number we
display and celebrate**. Everything local is a best-effort mirror used only to decide
whether to *nudge*. A wrong nudge is cheap; a wrong streak is not.

### Two shapes, chosen by cadence

| Cadence (`StudyRhythm` / `StudyCadence`) | Model | Goal | "Streak" unit |
|---|---|---|---|
| `daily`, `everyOtherDay`, `ownPace` | **Daily streak** | ≥ 1 completion today | consecutive qualifying **days** |
| `threePerWeek` | **Week goal** | 3 completions in the ISO week | consecutive **weeks** goal met |
| `weekly` | **Week goal** | 1 completion in the ISO week | consecutive weeks met |
| `ownDays` | **Week goal** | `reminderDays.length` completions/week | consecutive weeks met |
| `free` | none | — | show progress bar only, no streak, no nudges |

A "completion" = a finished lesson (`lesson_screen::_finish` success) **or** a recorded
chapter read (`read_screen` `recordRead`) — matching what the server already counts.

### Freeze / grace day

- **Daily-streak users:** one **grace day** ("vriesdag") per rolling 7 days. If exactly one
  qualifying day is missed and `streak >= 3`, the streak is shown as *held* ("beschermd")
  rather than reset. Mirror the server: surface `DashboardData.freezes`; show a small
  snowflake on the ring when a freeze is banked. Do **not** invent a second freeze economy —
  read the server's count, and locally allow the *display* to survive one gap while we wait
  for the next `/dashboard` to confirm.
- **Week-goal users:** a week counts as met if completions are **within 1 of target** *and*
  the previous week was met ("zachte week"). At most one soft week per 4.
- Never show "streak lost" the instant a day rolls over — only after the *grace* window also
  lapses, and only in a warm win-back tone (§5).

### Where state lives

New `lib/core/notifications/retention_store.dart` — `RetentionStore` +
`retentionStoreProvider` (`Notifier`), SharedPreferences-backed, key prefix `retention.`,
same pattern as `StudyPlansController`.

| Key | Type | Purpose |
|---|---|---|
| `retention.lastCompletionDayKey` | `String` `yyyy-MM-dd` | last **local** day with a completion |
| `retention.lastOpenDayKey` | `String` | last day app was foregrounded |
| `retention.completionsByWeek` | JSON `{ "2026-W36": ["2026-09-01","2026-09-03"] }` | week-goal ring; capped to 8 weeks |
| `retention.localStreak` | `int` | mirror of server streak, reconciled on each `/dashboard` |
| `retention.serverStreakSeen` | `int` | previous server streak, to detect a drop |
| `retention.graceUsedDayKey` | `String?` | day a grace day was applied |
| `retention.tzName` | `String` | last seen `DateTime.now().timeZoneName` |
| `retention.sentLog` | JSON `{ "2026-09-04": ["studyReminder"] }` | frequency cap; capped 14 days |
| `retention.milestonesReached` | JSON `List<String>` | celebration dedupe (`streak-7`, `study-<id>-done`, `book-Genesis`) |
| `retention.permissionAskedAfterFirstLesson` | `bool` | pre-permission prompt shown once |

Notification *preferences* (toggles, times, quiet hours) live separately in
`lib/features/settings/data/notification_prefs.dart` (§6).

### Computation

- `dayKey(tz.TZDateTime now) => DateFormat('yyyy-MM-dd').format(now)` using
  `tz.TZDateTime.now(tz.local)` — a **wall-clock local date**, never an elapsed-hours diff.
- `weekKey(now) => "${isoYear}-W${isoWeek}"` (ISO-8601 week, Monday start).
- `studiedToday => lastCompletionDayKey == dayKey(now)`.
- `completionsThisWeek => completionsByWeek[weekKey(now)]?.length ?? 0`.
- `markCompleted()`:
  - `d = dayKey(now)`. If `d == lastCompletionDayKey` → no-op (idempotent per day).
  - Guard clock-rewind: if `d < lastCompletionDayKey` lexicographically → **do not** rewrite; only append to the week bucket. Never decrement any counter.
  - Append `d` to `completionsByWeek[weekKey]` (dedup), set `lastCompletionDayKey = d`,
    trim old weeks.
- Reconcile on `/dashboard` load (in `dashboardProvider` `.whenData`):
  `if (data.streak != serverStreakSeen) { localStreak = data.streak; serverStreakSeen = data.streak; }`

### Surviving timezone change & clock skew

- All persisted instants are UTC epoch millis; all "day"/"week" decisions go through
  `tz.TZDateTime.now(tz.local)`.
- On every scheduler run: if `DateTime.now().timeZoneName != retention.tzName` →
  full reschedule (`NotificationService.cancelAllManaged()` then re-add every type) and
  store the new name. Fire times are re-derived against the new zone.
- `flutter_timezone` supplies the IANA name → `tz.setLocalLocation(tz.getLocation(name))`
  in `NotificationService.initialise()` (fixes the current UTC bug).
- Clock moved **backwards**: day keys can repeat; `markCompleted` is idempotent per key and
  never decrements, so a repeated day cannot inflate or destroy a streak.
- Clock moved **forwards** by days: local logic may briefly think the streak broke and
  schedule a win-back for "tomorrow 09:00"; the next `/dashboard` reconcile corrects the
  number, and the win-back copy is harmless if it lands.
- DST: `zonedSchedule` + `absoluteTime` (already used) + a correct `tz.local` handles the
  ±1h shift; no extra work.
- Never trust a single `DateTime.now()` subtraction for streak breakage — only day-key
  comparison, and only for nudging.

---

## 3. Home screen re-entry

A **separate workstream is already adding a "continue study" card** to
`dashboard_screen.dart`. This plan **builds on top of that card** — it does not replace it.
Coordinate the merge; treat the continue-card region as owned by that workstream.

Additions:

1. **Streak / weekly-goal ring** — new `lib/features/dashboard/present/widgets/streak_ring.dart`
   (`StreakRing`, `WeeklyGoalRing`). Placed next to the existing header streak pill
   (`dashboard_screen.dart:137-142`); replace the bare "N dagen" text with the ring +
   number. Daily-streak users see a filled ring (7-segment week around a streak count,
   snowflake when a freeze is banked). Week-goal users see a progress ring
   `count / target` with the target label ("2 / 3 deze week").
2. **"Waar je gebleven was" continue card** — the in-flight card. Ensure its resume target
   for study users is `enrollment.resumeStep`-aware and deep-links to
   `/studie/{studyId}/{currentLessonDay}`. If that card ships reading-only first, add a
   sibling `_ContinueLessonCard` behind the same "most recent activity wins" selector.
3. **Subtle "vandaag nog niet gedaan" chip** — new `homeNudgeProvider`
   (`lib/features/dashboard/present/dashboard_providers.dart`): shows only when
   `!retentionStore.studiedToday` **and** today is a cadence day **and** cadence != `free`.
   Renders as a quiet inline chip under the ring — one line of encouraging copy (drawn from
   the `studyReminder` pool, rendered in-app, no urgency styling), tap → resume target.
   Disappears the instant a completion is recorded (`ref.invalidate(retentionStoreProvider)`).
4. **Milestone toast** — when `retentionStore` detects an un-celebrated milestone on
   dashboard load and the app is foregrounded, show an in-app celebration reusing
   `LessonCompleteCard` styling instead of a notification.

No countdown timers, no red badges, no "you'll lose everything" language anywhere on the
home surface.

---

## 4. Notification system (the core)

### 4.1 Architecture

Three new files under `lib/core/notifications/`:

- **`notification_service.dart`** — generalise `ReminderService` → `NotificationService`.
  Keeps `reminderServiceProvider` as a deprecated alias. Adds:
  - `enum NotifType { studyReminder, streakAtRisk, streakLost, lessonHalfway, weeklyGoal, milestone, dormant, dailyVerse }`
  - stable ID ranges (below)
  - `Future<void> scheduleOneShot(NotifType, tz.TZDateTime when, RenderedVariant, {String deepLink})`
  - `Future<void> cancelType(NotifType)`, `cancelAllManaged()`
  - `tz.TZDateTime clampToWaking(tz.TZDateTime desired, QuietHours)` — if `desired` is
    inside quiet hours, move to `quietEnd` next morning (for morning types) or `quietStart − 30min`
    same evening (for evening types); never schedule inside quiet hours.
  - `onDidReceiveNotificationResponse` + `getNotificationAppLaunchDetails()` wired to
    `GoRouter` (`context.go(payload)`) — **fixes the current tap gap** for all types.
  - `initialise()` also: `flutter_timezone` → `tz.setLocalLocation`; register channels.
- **`retention_store.dart`** — §2.
- **`notification_scheduler.dart`** — `NotificationScheduler.recompute(Ref)`: the single
  brain. Pure function of (cached enrollments + study plans + `RetentionStore` +
  `NotificationPrefs` + last `DashboardData`). Produces a `List<Candidate>`, applies the
  ladder (§4.4), then **cancel-then-schedule per type** (same idempotent pattern as
  `scheduleDaily`). Exposed as `notificationRecomputeProvider` (`FutureProvider`).

`recompute` is invoked:
- from `dashboard_screen.dart` build (like `reminderCopyRefreshProvider` today),
- on `AppLifecycleState.resumed` (new `lib/core/app_lifecycle.dart` observer),
- after `lesson_screen::_finish` success and after `read_screen` `recordRead`,
- on `AppLifecycleState.paused` (to arm the "on close" one-shots: dormant, tomorrow's
  at-risk).

Because `flutter_local_notifications` cannot evaluate conditions at fire time, **every
condition is evaluated at recompute time** and the resulting one-shots are (re)written on
every foreground/completion. A type whose condition is no longer true is cancelled.

### 4.2 Android channels (create new ids; `daily_reading` is deleted after migration)

| Channel id | Name (Dutch) | Importance | Types |
|---|---|---|---|
| `study_reminders` | Studieherinnering | default | `studyReminder` |
| `streak` | Je reeks | default | `streakAtRisk`, `streakLost`, `weeklyGoal` |
| `progress` | Voortgang & lessen | default | `lessonHalfway` |
| `milestones` | Mijlpalen | high (+ sound) | `milestone` |
| `daily_verse` | Vers van de dag | low | `dailyVerse` |
| `winback` | Weer welkom | low | `dormant` |

(Android ignores importance changes to an existing channel — hence new ids + one-time
`deleteNotificationChannel('daily_reading')` in `initialise()`.)

### 4.3 Types, triggers, scheduling

Deep-link column feeds the tap payload (routes already exist: `/studie/:studyId/:day` at
`app_router.dart:318`, `/dashboard` at `:267`).

| Type | ID(s) | When scheduled / fires | Condition to (re)schedule | Deep link |
|---|---|---|---|---|
| **studyReminder** | 1001–1014 (existing block) | User-chosen time, **only on cadence weekdays** (`daily`→every day; `everyOtherDay`→every 2nd day from `startedAt`; `threePerWeek`→Mon/Wed/Fri; `weekly`→one chosen day; `ownDays`→`reminderDays`; `ownPace`/`free`→none). One one-shot per upcoming cadence day, 14 days out, each with its own copy variant. | `NotificationPrefs.studyReminderEnabled` && permission granted && cadence != `free`/`ownPace`. Skip a given day if `studiedToday` for that day is already known (today only). | `/studie/{studyId}/{currentLessonDay}` |
| **streakAtRisk** | 1200 | Evening = `min(quietStart − 30min, 20:30)`, **today only**, and only if by that time `!studiedToday`. | Scheduled at recompute when: cadence day today && `!studiedToday` && `localStreak >= 2` (daily-streak users) *or* week-goal not yet met with ≤ (target−done) cadence days left. **Cancelled immediately** when a completion is recorded today. | `/studie/{studyId}/{currentLessonDay}` |
| **streakLost** | 1201 | One-shot, morning after the break = `clampToWaking(09:00)` next day. | At recompute, if `dayKey(now) − lastCompletionDayKey > 1 + graceDays` && previous `localStreak >= 3` && no `streakLost` already sent this break (`sentLog`). Cancelled if a completion lands first. | `/dashboard` |
| **lessonHalfway** | 1202 | One-shot, `clampToWaking(now + 26h)`. | Cached enrollment has `currentStep ∉ {intro, done}` && `lastActivityAt` between 24h and 7d ago && `!studiedToday`. | `/studie/{studyId}/{currentLessonDay}` |
| **weeklyGoal** | 1203 | Week-goal users only. "Behind" variant: Thu `clampToWaking(18:30)` if `completionsThisWeek < target` and days remain. "Met" variant: fired **immediately** (local, once) the moment `completionsThisWeek == target`. | `NotificationPrefs.weeklyGoalEnabled` && cadence ∈ week-goal set. | `/studie/{studyId}/{currentLessonDay}` (behind) / `/dashboard` (met) |
| **milestone** | 1300+ (transient) | Fired **immediately** after completion when app is backgrounded; shown in-app when foregrounded. | New milestone not in `retention.milestonesReached`: streak ∈ {3,7,14,30,50,100}; `DashboardData.badges` gained an id; `enrollment.completedAt` newly set; a book reached full chapter count in `readChapters`. | `/dashboard` (or `/profile` for a badge) |
| **dormant** | 1210 / 1211 / 1212 / 1213 | Four one-shots at `lastOpenDayKey + {3,7,14,30}` days, `clampToWaking(10:00)`. Re-armed (cancel+reset) on **every** app open. | `NotificationPrefs.dormantEnabled` && permission granted. Only the *next* unreached threshold is armed at a time; the rest follow on the next open that still qualifies. | `/studie/{studyId}/{currentLessonDay}` if an active enrollment exists, else `/dashboard` |
| **dailyVerse** | 1100–1113 | User-chosen time (default 07:30), daily, 14-day one-shot batch, own copy pool. Independent of cadence and of the engagement cap. | `NotificationPrefs.dailyVerseEnabled` && permission granted. | `/dashboard` (verse card) |

### 4.4 Frequency cap, priority & suppression ladder

**Cap:** at most **1** notification from `{studyReminder, streakAtRisk, streakLost,
lessonHalfway, weeklyGoal, dormant}` per calendar day, enforced via `retention.sentLog`.
`dailyVerse` is exempt (max 1). `milestone` is exempt (rare, always earned, always welcome) —
but still ≤ 1 milestone/day.

**Priority (high → low)** when two candidates want the same day:

```
milestone  >  streakLost  >  lessonHalfway  >  streakAtRisk  >  studyReminder  >  weeklyGoal  >  dormant
```

`recompute` builds the candidate list, drops any whose condition is false, sorts by
priority, keeps the first non-`dailyVerse`/`milestone` one for that day, cancels the rest.

**Hard suppression (never fire), checked at recompute *and* re-checked on `resumed`:**

- `studiedToday` → suppress `studyReminder`, `streakAtRisk`, `lessonHalfway`, `weeklyGoal(behind)`, `dormant`.
- Not a cadence day today → suppress `studyReminder`, `streakAtRisk`.
- `cadence == free` → suppress everything except `dailyVerse` and `milestone`.
- App opened today → suppress `dormant` (and reset its schedule).
- A completion recorded after a notification was scheduled but before it fires → the
  `resumed`/completion `recompute` cancels it.
- `sentLog` already has a capped-type entry for today → suppress all other capped types.
- Permission not granted → schedule nothing; show the settings hint instead.

### 4.5 Quiet hours & cadence respect

- `NotificationPrefs.quietStart` / `quietEnd`, default **21:30 → 07:30**, both editable.
- Every computed fire time passes through `clampToWaking`. Nothing is ever scheduled inside
  the window. Evening types clamp *earlier*; morning types clamp *later*.
- Cadence is read from the **server `StudyRhythm`** (`studyEnrollmentsProvider`, cached),
  falling back to local `StudyCadence` when offline. `reminderDays` (weekday ints, 0=Sun)
  drives `ownDays`. `free` disables all nudges by design (`EnrollmentSettings.toJson` already
  sets `remindersEnabled:false` for `free`).
- Multiple active studies: nudge for the **most recently active** enrollment
  (`lastActivityAt`), one study at a time. Never one notification per study.

### 4.6 Permission-request timing

**Do not ask on first launch and do not ask in the onboarding wizard.**

- `setup_flow_screen.dart` step 3: stop calling `service.requestPermission()`. Keep the
  time-of-day + cadence pickers; write the intent into `NotificationPrefs`
  (`studyReminderMinutes`, `pendingPermissionRequest = true`). Reword the step to "we vragen
  dit later, als je je eerste les hebt gedaan".
- After the **first** `lesson_screen::_finish` success (guard
  `retention.permissionAskedAfterFirstLesson`), show a Dutch **pre-permission bottom sheet**
  (in-app, before the OS dialog). On "Herinner me" → `NotificationService.requestPermission()`
  then `notificationRecomputeProvider`. On "Nu niet" → set the guard, offer again only from
  Settings.
- Settings keeps its own enable → `requestPermission()` path (already present).

**Pre-permission sheet copy (Dutch):**

> **Wil je een rustig zetje op je studiedag?**
>
> We sturen je hooguit één herinnering per dag, op het moment dat jij kiest — nooit 's
> avonds laat, nooit als je die dag al bezig bent geweest. Je zet het met één tik weer uit.
>
> [ Herinner me ]  [ Nu niet ]

### 4.7 Local vs. backend

**Everything in Phases 1–2 is local** (`flutter_local_notifications` only). All conditions
are computable on-device from data already cached: `studyEnrollmentsProvider`,
`studyPlansProvider`, `serverStudyLessonsProvider`, `curatedStudiesProvider`,
`RetentionStore`, last `DashboardData`. Copy comes from the existing
`GET /api/v1/notifications/copy` batch (generalised to more `type` values) with a bundled
Dutch fallback pool (§5) and **on-device token interpolation** (we hold study title / lesson
name / streak locally).

| Capability | Local-only? | Notes |
|---|---|---|
| studyReminder, streakAtRisk, lessonHalfway, weeklyGoal, milestone, dailyVerse | ✅ | Pre-scheduled one-shots + immediate fires. No backend. |
| dormant (3/7/14/30) | ✅ | Pre-scheduled on app close; re-armed on open. Works as long as the OS keeps queued one-shots (it does). |
| streakLost **while the app is opened at least once in the window** | ✅ | Pre-scheduled "tomorrow 09:00 unless you complete today". |
| streakLost / dormant **when the app is never opened for weeks** | ❌ needs push | iOS drops nothing for queued local one-shots, so 30-day dormant still works; the only true gap is if the OS evicts the app or the user force-quits on iOS repeatedly. **Recommend deferring push** — Phase 1–2 cover the realistic cases. |
| Cross-device streak correctness | already backend | `GET /dashboard`. |
| Copy CMS / A/B variants | backend, already exists | `ReminderVariant.variantId` already carries an A/B id. |

**Backend work is Phase 3 and optional** (§8).

---

## 5. Copy (Dutch)

Tone: warm, calm, second person, scripture-flavoured where it lands naturally, **never**
"je verliest", "laatste kans", "nog X uur", "je hebt gefaald". Tokens:
`{name} {study} {lesson} {streak} {book} {chapter} {verse} {reference} {done} {target} {n}`
(`{n}` = target − done). Missing token → fall back to a token-free line in the same pool
(the existing `bundledFallback` already follows this rule).

Stored in new `lib/core/notifications/notification_copy.dart` as
`Map<NotifType, List<VariantTemplate>>`; server batch overrides per type when available.

### studyReminder (time-of-day, on a cadence day)

1. **Even tijd voor {study}** — "Les {lesson} ligt klaar. Een paar minuten is genoeg."
2. **Je moment met het Woord** — "Vandaag: {lesson}. Neem de tijd die je hebt."
3. **Verder in {study}** — "Waar je gebleven was, wacht rustig op je. Geen haast."
4. **Eén les, even stil** — "{lesson} vraagt niet veel — alleen jou, een ogenblik."
5. **Klaar wanneer jij dat bent** — "{study} staat voor je open bij {lesson}."
6. **Vandaag samen verder** — "Les {lesson} van {study}. Begin waar het je uitkomt."
7. **Je studieplan zegt: vandaag** — "{lesson} wacht. Vijf minuten telt ook mee."
8. **Stil worden bij het Woord** — "Les {lesson}. Lees zo ver als je komt."

### streakAtRisk (evening, not studied today, streak ≥ 2)

1. **Je bent {streak} dagen bezig** — "Nog even vandaag en de reeks blijft heel. Eén korte les is genoeg."
2. **Nog tijd voor vandaag** — "{streak} dagen achter elkaar — mooi volgehouden. Een paar minuten houdt het vast."
3. **Een kort moment nog?** — "Je {streak}-daagse reeks wacht op de les van vandaag."
4. **Vandaag nog niet langs geweest** — "Geen probleem. Eén les en je {streak} dagen staan weer."
5. **Bijna rond voor vandaag** — "{streak} dagen. Een laatste stille minuut maakt het af."
6. **Voor het slapengaan** — "Nog een les vandaag houdt je reeks van {streak} dagen heel."
7. **Je was goed op weg** — "{streak} dagen op rij. Vandaag hoeft maar kort te zijn."
8. **Een klein zetje** — "Eén les vanavond en je blijft in je ritme van {streak} dagen."

### streakLost (morning after the break, was ≥ 3)

1. **Welkom terug** — "Een dag overslaan gebeurt. Je {study} ligt er nog precies zo bij."
2. **Gewoon weer beginnen** — "Geen streep door alles — pak {lesson} op waar je was."
3. **De draad weer oppakken** — "Je hoeft niets in te halen. Eén les vandaag is een prima start."
4. **Elke morgen nieuw** — "'Zijn barmhartigheden zijn elke morgen nieuw.' Begin rustig opnieuw."
5. **Je plek is bewaard** — "Alles wat je deed staat er nog. Kom er even bij zitten."
6. **Een nieuwe reeks begint met één dag** — "Vandaag kan die dag zijn. {lesson} wacht."
7. **Niets verloren** — "Je voortgang blijft. Alleen de reeks begint opnieuw — dat mag."
8. **Terug in het ritme** — "Klein beginnen werkt het best. Open {study} even."

### lessonHalfway

1. **Je was halverwege {lesson}** — "Nog een paar stappen en de les is af. Verder waar je stopte?"
2. **{lesson} staat nog open** — "Je begon eraan — de rest wacht rustig op je."
3. **Nog even afmaken?** — "Je liet {lesson} halverwege liggen. Het duurt niet lang meer."
4. **Halverwege is een goed startpunt** — "Open {lesson} weer; je hoeft niet opnieuw te beginnen."
5. **Je gedachten bij {lesson}** — "De reflectie die je begon, staat er nog. Maak het af wanneer het uitkomt."
6. **Een paar minuten scheelt het** — "{lesson} in {study} is bijna klaar."
7. **Verder waar je was** — "{lesson} wacht op de laatste stappen."
8. **Nog niet afgerond** — "Geen haast — maar {lesson} ligt klaar om af te maken."

### weeklyGoal — behind

1. **Nog {n} lessen deze week** — "Je doel is {target}. Er is nog tijd genoeg."
2. **Halverwege de week** — "Nog {n} te gaan voor je weekdoel. Eén vandaag helpt al."
3. **Je weekritme** — "{done} van {target} gedaan. Een korte les brengt je dichterbij."
4. **Rustig op schema blijven** — "Nog {n} lessen tot zondag. Geen druk, wel een herinnering."

### weeklyGoal — met

5. **Weekdoel gehaald** — "{target} lessen deze week. Mooi volgehouden."
6. **Deze week zit erop** — "Je doel van {target} is rond. Alles daarboven is meegenomen."
7. **Ritme vastgehouden** — "{done} lessen deze week — precies wat je jezelf voornam."
8. **Goed bezig deze week** — "Je weekdoel staat. Rust nu gerust even."

### milestone

1. **{streak} dagen op rij** — "Een mooie gewoonte aan het worden. Blijf zoals je bezig bent."
2. **Een week volgehouden** — "7 dagen met het Woord. Iets om even bij stil te staan."
3. **14 dagen** — "Twee weken trouw. 'Laten wij niet moede worden in het goeddoen.'"
4. **30 dagen** — "Een maand lang elke dag even stil. Knap gedaan, {name}."
5. **{study} afgerond** — "Je hebt de laatste les gedaan. Neem de tijd om terug te kijken."
6. **{book} uitgelezen** — "{book} helemaal doorgelezen. Op naar het volgende boek."
7. **100 dagen** — "Honderd dagen. Wat klein begon, is nu een vast deel van je dag."
8. **Nieuw zegel verdiend** — "Er staat een nieuwe mijlpaal op je profiel."

### dormant

1. *(3d)* **Een paar dagen niet langs geweest** — "Je {study} ligt klaar bij {lesson}. Kom gerust weer even."
2. *(7d)* **Het is een weekje stil** — "Geen zorgen — je voortgang staat er nog. Eén les om er weer in te komen."
3. *(7d)* **Je plek is bewaard** — "{study} wacht precies waar je was, wanneer het jou uitkomt."
4. *(14d)* **Al een tijdje geleden** — "Even een korte groet. Het Woord staat nog steeds voor je open."
5. *(14d)* **Terugkomen mag altijd** — "Begin klein: één hoofdstuk, één stil moment."
6. *(30d)* **Een maand voorbij** — "Je bent nog steeds welkom. {study} begint waar jij wilt."
7. *(30d)* **Nog steeds hier** — "Geen inhaalrace, geen druk. Alleen een open Bijbel wanneer je wilt."
8. *(30d)* **De deur staat open** — "'Komt herwaarts tot Mij.' Wanneer je zover bent."

### dailyVerse

1. **Het woord voor vandaag** — "{verse} — {reference}"
2. **Even meenemen vandaag** — "{verse}"
3. **Vers van de dag** — "{reference}: {verse}"
4. **Een gedachte om mee te dragen** — "{verse} ({reference})"
5. **Voor onderweg** — "{verse} — {reference}"
6. **Stil bij dit vers** — "{reference}: {verse}"
7. **Vandaag** — "{verse}"
8. **Uit de Schrift** — "{verse} — {reference}"

---

## 6. Settings & control

New `lib/features/settings/data/notification_prefs.dart`:

```
class NotificationPrefs {
  bool masterEnabled;              // false => cancelAllManaged(), everything off
  int  studyReminderMinutes;       // migrated from ReadingSettings.dailyReminderMinutes
  bool studyReminderEnabled;
  bool streakAtRiskEnabled;
  bool lessonHalfwayEnabled;
  bool weeklyGoalEnabled;
  bool milestonesEnabled;
  bool dormantEnabled;
  bool dailyVerseEnabled;
  int  dailyVerseMinutes;          // default 7*60+30
  int  quietStartMinutes;          // default 21*60+30
  int  quietEndMinutes;            // default 7*60+30
  int? snoozedUntilEpochMs;        // "sla vandaag over"
}
```
`notificationPrefsProvider` (`Notifier`), SharedPreferences prefix `notif.`, same
load/persist pattern as `ReadingSettingsController`. One-time migration: on first read, if
`notif.studyReminderMinutes` absent and `app.dailyReminderMinutes` present, copy it and set
`studyReminderEnabled = true`.

**UI** — replace `_ReminderSection` in `settings_screen.dart:221` with `_NotificationsSection`:

| Row | Control | Visibility |
|---|---|---|
| Herinneringen (master) | Switch → on triggers permission flow; off → `NotificationService.cancelAllManaged()` + all sub-toggles false | always (hidden on web, like today) |
| Studieherinnering | Switch + `showTimePicker` (reuse `_ReminderTile`) | master on |
| Reeks bijna kwijt | Switch | master on |
| Onafgemaakte les | Switch | master on |
| Weekdoel | Switch | master on **and** an enrollment has a week-goal rhythm |
| Mijlpalen | Switch | master on |
| Weer welkom (afwezigheid) | Switch | master on |
| Vers van de dag | Switch + `showTimePicker` | master on |
| Stille uren | two `showTimePicker` (start / end) | master on |
| Sla vandaag over | Button — sets `snoozedUntilEpochMs = tomorrow 05:00`, cancels today's capped types | master on |

- **Snooze from a delivered notification:** Android `AndroidNotificationAction` "Later
  vandaag" (+3h, clamped) and "Openen"; iOS `DarwinNotificationCategory` with `LATER` /
  `OPEN` actions. Handled in `onDidReceiveNotificationResponse`.
- **Full opt-out = one tap** on the master switch. No confirmation nag, no "are you sure you
  want to lose your streak".
- Keep `_reminderStatusProvider` semantics (OS-truth, not stored-pref) for the master row so
  it can't claim "on" when the OS revoked permission — extend it to check any managed
  pending id, not just `1001..1014`.

---

## 7. Anti-patterns — do NOT

- **No rapid-fire.** Never > 1 engagement notification/day; never two within a few hours;
  `milestone` still ≤ 1/day.
- **No fake urgency.** No countdowns, no "nog 2 uur", no "vervalt vanavond", no
  all-caps, no ⚠️/🔥 as pressure. A streak that's "at risk" is stated calmly, once.
- **No shaming / loss-framing.** Never "je hebt X gemist", "je liet ons in de steek", "je
  {streak} dagen zijn weg". Win-back copy is warm and forward-looking.
- **No dark patterns.** Opt-out is one tap and obvious. No "weet je het zeker? je verliest…"
  interstitial. No pre-checked bundles. No re-prompting for permission after a "nee" except
  from an explicit Settings tap.
- **No notification for something already done.** `studiedToday` and the post-schedule
  `recompute` on `resumed`/completion are mandatory, not best-effort.
- **No manipulative streak inflation.** Grace days are transparent (shown as a snowflake),
  finite (1 / 7 days), and never sold.
- **No permission prompt on first launch or in the wizard.** Earn it after the first
  completed lesson.
- **No cadence-blind nagging.** A 3×/week user is silent on their off days.
- **No guilt via the home screen.** The "not done today" chip is a quiet invitation, never
  a red alert; it vanishes on completion.
- **No push spam masquerading as pastoral care.** Scripture in copy is used sparingly and
  only where it fits; it is never a lever.

---

## 8. Implementation phases

### Phase 1 — shippable on its own: cadence-aware daily reminder + home re-entry + honest permission timing

Delivers: study reminder that respects the user's cadence and quiet hours; deferred
permission (after first lesson); home streak/weekly-goal ring + "not done today" chip;
working notification tap → deep link; the `tz.local` bug fixed; ≤ 1/day cap. No backend
change.

**Create**
- [ ] `pubspec.yaml` — add `flutter_timezone` (IANA name for `tz.setLocalLocation`).
- [ ] `lib/core/notifications/notification_service.dart` — `NotificationService`
      (`NotifType` enum, ID ranges, `scheduleOneShot`, `cancelType`, `cancelAllManaged`,
      `clampToWaking`, tap handler + `getNotificationAppLaunchDetails`, channel registration,
      `tz.setLocalLocation`). `notificationServiceProvider`; keep `reminderServiceProvider`
      alias.
- [ ] `lib/core/notifications/retention_store.dart` — `RetentionStore`,
      `retentionStoreProvider`, keys per §2, `markCompleted()`, `markOpened()`, `studiedToday`,
      `dayKey`/`weekKey`, `completionsThisWeek`, `recordNotificationSent`, `canSendToday`,
      `reconcileServerStreak(DashboardData)`.
- [ ] `lib/core/notifications/notification_scheduler.dart` — `NotificationScheduler.recompute`
      (Phase 1 handles `studyReminder` only) + `notificationRecomputeProvider`.
- [ ] `lib/core/notifications/notification_copy.dart` — bundled Dutch pools + `renderVariant`.
- [ ] `lib/features/settings/data/notification_prefs.dart` — `NotificationPrefs`,
      `notificationPrefsProvider`, migration from `ReadingSettings.dailyReminderMinutes`.
- [ ] `lib/core/app_lifecycle.dart` — `WidgetsBindingObserver` → `recompute` on `resumed`,
      arm "on close" set on `paused`, `markOpened()` on `resumed`.
- [ ] `lib/features/dashboard/present/widgets/streak_ring.dart` — `StreakRing`,
      `WeeklyGoalRing`.
- [ ] `test/retention_store_test.dart`, `test/notification_scheduler_test.dart`.

**Edit**
- [ ] `lib/core/notifications/reminder_copy.dart` — generalise `ReminderCopySource` to take a
      `type` param (`daily_reading` stays the default); keep cache keys per type.
- [ ] `lib/main.dart` — `_initReminders()` → `_initNotifications()`: init service (sets
      `tz.local`), delete `daily_reading` channel, register new channels, cache-only
      `recompute`.
- [ ] `lib/features/onboarding/present/setup_flow_screen.dart` — remove the
      `requestPermission()` call at step 3; write time + cadence intent to `NotificationPrefs`;
      reword copy.
- [ ] `lib/features/study/present/lesson/lesson_screen.dart` `_finish()` success — call
      `retentionStore.markCompleted(...)`, `ref.read(notificationRecomputeProvider.future)`,
      and (first time only) the pre-permission bottom sheet.
- [ ] `lib/features/bible/present/read_screen.dart` (~`:217`, after `recordRead`) —
      `retentionStore.markCompleted(...)` + `recompute`.
- [ ] `lib/features/dashboard/present/dashboard_providers.dart` — add `homeNudgeProvider`;
      in `dashboardProvider` consumer, call `retentionStore.reconcileServerStreak(data)`.
- [ ] `lib/features/dashboard/present/dashboard_screen.dart` — swap the bare streak pill
      (`:137-142`) for `StreakRing`/`WeeklyGoalRing`; add the quiet "vandaag nog niet gedaan"
      chip below it, linking to the resume target. **Do not touch the continue-study card
      region owned by the other workstream** — add the chip above/below it.
- [ ] `lib/features/settings/present/settings_screen.dart` — expand `_ReminderSection` →
      `_NotificationsSection` with: master switch, study reminder toggle+time, quiet-hours
      pickers, one-tap opt-out. (Remaining per-type rows land in Phase 2.)

### Phase 2 — the full nudge ladder

**Edit**
- [ ] `notification_scheduler.dart` — add derivation + scheduling for `streakAtRisk`,
      `streakLost`, `lessonHalfway`, `weeklyGoal`, `dormant`, `dailyVerse`, `milestone`;
      implement the priority + suppression ladder (§4.4) and `sentLog` cap.
- [ ] `notification_service.dart` — Android/iOS action buttons ("Later vandaag" / "Openen"),
      `daily_verse` + `winback` + `milestones` channels finalised.
- [ ] `notification_copy.dart` — full pools from §5; token personalisation pulling
      `{study}`/`{lesson}` from `serverStudyLessonsProvider` + `curatedStudiesProvider`,
      `{book}` from `readChapters`, `{verse}`/`{reference}` from `DailyVerseStore`.
- [ ] `app_lifecycle.dart` — on `paused`, arm `dormant` (next threshold) and tomorrow's
      `streakAtRisk`/`streakLost`.
- [ ] `retention_store.dart` — `milestonesReached` detection helper
      (`newMilestones(DashboardData, enrollments)`).
- [ ] `lesson_screen.dart` / `dashboard_screen.dart` — foreground milestone → in-app
      celebration (reuse `LessonCompleteCard` styling); backgrounded → immediate
      `milestone` notification.
- [ ] `settings_screen.dart` — remaining per-type toggles, daily-verse toggle+time, dormant
      toggle, "Sla vandaag over".
- [ ] Tests: `test/notification_ladder_test.dart` (priority, "never fire for done", dormant
      re-arm on open, milestone dedupe, tz-change full reschedule).

### Phase 3 — backend + polish (optional, product decision)

- [ ] `C:\Projects\bijbelstudie` — extend `GET /api/v1/notifications/copy` to serve
      `type ∈ {streak_at_risk, lesson_halfway, weekly_goal, milestone, dormant, daily_verse}`
      with server-side token fill and `variantId` A/B ids.
- [ ] App — call `POST /streak` (`bumpStreak`, currently unused) from `_finish()` /
      `recordRead` so the server streak stays authoritative for cross-device; reconcile the
      ring from the response.
- [ ] Consolidate the duplicate cadence models — adopt server `StudyRhythm` everywhere
      (`reminderDays`/`reminderMinutes`/`reminderTimezone` already there); migrate
      `study_plan_store.dart` reads; deprecate `StudyCadence`.
- [ ] Optional true push (`firebase_messaging` + APNs cert + backend cron on
      `study-enrollments.reminderMinutes` / `lastActivityAt`) **only if** analytics show a
      real gap from users who never open the app for weeks. Phases 1–2 cover the opened-app
      cases locally.
- [ ] Analytics wiring (§9).

---

## 9. Metrics

**Return / habit**
- D1 / D7 / D30 return rate; sessions per active user per week; median gap (hours) between
  sessions; % of sessions that land on a cadence day.
- Lesson completions / active user / week; study completion rate; chapters read / week.
- Streak distribution; % of active users with a live streak ≥ 7; week-goal completion rate
  by cadence (`threePerWeek`, `weekly`, `ownDays`).

**Notification health (guardrails)**
- Permission grant rate at the post-first-lesson prompt (target ≫ the current
  onboarding-wizard rate).
- Notifications sent / user / day — **assert ≤ 1 capped + ≤ 1 verse + ≤ 1 milestone**.
- Suppression counter: times a candidate was dropped because `studiedToday` / already sent /
  off-cadence (should be high — it means the cap is working).
- Per-type CTR = taps (via deep-link payload tag) / delivered.
- Per-type opt-out rate; master opt-out rate; **opt-out rate within 7 days of enabling**
  (if it climbs, cut frequency).
- Uninstall rate delta between permission-granted and permission-denied cohorts (must not
  diverge — if it does, we're annoying people).

**Efficacy of each nudge**
- `streakAtRisk`: % of recipients who complete a lesson before midnight that day.
- `streakLost` / `dormant`: reactivation within 3 days of delivery, by threshold
  (3 / 7 / 14 / 30).
- `lessonHalfway`: lesson-resume rate within 48h vs. a holdout that gets no halfway nudge.
- `weeklyGoal(behind)`: goal-met rate for recipients vs. holdout.
- `milestone`: next-day retention of celebrated vs. matched non-celebrated users.

**Instrumentation**: emit an analytics event on schedule / deliver / tap / suppress with
`{type, variantId, cadence, streak_bucket}`. Keep a 10% holdout that receives **no**
engagement notifications (verse + in-app only) to measure true lift and watch for annoyance.
