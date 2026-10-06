# Vriendenkring — plan to make it functional

Status, 2026-10-02: **phases 1 and 2 are built.** The backend exists
(`app/api/v1/friends/**`, five Mongoose collections, `lib/friends/`), the web
platform has `/vriendenkring` plus a "Bij je vrienden" block on its dashboard,
and the app has the Start tab block plus `/vriendenkring` with Feed | Vrienden
| Verzoeken. Inviting works by link and by code on both clients.

Still to do: **phase 3** (contacts, app-only), **phase 4** (share actions and
server-side milestone posts) and **phase 5** (push, paging, a friend's
ProgressTree). `FRIENDS_CONTACT_PEPPER` is not set anywhere yet, so the discovery
routes answer 503 - which is the intended "off" state until phase 3.

Every surface still degrades to the invitation card when the server says
nothing, which is what let the UI ship before the API existed.

This plan is what turns it real, on **both clients**, including contact-based
friend finding.

Two repos are involved:

- **app** — `C:\Projects\bijbelstudie-app` (this one). Flutter, Riverpod 3,
  go_router, Dio. Auth: `Authorization: Bearer <jwt>` against `/api/v1/*`.
- **web platform** — `C:\Projects\bijbelstudie`. Next.js 15 App Router +
  TypeScript + **MongoDB (Mongoose)** + NextAuth + Tailwind, on Vercel. Dutch
  only, slate + teal, brand teal `#0D9488` hardcoded.

No new stack anywhere: Mongoose schemas in `models/*.js`, business logic in
`lib/friends/`, route handlers in `app/api/v1/friends/**`, React in
`components/friends/`, vitest in `tests/`. Nothing is added to the toolchain.

> Two rules from that repo's CLAUDE.md that bind this work: Claude never
> commits or pushes to `main` there (work on `levensboom` or a branch off it),
> and **preview deployments share the production `scriptura` database** — so
> "just trying the friend flow on a preview" is production. Dev work points at
> the `Bijbelstudie` database via `.env.local`.

---

## 1. Principles

1. **Opt-in, twice.** Reading contacts is one consent; being findable by others
   is a second one. Neither implies the other.
2. **No address book leaves the phone in the clear.** Only salted hashes of
   normalised phone numbers and e-mail addresses go up, and they are not kept
   after matching.
3. **Nothing is published by accident.** A note, a verse or a milestone reaches
   the kring only when the reader shares it, or switches that category on.
4. **Reciprocal.** A vriendschap needs both sides; there are no followers.
5. **Leaveable.** Revoking contacts access, removing a friend and deleting the
   kring all work, and actually delete documents.
6. **One feed, two clients.** Web and app read the same documents through the
   same routes and the same wire contract. Neither gets a feature the other
   silently lacks (contacts aside — see §6).

Items 1-3 are what store review hangs on: Apple 5.1.1(i) and 5.1.2 (contacts
may not be required for app function, nor shared without consent) and the Play
"Personal and sensitive data" policy, which requires a prominent in-app
disclosure before the OS contacts prompt.

**Vriendenkring is not Groepen.** `models/StudyGroup.js` and
`models/GroupMessage.js` already exist and are hidden for the MVP (`/groups`
redirects to the dashboard in both clients). A kring is a reciprocal 1:1 graph,
a groep is a room with messages. Keep them apart; do not reuse those models.

---

## 2. Data model — Mongoose (`models/*.js`)

Five schemas, written like the existing ones (`.js`, singular PascalCase file,
explicit indexes, `timestamps` where the existing models use it).

```js
// models/Friendship.js - one document per pair, userAId < userBId as strings
{ userAId: ObjectId, userBId: ObjectId, createdAt: Date, source: String }
//   unique index { userAId: 1, userBId: 1 }, plus { userAId: 1 } and { userBId: 1 }

// models/FriendRequest.js
{ fromUserId: ObjectId, toUserId: ObjectId,
  status: String,            // pending | accepted | declined | cancelled
  source: String,            // contacts | code | link | qr
  createdAt: Date, respondedAt: Date }
//   unique index { fromUserId: 1, toUserId: 1 }, plus { toUserId: 1, status: 1 }

// models/FriendProfile.js - one document per user; everything per-account
{ userId: ObjectId,          // unique
  discoverable: Boolean,     // may others find me by contact hash
  phoneHashes: [String],     // MY OWN normalised identifiers, hashed
  emailHashes: [String],
  feedSeenAt: Date,          // drives newActivityCount
  autoShare: { milestones: Boolean, verses: Boolean, notes: Boolean },
  blocked: [ObjectId] }
//   unique { userId: 1 }; multikey { phoneHashes: 1 } and { emailHashes: 1 }

// models/FriendPost.js
{ userId: ObjectId,
  kind: String,              // verse | milestone | note
  reference: String, body: String,
  sourceId: String,          // the note / daytext / badge it came from
  likes: [{ userId: ObjectId, at: Date }],
  commentCount: Number,
  createdAt: Date }
//   { userId: 1, createdAt: -1 }

// models/FriendPostComment.js
{ postId: ObjectId, userId: ObjectId, body: String, createdAt: Date }
//   { postId: 1, createdAt: 1 }
```

Why a separate `FriendProfile` rather than fields on `User`: that repo's data
rules forbid `save()` on a hydrated `User` and want targeted operators only, and
`User` is already the document the 2026-09-08 incident was about. Keeping the
whole feature in its own collection means nothing here can touch progress
fields.

**Writes follow the `lib/bibleYear/service.ts` precedent:** `lib/friends/service.ts`
is the only writer, and only through targeted operators — `$addToSet` for a
like or a hash, `$set` on a specific path for `feedSeenAt`, `$inc` for
`commentCount`, `$pull` to unlike. No document replacement anywhere.

Add `friendprofiles`, `friendships`, `friendrequests`, `friendposts` and
`friendpostcomments` to `lib/accountArchive.ts`, so account deletion keeps
archiving everything related (that guard exists because of the incident; a new
collection that it does not know about is a hole in it).

## 3. What this reuses — no new plumbing anywhere

Everything below already exists and is the thing to call, not to re-derive.

**Web platform (`C:\Projectsijbelstudie`)**

| Use | Existing |
| --- | --- |
| caller resolution, both clients | `requireUser` / `resolveUser` / `AuthUser` in `lib/apiAuth.ts` — NextAuth cookie **or** `Authorization: Bearer` via `lib/mobileJwt.ts`. One handler serves web and app. |
| response plumbing | `corsPreflight`, `jsonV1`, `errorV1`, `handleV1Error` in `lib/apiV1.ts` (uniform error bodies, CORS, the 500 error id) |
| database | `connectMongoDB` from `lib/mongodb.ts`; `models/*.js` Mongoose schemas |
| throttling | `checkRateLimit` in `lib/mobileRateLimit.ts` (per-IP fixed window) for `discovery/match`; `lib/rateLimit.ts` buckets for the rest. In-process, so a courtesy limit — stated at the call site, as those modules ask. |
| invite link, code, share text | `referralOverview` in `lib/referral.ts` and `/api/v1/referral`; the app's card already renders it. A friend request carries the same code, so one link does both jobs. |
| streak / XP on a friend row | `lib/streak.ts`, `lib/gamification.ts` |
| plan day on a friend row | `lib/bibleYear/service.ts` (the only writer of its enrollment) |
| push on a request or reaction | `lib/notificationSchedule.ts`, `lib/notificationCopy.ts` |
| account deletion safety | `archiveAccount`'s `related` map in `lib/accountArchive.ts` |
| user lookup by id/email | `lib/userLookup.ts` |
| route conventions | `app/api/v1/referral/route.ts` is the shortest example: `OPTIONS = corsPreflight`, `requireUser`, `jsonV1(..., { headers: { 'Cache-Control': 'private, no-store' } })`, `handleV1Error` in the catch |
| tests | vitest in `tests/`, `npm test` |

**App (`C:\Projectsijbelstudie-app`)**

| Use | Existing |
| --- | --- |
| HTTP | `core/api/api_client.dart` (Dio + bearer refresh). Screens never touch Dio. |
| last-good payload on a cold start | `core/data/payload_cache.dart` — the same trick `DashboardNotifier` uses, so the feed opens on what it had |
| cards, buttons, headers, empty states | `core/ui/app_widgets.dart` (`AppCard`, `SiteButton`, `SectionHeader`, `IconChip`, `AppEmptyState`), `core/ui/skeleton.dart` |
| colours, radii, type | `core/theme/app_theme.dart` — including `AppTheme.flame` for the streak and `tealTint` for avatars |
| routing | `core/router/app_router.dart`; `/vriendenkring` is already in the shell |
| report a post | `showFeedbackSheet` in `features/feedback/present/feedback_sheet.dart` |
| invite share | `referralOverviewProvider` + `share_plus`, as `features/referral/present/invite_section.dart` does |
| the contacts disclosure screen | `core/notifications/permission_moment.dart` is the existing "explain, then ask" pattern — the contacts moment is a second instance of it, not a new idea |
| push | `core/notifications/` |

**The only new dependency in either repo** is `flutter_contacts` in phase 3. It
asks for the contacts permission itself, so no `permission_handler` is needed.
Phases 1, 2 and 4 add no package anywhere.

## 4. Shared wire contract and services

Mirror the Bijbel-in-een-jaar arrangement exactly, because it is the pattern
that already keeps web and app in step:

| Where | What |
| --- | --- |
| `lib/friends/types.ts` | the wire contract: `FriendsFeed`, `FriendPost`, `FriendSummary`, `FriendRequestView`. No database imports, so client components can `import type` it. **Changes here, in `components/friends/`, in `lib/friends/client.ts` and in the app's `features/friends/` go in one pass.** |
| `lib/friends/service.ts` | the only writer; feed assembly, pair invariants, request state machine |
| `lib/friends/discovery.ts` | pure: normalisation and hashing, unit-testable without a database |
| `lib/friends/client.ts` | the browser's fetch wrapper, as `lib/bibleYear/client.ts` is |
| `app/api/v1/friends/**` | route handlers, thin: auth, parse, call the service, `jsonV1` |

The app's `features/friends/data/friend_models.dart` already matches this shape
(`posts`, `newActivityCount`, `hasFriends`, and a post with
`kind/reference/body/likeCount/likedByMe/commentCount`), so phase 1 needs no
Dart change at all.

## 5. Endpoints

| Method | Path | Does |
| --- | --- | --- |
| GET | `/friends/feed?limit=&before=` | `FriendsFeed`: friends' posts newest first, `newActivityCount` from `feedSeenAt`, `hasFriends` |
| POST | `/friends/feed/seen` | clears the badge (`$set feedSeenAt`) |
| POST | `/friends/posts` | share a verse / note / milestone by hand |
| POST / DELETE | `/friends/posts/:id/like` | heart (`$addToSet` / `$pull`) |
| GET / POST | `/friends/posts/:id/comments` | reactions |
| GET | `/friends` | the kring, each friend with streak and current plan day |
| DELETE | `/friends/:userId` | remove a friend (deletes the one pair document) |
| GET / POST | `/friends/requests` | incoming and outgoing; invite by userId, code or link token |
| POST | `/friends/requests/:id/accept` \| `/decline` | answer |
| GET | `/friends/discovery/pepper` | the current hashing pepper (signed in only) |
| POST | `/friends/discovery/hashes` | upload my own hashed phone/e-mail; sets `discoverable` |
| POST | `/friends/discovery/match` | `{phoneHashes, emailHashes}` -> matching users (name + avatar only) |
| DELETE | `/friends/discovery` | forget my hashes, stop being findable |
| POST | `/friends/:userId/block`, `/friends/posts/:id/report` | moderation |

`/friends/discovery/match` is rate-limited (≈5 calls/hour, ≤2000 hashes per
call) and returns only users with `discoverable: true`.

Feed query, in Mongo terms: read the pair documents for the signed-in user,
collect the other side's ids, drop anyone in `blocked` (either direction), then
`FriendPost.find({ userId: { $in: ids } }).sort({ createdAt: -1 }).limit(n)`.
For a kring of tens of people that is one indexed query; no fan-out collection
is warranted at this size, and `before` gives cursor pagination later.

## 6. Contact matching — app only, by nature

A browser cannot read an address book, so **contacts are an app feature**; the
web platform gets the same kring through invite link, code and QR. This is the
one place the two clients differ, and the plan says so out loud rather than
leaving the website looking broken.

**On the phone**

1. A prominent disclosure screen first, before any OS prompt: what is read,
   what is sent, what is kept. Copy below.
2. `permission_handler` + `flutter_contacts` read names, phone numbers and
   e-mail addresses.
3. Normalise: phone numbers to E.164 using the account's country (fall back to
   NL), e-mail lowercased and trimmed.
4. Hash each with HMAC-SHA256 under a **pepper fetched from the server**
   (`/friends/discovery/pepper`), truncated to 16 bytes — so the app ships no
   secret and the pepper can be rotated.
5. POST the hashes to `/friends/discovery/match`. Keep nothing on disk but the
   matched user ids.
6. Show "Vrienden gevonden": name, avatar, "Uitnodigen". Nothing is sent
   automatically.
7. The reader's own number and e-mail go up separately, through
   `/friends/discovery/hashes`, and only if they chose to be findable.

**On the server**

- Never store an uploaded hash from a match call: match and drop.
- `FriendProfile.phoneHashes` / `emailHashes` hold only the reader's own
  identifiers.
- `DELETE /friends/discovery` and account deletion remove them.

**Why hashes and not raw contacts:** it keeps the address book out of
`scriptura` entirely, which is both the policy requirement and the thing that
makes a breach boring. Stated honestly: phone-number hashes are brute-forceable
by their nature; the server-held pepper, the rate limit and not retaining
uploaded hashes are what keep that expensive. That is the same trade every
contact-matching app makes.

**Permission copy (Dutch)**

> **Vind je vrienden**
> BijbelStudie kan in je contacten kijken om te zien wie de app al gebruikt.
> We versturen alleen versleutelde codes, nooit namen of nummers, en bewaren
> ze niet. Je bepaalt zelf wie je uitnodigt.

- iOS `Info.plist` -> `NSContactsUsageDescription`: "Zo kunnen we zien welke
  van je contacten BijbelStudie al gebruiken. We sturen alleen versleutelde
  codes."
- Android `AndroidManifest.xml` -> `android.permission.READ_CONTACTS`.
- App Store privacy answers: Contacts -> "Used for app functionality", not
  linked to identity, not used for tracking. Play Data safety: contacts
  collected, not shared, processed ephemerally.

## 7. The web platform's own surfaces

- `app/vriendenkring/page.tsx` — the feed, the kring and the requests, same
  three sections as the app, Dutch slug like `groepen` / `notities`.
- `components/friends/` — `FriendPostCard`, `FriendFeed`, `FriendList`,
  `FriendRequests`, `InviteFriendsCard`. Slate + teal, teal `#0D9488` inline,
  no decorative icons (icons only to identify a control), matching the app's
  card: avatar, name, "Mijlpaal · 2 u", body, then heart / reaction / more.
- `components/dashboard/` — a "Bij je vrienden" block on `/dashboard` with the
  two newest posts and "Alles bekijken", mirroring the Start tab.
- Share actions on the daily verse and on a note, the same two the app gets.
- The invite page the link lands on: the existing `/uitnodiging` referral page
  grows a "word vrienden" path, so one link serves both.

## 8. What posts to the feed, and when

Each category is a switch in Instellingen on both clients, all **off** by
default except mijlpalen:

- **mijlpaal** — plan day finished, study finished, badge earned, streak
  milestone (7/30/100). Written server-side, on events that already exist.
- **tekst van de dag** — only on an explicit "deel met je vrienden".
- **notitie** — only from a note's own share action. Notes are private; this
  must never become a default.

A post is a copy, not a reference: editing the note later does not change what
the kring saw, and deleting the note deletes the post.

## 9. Phases

**Phase 1 — backend + wire contract** (done; web repo, branch `vriendenkring` off `levensboom`)
The five schemas, `lib/friends/{types,service,discovery,client}.ts`,
`/friends/feed`, `/friends`, `/friends/requests`, likes, comments, `seen`,
invite by code (reusing `referralOverview`'s code), and the five new entries in
`archiveAccount`'s `related` map. Handlers are `requireUser` + service call +
`jsonV1`, with `handleV1Error` in the catch. Vitest for the feed query, the
pair invariants and the request state machine. **The app needs no change: it
already calls these paths and lights up the moment they answer.**

**Phase 2 — kring without contacts** (done, both clients)
App: `/vriendenkring` gains Feed | Vrienden | Verzoeken, invite by code, link
and QR, friend rows with streak and plan day, remove/block/report.
Web: `app/vriendenkring` plus the dashboard block. After this it is a usable
vriendenkring on both platforms, with the address book untouched.

**Phase 3 — contacts** (app + backend)
Disclosure screen, `flutter_contacts`, normalisation, pepper endpoint,
`/friends/discovery/*`, "Vrienden gevonden", the findability switch (also on
web, since being findable is an account setting), the delete path, manifest
entries and the store privacy answers. Behind a dart-define, so it can be
switched off if review pushes back.

**Phase 4 — sharing and auto-posts** (both)
Share actions on the verse card and on notes, the Instellingen switches, and
the server-side milestone posts.

**Phase 5 — polish**
Push on a new request and on a reaction (the notifications feature exists),
feed pagination via `before`, and a friend's ProgressTree on their row.

## 10. Tests

- **web** (`tests/`, `npm test`): feed excludes non-friends and blocked users;
  a request cannot be accepted twice; the pair document is unique whichever
  side asks; `discovery/match` returns only discoverable users and respects the
  rate limit; `lib/friends/discovery.ts` normalises `06 12345678`,
  `+31 6 12345678` and `0031612345678` to one hash; every write uses a targeted
  operator (no document replacement).
- **app** (`test/`, local-only): `friends_repository` turns a 404 into
  `FriendsFeed.empty` — that is the whole shipped-safe guarantee; the
  disclosure screen cannot be skipped into the OS prompt; revoking contacts
  access clears what was stored. `test/home_start_redesign_test.dart` already
  covers the Start tab's two main cards and the "Bij je vrienden" states.

## 11. Open questions for the owner

1. Is a vriendschap visible to the kring ("Marieke en Jonathan zijn vrienden")
   or strictly between the two? Plan assumes strictly between the two.
2. May a friend see the reader's notes list, or only shared notes? Plan assumes
   only shared.
3. Minimum age: contacts matching for minors is a separate policy question, and
   Play treats it strictly.
4. Web and app together in one release, or web first (it has no store review
   to wait for)?
