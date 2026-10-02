# Vriendenkring — plan to make it functional

Status: **the app UI exists, the backend does not.** The Start tab's header
button, "Bij je vrienden" and `/vriendenkring` are built and shipped-safe: the
repository treats every failure (404 included) as "no vriendenkring", so today
every reader sees the invitation card and nothing breaks. A preview build
(`--dart-define=PREVIEW=true`) renders canned posts for design review; that flag
is hard-disabled in release.

This plan is what turns it real, including contact-based friend finding.

Two repos are involved:

- **app** — `C:\Projects\bijbelstudie-app` (this one)
- **backend/website** — `C:\Projects\bijbelstudie` (Next.js, `/api/v1/*`, Prisma)

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
   kring all work, and actually delete rows.

Store review hangs on items 1-3: Apple 5.1.1(i) and 5.1.2 (contacts may not be
required for app function, and may not be shared without consent) and the Play
"Personal and sensitive data" policy, which requires a prominent in-app
disclosure before the contacts prompt.

---

## 2. Data model (backend, Prisma)

```prisma
model Friendship {            // one row per pair, userAId < userBId
  id        String   @id @default(cuid())
  userAId   String
  userBId   String
  createdAt DateTime @default(now())
  @@unique([userAId, userBId])
}

model FriendRequest {
  id          String   @id @default(cuid())
  fromUserId  String
  toUserId    String
  status      String   // pending | accepted | declined | cancelled
  source      String   // contacts | code | link
  createdAt   DateTime @default(now())
  respondedAt DateTime?
  @@unique([fromUserId, toUserId])
}

model ContactDiscovery {      // the reader's OWN hashed identifiers
  id        String   @id @default(cuid())
  userId    String
  kind      String   // phone | email
  hash      String   // HMAC-SHA256(pepper, normalised value)
  createdAt DateTime @default(now())
  @@unique([kind, hash, userId])
  @@index([kind, hash])
}

model FriendPost {
  id        String   @id @default(cuid())
  userId    String
  kind      String   // verse | milestone | note
  reference String?
  body      String
  sourceId  String?  // the note / daily verse / badge it came from
  createdAt DateTime @default(now())
  @@index([userId, createdAt])
}

model FriendPostLike    { postId String; userId String; createdAt DateTime @default(now()); @@id([postId, userId]) }
model FriendPostComment { id String @id @default(cuid()); postId String; userId String; body String; createdAt DateTime @default(now()); @@index([postId, createdAt]) }
model FriendFeedSeen    { userId String @id; seenAt DateTime }
model FriendBlock       { userId String; blockedUserId String; createdAt DateTime @default(now()); @@id([userId, blockedUserId]) }
```

Plus two columns on the user's preferences: `friendsDiscoverable` (bool, may
others find me by contact) and `friendsAutoShare` (json: which categories post
automatically).

## 3. Endpoints

| Method | Path | Does |
| --- | --- | --- |
| GET | `/friends/feed?limit=` | the app's `FriendsFeed`: posts of friends, `newActivityCount` from `FriendFeedSeen`, `hasFriends` |
| POST | `/friends/feed/seen` | clears the badge |
| POST | `/friends/posts` | share a verse / note / milestone by hand |
| POST/DELETE | `/friends/posts/:id/like` | heart |
| POST | `/friends/posts/:id/comments` | reaction |
| GET | `/friends` | the kring, with each friend's streak and current plan day |
| DELETE | `/friends/:userId` | remove a friend (deletes the pair row both ways) |
| GET | `/friends/requests` | incoming and outgoing |
| POST | `/friends/requests` | by `userId`, invite code or link token |
| POST | `/friends/requests/:id/accept` / `/decline` | answer |
| POST | `/friends/discovery/hashes` | upload the reader's own hashed phone/e-mail; sets `friendsDiscoverable` |
| POST | `/friends/discovery/match` | body: `{phoneHashes: [], emailHashes: []}` -> matching user ids, name and avatar only |
| DELETE | `/friends/discovery` | forget my hashes, stop being findable |
| POST | `/friends/:userId/block`, `/friends/posts/:id/report` | moderation |

`/friends/discovery/match` is rate-limited (say 5 calls/hour, 2000 hashes per
call) and returns only users with `friendsDiscoverable = true`.

The feed query is the one to watch: posts of friends, newest first, excluding
blocked users, with like/comment counts and `likedByMe`. Index
`FriendPost(userId, createdAt)` plus the friendship fan-out; for a kring of
tens of people a single `IN (...)` query is fine - no fan-out table needed at
this size.

## 4. Contact matching, concretely

**On the phone**

1. Prominent disclosure screen first (own screen, before any OS prompt):
   what is read, what is sent, what is kept. Dutch copy below.
2. `permission_handler` + `flutter_contacts` to read names, phone numbers and
   e-mail addresses.
3. Normalise: phone numbers to E.164 using the account's country (fall back to
   NL), e-mail lowercased and trimmed.
4. Hash each with HMAC-SHA256 under a **pepper fetched from the server** (so
   the app never ships a secret and the pepper can be rotated), truncated to
   16 bytes.
5. POST the hashes to `/friends/discovery/match`. Keep nothing on disk but the
   matched user ids.
6. Show "Vrienden gevonden": name, avatar, "Uitnodigen". Nothing is sent
   automatically.
7. The reader's own number/e-mail go up separately, through
   `/friends/discovery/hashes`, and only if they chose to be findable.

**On the server**

- Never store an uploaded hash from a match call; match and drop.
- `ContactDiscovery` holds only the reader's own identifiers.
- Deleting the account, or `DELETE /friends/discovery`, deletes those rows.

**Why hashes and not raw contacts:** hashes keep the address book out of the
database, which is both the policy requirement and the thing that makes a
breach boring. Note honestly that phone-number hashes are brute-forceable;
the pepper plus rate limits are what keep that expensive, and the hashes are
not retained. That is the same trade every contact-matching app makes.

**Permission copy (Dutch, for the disclosure screen and the manifests)**

> **Vind je vrienden**
> BijbelStudie kan in je contacten kijken om te zien wie de app al gebruikt.
> We versturen alleen versleutelde codes, nooit namen of nummers, en bewaren
> ze niet. Je bepaalt zelf wie je uitnodigt.

- iOS `Info.plist` → `NSContactsUsageDescription`: "Zo kunnen we zien welke van
  je contacten BijbelStudie al gebruiken. We sturen alleen versleutelde codes."
- Android `AndroidManifest.xml` → `android.permission.READ_CONTACTS`.
- App Store privacy answers: Contacts -> "Used for app functionality", not
  linked to identity, not used for tracking. Play Data safety: contacts
  collected, not shared, processed ephemerally.

**Without contacts** everything still works: an invite link and a code (the
existing `/referral` link can carry it), and a QR code for in-person.

## 5. What posts the feed, and when

Each category is a switch in Instellingen, all **off** by default except
mijlpalen:

- **mijlpaal** — plan day finished, study finished, badge earned, streak
  milestone (7/30/100). Server-side, on the event that already exists.
- **tekst van de dag** — only on an explicit "deel met je vrienden" from the
  verse card's share sheet.
- **notitie** — only from a note's own share action. Notes are private; this
  must never become a default.

A post is a copy, not a reference: editing the note later does not change what
the kring saw, and deleting the note deletes the post.

## 6. Phases

**Phase 1 - backend skeleton (backend repo)**
Prisma models, migration, `/friends/feed`, `/friends`, `/friends/requests`,
likes, comments, `seen`. Invite by code and link. Vitest coverage for the feed
query and the pair invariants. The app needs no change: the repository already
calls these paths and the UI lights up as soon as they answer.

**Phase 2 - invite without contacts (app)**
Vriendenkring gets its own tabs: Feed | Vrienden | Verzoeken. Invite by code,
link and QR. Friend rows show streak and plan day. Remove a friend, block,
report. This is where Vriendenkring stops being read-only.

**Phase 3 - contacts (app + backend)**
The disclosure screen, `flutter_contacts`, normalisation, the pepper endpoint,
`/friends/discovery/*`, the "Vrienden gevonden" list, the findability switch,
and the delete path. Manifest entries and the store privacy answers.
Ship behind a dart-define so it can be turned off if review pushes back.

**Phase 4 - sharing and auto-posts**
The share actions on the verse card and on notes, the Instellingen switches,
and the server-side milestone posts.

**Phase 5 - polish**
Push notification on a new friend request and on a reaction (the notification
feature already exists), pagination of the feed, and the Levensboom of a
friend on their row.

Each phase is independently shippable; 1 and 2 together are already a usable
vriendenkring without touching the address book.

## 7. Tests

- backend: feed excludes blocked users and non-friends; a request cannot be
  accepted twice; the pair row is unique in both directions; match returns only
  discoverable users; rate limit holds.
- app: `friends_repository` turns a 404 into `FriendsFeed.empty` (the whole
  shipped-safe guarantee); hash normalisation of Dutch numbers
  (`06 12345678`, `+31 6 12345678`, `0031612345678` all give one hash);
  the disclosure screen cannot be skipped into the OS prompt; revoking
  contacts access clears what was stored.

## 8. Open questions for the owner

1. Is a vriendschap visible to the kring ("Marieke en Jonathan zijn vrienden")
   or strictly between the two? Plan assumes strictly between the two.
2. May a friend see the reader's notes list, or only shared notes? Plan assumes
   only shared.
3. Minimum age / youth accounts: contacts matching for minors is a separate
   policy question, and Play treats it strictly.
4. Does the website get Vriendenkring too, or is it app-only at first? The
   endpoints are shared either way.
