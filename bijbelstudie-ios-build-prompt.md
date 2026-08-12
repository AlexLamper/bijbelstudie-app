# BijbelStudie iOS — complete build prompt

Copy this whole file into the new, empty project directory and hand it to the
coding agent. It assumes two repos on the same machine:

| Role | Path |
|---|---|
| **Reference app** (working, shipping, proven CI) | `C:\Projects\bijbelquiz-app` |
| **Backend** (existing Next.js site, needs new endpoints) | `C:\Projects\bijbelstudie` |
| **New mobile app** (this repo) | current directory |

---

# 0. What you are building

A native **Flutter** iOS app for BijbelStudie, structurally cloned from the
Bijbelquiz app at `C:\Projects\bijbelquiz-app`, using:

- **the same payment method** — RevenueCat (`purchases_flutter`) + StoreKit
  auto-renewable subscriptions, with the RevenueCat webhook writing `isPremium`
  back to MongoDB
- **the same signing/release method** — GitHub Actions on `macos-latest`,
  manual codesigning from a base64 `.p12` + `.mobileprovision`, `xcodebuild
  -exportArchive`, upload via `xcrun altool`

Do **not** propose Expo, Capacitor, or a WebView wrapper. That decision is made.
Do **not** redesign the architecture. Clone the proven one, then adapt.

## Stack (fixed)

Flutter 3.32 / Dart 3.8 (`sdk: ^3.8.0`) · Riverpod · `go_router` · Dio ·
`flutter_secure_storage` · `google_sign_in` · `sign_in_with_apple` ·
`purchases_flutter` · `cached_network_image` · `flutter_svg` · `url_launcher` ·
`sqflite` (new — offline cache) · `flutter_lints ^5`.

---

# 1. HARD GATE — licensing. Read before writing any code.

An audit of the BijbelStudie site (`IOS_APP_BRIEF.md` in the backend repo) found
that **three content sources may not ship in an iOS app**. Shipping them is a
contract breach and a takedown risk, not a technical bug.

| Source | Status | Rule |
|---|---|---|
| **NBG-vertaling 1951** (`nbg51`) | 🔴 BLOCKED | Licence is scoped to `www.bijbel-studie.com` only. iOS is not covered. |
| **KingComments** (`kingcomments_nl`) | 🔴 BLOCKED | Requires prior written permission from Stichting Titus / Uitgeverij Daniël. They ship their own App Store app. |
| **NET Bible** | 🔴 BLOCKED | Electronic whole-text distribution needs written permission and "cannot be bundled with anything sold". The app has a paid tier. |
| **HSV, BasisBijbel** | 🔴 BLOCKED | Copyrighted. Already out of the manifest. Keep out. |
| Statenvertaling, KJV, ASV, WEB, Geneva, Coverdale, Luther, Elberfelder, HS1917, Canisius | ✅ public domain | Ship. |
| Dachsel, Matthew Henry, Meyer | ✅ public domain | Ship. |
| STEPBible originals | ✅ CC BY 4.0 | Ship **with attribution visible in the app**. |

**Implementation requirement — this is not optional:**

Create a single server-side allowlist and gate every mobile content route on it.
A per-request check, not a UI filter. The mobile client must be structurally
incapable of receiving blocked content even if someone crafts the request by
hand.

```ts
// lib/mobileLicensing.ts  — single source of truth
export const MOBILE_ALLOWED_BIBLES = new Set([
  'statenvertaling', 'kjv', 'asv', 'web', 'geneva',
  'coverdale', 'luther', 'elberfelder', 'hs1917', 'canisius',
]);

export const MOBILE_ALLOWED_COMMENTARIES = new Set([
  'matthew_henry_nl', 'dachsel', 'meyer',
]);

export const MOBILE_ALLOWED_ORIGINALS = new Set(['stepbible']);

export function assertMobileAllowed(kind: 'bible'|'commentary'|'original', id: string) {
  const set = kind === 'bible' ? MOBILE_ALLOWED_BIBLES
            : kind === 'commentary' ? MOBILE_ALLOWED_COMMENTARIES
            : MOBILE_ALLOWED_ORIGINALS;
  if (!set.has(id)) {
    const err = new Error('CONTENT_NOT_LICENSED_FOR_MOBILE');
    (err as any).status = 451;   // Unavailable For Legal Reasons
    throw err;
  }
}
```

Write a backend test that asserts `nbg51`, `kingcomments_nl` and `net` each
return **451** from every `/api/v1/*` content route. If that test does not exist
and pass, the mobile app is not ready to build.

If I later obtain written permission for any of these, the only change is one
line in that allowlist.

---

# 2. Apple submission blockers (must all be closed before first upload)

| # | Guideline | Problem today | Required fix |
|---|---|---|---|
| 1 | — | Every protected route uses `getServerSession()` (NextAuth cookies). Native apps cannot use cookie sessions. | Bearer-JWT auth on `/api/v1/*` (Phase A1) |
| 2 | **5.1.1(v)** | No self-service account deletion. Only `DELETE /api/admin/users/[id]` exists. **Automatic rejection.** | In-app "Verwijder account" flow + `DELETE /api/v1/account` (Phase A2) |
| 3 | **4.8** | Google login offered with no private-login alternative. | Sign in with Apple, presented equally (Phase B) |
| 4 | **3.1.1** | Stripe cannot sell the Pro tier inside the binary, EU storefront included. | RevenueCat/StoreKit subscriptions. No link to Stripe checkout anywhere in the app. Existing web subscribers keep Pro via the multiplatform exception — read entitlement from the backend, do not sell to them. |
| 5 | **4.2** | A thin content viewer reads as a repackaged website. | Ship real native features (Phase F list) |

---

# 3. Repo layout to create

```
<this repo>/
├─ .github/
│  ├─ workflows/ios-release.yml            ← copied verbatim from reference
│  └─ instructions/flutter-architecture.instructions.md
├─ bijbelstudie_mobile/                    ← the Flutter app
│  ├─ lib/
│  │  ├─ core/{api,config,router,theme,ui,preview,db}/
│  │  ├─ features/
│  │  │  ├─ auth/{data,domain,present}/
│  │  │  ├─ onboarding/{data,present}/
│  │  │  ├─ premium/{data,present}/
│  │  │  ├─ profile/{data,present}/
│  │  │  ├─ bible/{data,domain,present}/
│  │  │  ├─ commentary/{data,domain,present}/
│  │  │  ├─ notes/{data,domain,present}/
│  │  │  └─ search/{data,domain,present}/
│  │  └─ main.dart
│  ├─ assets/{fonts,images}/
│  ├─ android/  ios/  test/
│  ├─ analysis_options.yaml
│  └─ pubspec.yaml
├─ docs/ios-release-setup.md
└─ README.md
```

Feature-first clean architecture: `data/` = repositories + models + local
storage, `domain/` = entities, `present/` = screens + Riverpod providers. This
mirrors the reference exactly. Do not invent a different split.

---

# PHASE A — Backend (`C:\Projects\bijbelstudie`)

Additive only. **The website must keep working unchanged.** Do not touch
existing cookie-session routes; add a parallel `/api/v1/*` surface.

## A1 — Bearer auth

Create `lib/apiAuth.ts` that resolves a caller from **either** a NextAuth cookie
session **or** an `Authorization: Bearer <jwt>` header, so route handlers can be
shared:

```ts
export async function resolveUser(req: Request): Promise<AuthUser | null>
```

Endpoints (all under `/api/v1/`):

| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/auth/register` | `{name,email,password}` | `{accessToken, refreshToken, user}` |
| POST | `/auth/login` | `{email,password}` | `{accessToken, refreshToken, user}` |
| POST | `/auth/google` | `{idToken}` | same |
| POST | `/auth/apple` | `{identityToken, authorizationCode, givenName?, familyName?, email?}` | same |
| POST | `/auth/refresh` | `{refreshToken}` | new pair |
| POST | `/auth/logout` | `{refreshToken}` | `204` |

Rules:
- Access token: JWT, 15 min, `{sub, email, isPro, iat, exp}`.
- Refresh token: opaque random 256-bit, hashed (SHA-256) at rest in a
  `RefreshToken` collection with `{userIdHash, tokenHash, family, expiresAt, revokedAt}`.
- **Rotation with replay detection**: each refresh issues a new token and
  revokes the old one. If a revoked token is presented, revoke the entire
  `family` and force re-login. This is the difference between a refresh-token
  system and a long-lived password.
- Apple: verify `identityToken` with `apple-signin-auth`, audience =
  `com.bijbelstudie.app`. Link by `appleId`, fall back to email match, else
  create. Handle Apple's private-relay addresses and the fact that name/email
  arrive **only on first authorization** — persist them then or lose them.
- Rate-limit `/auth/login` and `/auth/register`.
- Never log tokens.

## A2 — Account deletion (blocker #2)

```
DELETE /api/v1/account      Authorization: Bearer <access>
Body: { "confirm": "VERWIJDER" }
```

Must, in one transaction: delete the user document, their notes/highlights/
bookmarks/history, revoke every refresh-token family, and either delete or
irreversibly anonymise Stripe/RevenueCat linkage. Return `204`. Apple checks
that this is reachable **without leaving the app** — no "email us" link.

## A3 — Content API (allowlist-gated)

| Method | Path | Notes |
|---|---|---|
| GET | `/v1/bibles` | manifest, allowlisted only |
| GET | `/v1/bibles/:versionId/books` | |
| GET | `/v1/bibles/:versionId/:book/:chapter` | one chapter, the unit of transfer |
| GET | `/v1/commentaries` | allowlisted only |
| GET | `/v1/commentaries/:id/:book/:chapter` | |
| GET | `/v1/original/:book/:chapter` | STEPBible |
| GET | `/v1/search?q=&version=&book=` | server-side |

Every one calls `assertMobileAllowed(...)` first. Every response carries
`ETag` + `Cache-Control` and honours `If-None-Match` → `304`. The chapter is the
transfer unit; **never** serve a whole version in one response.

Response envelope, used by all content routes:

```json
{ "id":"statenvertaling", "book":"genesis", "chapter":1,
  "verses":[{"n":1,"t":"In den beginne schiep God..."}],
  "attribution":"Statenvertaling (publiek domein)",
  "updatedAt":"2026-08-09T00:00:00Z" }
```

## A4 — User data + sync

`GET/POST/PATCH/DELETE /v1/notes`, `/v1/highlights`, `/v1/bookmarks`,
`/v1/reading-history`. Each record carries `id` (client-generated UUID),
`updatedAt`, `deletedAt`.

`POST /v1/sync` takes `{since, changes[]}` and returns `{serverChanges[], serverTime}`.
Conflict rule: **last-write-wins by `updatedAt`**, ties broken by server. Deletes
are tombstones, never hard deletes, so an offline device cannot resurrect them.
State this rule in a comment where it is implemented.

## A5 — Entitlements + RevenueCat webhook

- `GET /v1/me` → `{id,name,email,isPro,proSource:'stripe'|'apple'|'google'|null, proExpiresAt}`
- `POST /api/mobile/revenuecat-webhook` — copy the pattern from
  `C:\Projects\bijbelquiz-app\server\nextjs-reference\app\api\mobile\revenuecat-webhook\route.ts`.
  HMAC-verify `x-revenuecat-signature` against the raw body with
  `REVENUECAT_WEBHOOK_SECRET`, `bodyParser: false`. Store processed event ids to
  make it idempotent — RevenueCat retries.
- `POST /v1/sync-premium` — force reconciliation. **This one is essential**:
  RevenueCat does not re-send a webhook for an already-owned purchase or a
  restore, so without it premium can stay locked on the server forever. The
  reference app learned this the hard way; see
  `features/profile/data/profile_repository.dart:syncPremium`.
- A user who is Pro via Stripe on the web stays Pro in the app. `isPro` is the
  OR of all sources. Do not offer them a purchase.

---

# PHASE B — Mobile app skeleton

## B1 — Copy from the reference

Copy `C:\Projects\bijbelquiz-app\bijbelquiz_mobile\` into `bijbelstudie_mobile/`,
**excluding**: `.git/`, `build/`, `.dart_tool/`, `ios/Pods/`, `ios/.symlinks/`,
`android/.gradle/`, `android/key.properties`, `android/app/*.jks`,
`android/app/upload_certificate.pem`, `pubspec.lock`, `flutter_01.png`,
`flutter_02.png`, and the stray root-level `main.dart` (a duplicate of
`lib/main.dart` — do not carry it over).

**Never copy a credential.** No `.p12`, `.mobileprovision`, `.p8`, keystore, or
`key.properties`. If you find one, stop and tell me.

Keep `assets/fonts/` complete (Inter, Newsreader, Geist, Geist Mono) — the theme
depends on all four families.

## B2 — Rename

Longest strings first, so you do not create partial matches:

| Find | Replace |
|---|---|
| `bijbelquiz_mobile` | `bijbelstudie_mobile` |
| `com.example.bijbelquizMobile` | `com.example.bijbelstudieMobile` |
| `com.bijbelquiz.app` | `com.bijbelstudie.app` |
| `BijbelquizApp` | `BijbelStudieApp` |
| `Bijbelquiz` | `BijbelStudie` |
| `bijbelquiz.com` | `bijbel-studie.com` |
| `bijbelquiz` | `bijbelstudie` |

Files needing explicit attention:

- `pubspec.yaml` — `name`, `description`, `version: 1.0.0+1`, add `sqflite`,
  `path_provider`.
- `lib/core/config/app_config.dart` — `_productionBaseUrl` =
  `https://www.bijbel-studie.com/api/v1`, `_developmentBaseUrl` =
  `http://localhost:3000/api/v1`, `privacyPolicyUrl`. Leave `termsOfUseUrl`
  pointing at Apple's standard EULA.
- `lib/core/config/revenuecat_config.dart` — **blank both**
  `_defaultApplePublicKey` and `_defaultGooglePublicKey` to `''`. The reference
  hardcodes Bijbelquiz's real keys as build-time defaults; the new app must not
  inherit them. Keep the `String.fromEnvironment` overrides.
- `lib/core/config/apple_sign_in_config.dart` — `serviceId` =
  `com.bijbelstudie.app.signin`, `redirectUriRaw` =
  `https://www.bijbel-studie.com/api/v1/auth/apple/callback`.
- `ios/Runner/Info.plist` — `CFBundleDisplayName` / `CFBundleName` =
  `BijbelStudie`. Replace `CFBundleURLSchemes` and `GIDClientID` with
  `PUT_YOUR_REVERSED_CLIENT_ID_HERE` / `PUT_YOUR_GID_CLIENT_ID_HERE`. **Do not**
  carry over the reference's Google client ID. Keep
  `ITSAppUsesNonExemptEncryption = false`.
- `ios/Runner/Runner.entitlements` — keep `com.apple.developer.applesignin`.
- `ios/Runner.xcodeproj/project.pbxproj` — every `PRODUCT_BUNDLE_IDENTIFIER`.
  The reference has a stale `com.example.bijbelquizMobile.RunnerTests`; set the
  new one to `com.bijbelstudie.app.RunnerTests` rather than cloning the mistake.
- `android/app/build.gradle.kts` — `namespace` + `applicationId`. Keep the
  `key.properties` signing block, `compileSdk = 36`, `minSdk = 24`.
- `android/app/src/main/AndroidManifest.xml` — `android:label`. Keep `INTERNET`
  and `com.android.vending.BILLING`.
- Move `android/app/src/main/kotlin/.../MainActivity.kt` to the new package path
  and fix its `package` line.
- `test/*.dart` — the `package:bijbelquiz_mobile/...` imports.

## B3 — Keep verbatim (rename strings only, change nothing structural)

- `core/api/api_client.dart` — Dio + bearer interceptor + 401 handling. **Extend
  it**: on 401, attempt one refresh via `/auth/refresh`, retry the original
  request once, and only then clear the token and bounce to login. Queue
  concurrent 401s so a burst triggers one refresh, not five.
- `core/theme/app_theme.dart` — the full token system (paper/ink/rule palette,
  Inter + Newsreader, `displayLarge`…`overline`, button themes). Keep the
  palette unless I give you new brand colours.
- `core/ui/app_widgets.dart` — `Eyebrow`, `GradientHeader`, `SectionHeader`,
  `RuleLine`, `AppCard`, `RuleGrid`, `StatStrip`, `SiteBadge`, `SiteButton`,
  `SiteOutlineButton`, `RuleListTile`, `AppLoader`, `AppEmptyState`.
- `core/ui/server_image.dart`, `custom_text_field.dart`, `primary_button.dart`.
- `core/config/preview_config.dart` and `core/preview/` — design-preview mode.
- `features/auth/**` — repository, secure storage, controller, splash, login,
  register, Google/Apple buttons incl. the web/stub conditional imports.
- `features/onboarding/**`.
- `features/premium/**` — see Phase C.
- `features/profile/**` — adapt the model to BijbelStudie's `/v1/me` shape.

## B4 — Delete, then build the real domain

Delete `features/quiz/`, `features/leaderboard/`, `features/multiplayer/`,
`features/dashboard/` and their routes. Build in their place:

- `features/bible/` — version picker, book/chapter navigator, reader.
- `features/commentary/` — commentary picker, chapter-synced pane.
- `features/notes/` — notes, highlights, bookmarks; offline-first.
- `features/search/` — server-side search with local history.

Use the same Riverpod patterns as the reference
(`FutureProvider.autoDispose.family`, a `Repository` class taking `ApiClient`)
and the same widget vocabulary from `app_widgets.dart`.

Rewrite `core/router/app_router.dart`: keep `MainScaffold` and `_NavItem`
styling **verbatim**, replace the tab list. Preserve the route shape —
`/` splash → `/onboarding` → `/login` `/register` → `ShellRoute` with tabs →
detail routes outside the shell.

Proposed tabs: `Lezen` `/read` · `Commentaren` `/commentary` · `Zoeken`
`/search` · `Notities` `/notes` · `Profiel` `/profile`.

**Before writing any repository method, confirm the actual response shape** by
calling the endpoint, and report what you saw. Do not infer it from the route
name. The reference app has real, shipped bugs caused by exactly that: its
`/quizzes` list endpoint hard-codes `xpReward: 50` while the detail endpoint
returns the true value, and nobody noticed for months.

---

# PHASE C — Payments (same method as the reference)

Copy `features/premium/` from the reference and change only the identifiers.

```dart
const kRcMonthlyProductId  = 'bijbelstudie_pro_monthly';
const kRcYearlyProductId   = 'bijbelstudie_pro_yearly';
const kRcMonthlyPackageId  = '\$rc_monthly';
const kRcYearlyPackageId   = '\$rc_annual';
const kRcProEntitlement    = 'pro';
```

Keep, unchanged in behaviour:

- SDK configured once in `main.dart` via `RevenueCatConfig.sdkPublicApiKey()`,
  guarded by `kIsWeb`, wrapped in try/catch so a RevenueCat outage cannot block
  app start.
- `getPackages()` reading the **current offering** (not hardcoded products),
  with the hardcoded-product-id path kept only as a fallback.
- `restorePurchases()` — **required** by App Store review; the paywall must have
  a visible "Herstel aankopen" button.
- `hasPremiumAccess()` reading the entitlement from `CustomerInfo`.

**The critical line — do not omit it.** In `auth_controller.dart` after a
successful login:

```dart
await Purchases.logIn(user.id);   // RC app_user_id == Mongo _id
```

and on logout, `await Purchases.logOut();`

The webhook does `User.findByIdAndUpdate(app_user_id, {isPro: true})`. If
`app_user_id` is not the Mongo `_id`, **every purchase silently fails to grant
access on the server.** This is the single highest-risk integration point.

Entitlement resolution order in the app: server `/v1/me.isPro` is
authoritative; RevenueCat `CustomerInfo` is the fast local signal. On mismatch,
call `/v1/sync-premium` and re-read `/v1/me`.

**Guideline 3.1.1 compliance:** no Stripe link, no "subscribe on our website"
text, no external purchase URL anywhere in the binary. Web subscribers keep Pro
through `/v1/me`; show them "Actief via web" and no purchase button.

---

# PHASE D — Signing & CI (same method as the reference)

Copy `.github/workflows/ios-release.yml` **verbatim**. Change only:

- `working-directory: bijbelquiz_mobile` → `bijbelstudie_mobile` (2 places)
- the `find bijbelquiz_mobile/build/ios/ipa ...` path in the upload step

Keep all of the following exactly. It is load-bearing and was debugged the hard
way:

- `workflow_dispatch` with optional `build_name` / `build_number`; push trigger
  stays commented out
- `maxim-lobanov/setup-xcode@v1` `latest-stable`; `subosito/flutter-action@v2`
  `3.x` with `cache: true`
- temp-keychain import of the `.p12`, including
  `security set-key-partition-list -S apple-tool:,apple:` — without it,
  `codesign` cannot reach the key in CI
- provisioning-profile decode + `PlistBuddy` extraction of UUID / Name /
  bundle ID, **including the hard failure when the profile lacks
  `com.apple.developer.applesignin`**
- generated `ExportOptions.plist`, `method: app-store-connect`,
  `signingStyle: manual`
- `flutter build ios --release --no-codesign` with `--dart-define`s, plus the
  guard clauses that fail fast on missing secrets
- `xcodebuild archive` with `CODE_SIGNING_ALLOWED=NO`, then `-exportArchive`
- the post-export `codesign -d --entitlements` verification
- `xcrun altool --upload-app` **with the output-grep failure check** — altool
  exits 0 on some rejections, and that grep is the only thing catching a
  duplicate version string
- the `if: always()` keychain / profile / `.p8` cleanup

Add `--dart-define=REVENUECAT_APPLE_KEY`, `APPLE_SERVICE_ID`,
`APPLE_REDIRECT_URI`, `USE_PRODUCTION_API=true` as in the reference.

Then write `docs/ios-release-setup.md` for this app, modelled on
`C:\Projects\bijbelquiz-app\docs\ios-release-setup.md`, with the new bundle ID.

---

# PHASE E — Offline data

355 MB of bibles/commentaries cannot ship in the IPA and must not be downloaded
wholesale on first launch.

- Transfer unit = **one chapter**. Never a whole version.
- Cache in SQLite (`sqflite`) keyed `(kind, sourceId, book, chapter)` with the
  `ETag` and `fetchedAt`. Revalidate with `If-None-Match`; a `304` refreshes
  `fetchedAt` and costs nothing.
- LRU eviction at a configurable cap (default 300 MB), surfaced in Settings as
  "Cache legen" with the current size.
- Optional explicit download: "Bewaar dit boek offline" per book, never per
  version, with a progress indicator and a cancel.
- Reader must render from cache with no network. Show a subtle offline state,
  not an error.

---

# PHASE F — Native features (guideline 4.2)

A chapter viewer alone reads as a repackaged website. Ship at least these, and
make them visible in the App Review notes and screenshots:

1. Offline reading from local cache
2. System share sheet for a verse or selection
3. Adjustable font size + line height, persisted
4. Light/dark theme following system
5. Local notifications for a daily reading reminder
6. Highlights and notes with local-first storage and sync
7. Full-text search with local history
8. Continue-reading, restoring exact scroll position
9. Haptics on highlight/bookmark, and VoiceOver labels on every interactive
   element

Accessibility is not optional: Dynamic Type support and VoiceOver labels.
Reviewers do check.

---

# PHASE G — Verify, then report

Report actual command output. Do not claim a success you did not observe.

```bash
cd bijbelstudie_mobile
flutter pub get
flutter analyze          # must be clean
flutter test             # widget render + overflow tests must pass
flutter build apk --debug
```

Backend, in `C:\Projects\bijbelstudie`:

```bash
npm test                 # incl. the 451 licensing test from section 1
```

Then grep the whole new repo and confirm **zero** occurrences of:
`bijbelquiz`, `Bijbelquiz`, `com.bijbelquiz`, `appl_`, `goog_`,
`nbg51`, `kingcomments`, and `net` as a content id.

You cannot build or verify iOS from Windows. Say that plainly — the pipeline is
proven only after the first green Actions run, not before.

---

# PHASE H — Hand me this list

Things only I can do. Do not attempt them; list them with exact "what and where".

1. **Apple Developer** → Identifiers → register App ID `com.bijbelstudie.app`,
   enable **Sign In with Apple**.
2. **Apple Developer** → Identifiers → new **Services ID**
   `com.bijbelstudie.app.signin`, redirect URI
   `https://www.bijbel-studie.com/api/v1/auth/apple/callback`.
3. **Apple Developer** → Keys → new key with **Sign in with Apple** enabled
   (needed server-side to verify Apple tokens). Note Key ID + Team ID.
4. **Apple Developer** → Profiles → new **App Store** distribution profile for
   the App ID → download `.mobileprovision`. Regenerate it *after* enabling
   Sign in with Apple, or the workflow's entitlement check fails by design.
5. **App Store Connect** → Apps → new app, bundle ID `com.bijbelstudie.app`.
6. **App Store Connect** → Users and Access → Integrations → App Store Connect
   API → Team Keys → Generate (role **App Manager**) → download `.p8`, note
   Key ID + Issuer ID.
7. **App Store Connect** → your app → Subscriptions → create group `Pro`, with
   `bijbelstudie_pro_monthly` and `bijbelstudie_pro_yearly`. Fill in
   localisations and review screenshot, or the products stay "Missing Metadata"
   and RevenueCat returns an empty offering.
8. **Google Cloud Console** → Credentials → OAuth client ID (iOS) for
   `com.bijbelstudie.app` → paste the client ID and its reversed form into
   `ios/Runner/Info.plist`.
9. **RevenueCat** → new Project → add iOS + Android apps → create the two
   products → entitlement `pro` → an Offering with both packages → Integrations
   → Webhooks → `https://www.bijbel-studie.com/api/mobile/revenuecat-webhook`
   with a secret stored as `REVENUECAT_WEBHOOK_SECRET`.
10. **GitHub repo** → Settings → Secrets and variables → Actions:
    - Secrets: `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`,
      `BUILD_PROVISION_PROFILE_BASE64`, `KEYCHAIN_PASSWORD`, `APPLE_TEAM_ID`,
      `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
      `APP_STORE_CONNECT_API_KEY_P8`, `REVENUECAT_APPLE_KEY`
    - Variables: `APPLE_SERVICE_ID`, `APPLE_REDIRECT_URI`
11. **Vercel** → env vars for the backend: `REVENUECAT_WEBHOOK_SECRET`,
    `APPLE_SIGNIN_KEY_ID`, `APPLE_SIGNIN_TEAM_ID`, `APPLE_SIGNIN_PRIVATE_KEY`,
    `MOBILE_JWT_SECRET`.
12. **Licensing** (section 1) — obtain written permission for NBG51,
    KingComments and NET, or confirm they stay out of the mobile allowlist.

---

# Guardrails

- Never commit a certificate, keystore, `.p8`, `.p12`, `.mobileprovision`, or
  `key.properties`. Verify `.gitignore` covers all of them before the first
  commit.
- No RevenueCat key hardcoded as a Dart default. Build-time `--dart-define` only.
- No blocked content id reachable from any `/v1/*` route, under any parameter.
- No Stripe link or external purchase path in the binary.
- Do not invent backend response shapes. Call the endpoint, report what came
  back, then write the model.
- Do not "modernise" dependencies, lints, or folder names away from the
  reference. Matching it is the point.
- If a phase is blocked, finish every other phase in full and tell me exactly
  what you skipped and why. Do not silently narrow the scope.
