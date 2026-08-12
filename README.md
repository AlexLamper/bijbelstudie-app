# BijbelStudie — iOS app

Native **Flutter** app for [www.bijbel-studie.com](https://www.bijbel-studie.com),
structurally cloned from an already-shipping Flutter app of ours and adapted to
a Bible-reading domain.

```
.
├─ .github/
│  ├─ workflows/ios-release.yml            manual TestFlight pipeline
│  └─ instructions/flutter-architecture.instructions.md
├─ bijbelstudie_mobile/                    the Flutter app
│  ├─ lib/
│  │  ├─ core/{api,config,data,db,notifications,preview,router,theme,ui}/
│  │  ├─ features/
│  │  │  ├─ ai/          {data,present}      AI-assistent tab
│  │  │  ├─ auth/        {data,domain,present}
│  │  │  ├─ bible/       {data,domain,present}
│  │  │  ├─ commentary/  {data,present}
│  │  │  ├─ dashboard/   {data,present}      the /dashboard tab
│  │  │  ├─ feedback/    {present}
│  │  │  ├─ groups/      {data,present}      /groepen
│  │  │  ├─ notes/       {data,domain,present}
│  │  │  ├─ onboarding/  {data,present}
│  │  │  ├─ premium/     {data,present}
│  │  │  ├─ profile/     {data,present}
│  │  │  ├─ resources/   {data,present}      /hulpbronnen
│  │  │  ├─ search/      {present}
│  │  │  ├─ settings/    {data,present}
│  │  │  ├─ studies/     {data,present}      /studies + leesplannen
│  │  │  └─ study/       {data,present}      /studie — the split view
│  │  └─ main.dart
│  ├─ assets/{fonts,images}/
│  ├─ android/  ios/  test/
│  ├─ analysis_options.yaml
│  └─ pubspec.yaml
├─ docs/ios-release-setup.md
└─ README.md
```

Feature-first clean architecture: `data/` = repositories, models and local
storage; `domain/` = entities; `present/` = screens and Riverpod providers.

---

## The backend

The app talks to `/api/v1/*` on the existing Next.js site
(`C:\Projects\bijbelstudie`). That surface was added alongside the website's
cookie routes, which are untouched — one database, one content store, two
clients.

| | Website | App |
|---|---|---|
| Auth | NextAuth session cookie | `Authorization: Bearer <jwt>` |
| Routes | `/api/*` | `/api/v1/*` |
| Payments | Stripe | RevenueCat / StoreKit |

`lib/apiAuth.ts` resolves a caller from either, so route logic can be shared.

### The `/api/v1` surface

| Route | Serves |
|---|---|
| `auth/*`, `me`, `account` | login, refresh, profile, deletion |
| `bibles/*`, `commentaries/*`, `original/*`, `search` | content, behind the licensing gate |
| `notes`, `highlights`, `bookmarks`, `reading-history`, `sync` | user data |
| `dashboard` | the whole Start tab in one request |
| `streak`, `last-read`, `daytext` | reading progress and the verse of the day |
| `plans`, `plans/enrollment`, `plans/progress` | leesplannen |
| `studies`, `resources` | curated studies and the Hulpbronnen library |
| `groups/*` | groepen, their roster and their messages |
| `ai/chat` | the AI-assistent tab (Gemini, same caps as the site) |
| `tts` | voorlezen (Google Cloud TTS, proxied so the key stays server-side) |
| `summary`, `geo/images` | the "Algemene info" tab |
| `preferences`, `feedback` | settings shared with the website, in-app feedback |
| `sync-premium` | reconciles Pro with RevenueCat after a restore |

`dashboard` exists because the website assembles that screen from six parallel
`fetch` calls; on a phone that is six round trips before anything renders.

---

## Content licensing — read this before adding a source

Three sources on the website may **not** ship in the app:

| Source | Why |
|---|---|
| `nbg51` | NBG-vertaling 1951 licence covers `www.bijbel-studie.com` only |
| `net` | NET Bible: whole-text electronic distribution needs written permission and "cannot be bundled with anything sold" |
| `kingcomments_nl` | © Stichting Titus / Uitgeverij Daniël; they ship their own App Store app |

Plus `hsv`, `basisbijbel`, `schlachter` and `afri`, which are copyrighted or
uncleared.

The gate is **server-side**, in `lib/mobileLicensing.ts`. Every `/api/v1`
content route calls `assertMobileAllowed()` before touching the filesystem, and
a blocked id returns **451 Unavailable For Legal Reasons** regardless of how the
request is spelled. The app cannot receive blocked text even if someone crafts
the request by hand.

`tests/v1ContentRoutes.test.ts` asserts this on every content route. If that
test does not pass, the app is not ready to build.

Getting permission for one of these is a one-line change to the allowlist.

STEPBible originals are CC BY 4.0 and the attribution is rendered in the
Grondtekst tab — that is a licence condition, not a footnote.

---

## Running it

```bash
cd bijbelstudie_mobile
flutter pub get
flutter analyze
flutter test

# Against a local backend (npm run dev in C:\Projects\bijbelstudie):
flutter run                                     # iOS simulator / desktop
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1   # Android emulator

# Against production:
flutter run --dart-define=USE_PRODUCTION_API=true

# Design preview — canned data, no login, no backend:
flutter run -d chrome --dart-define=PREVIEW=true
```

### Build-time configuration

Nothing secret is hardcoded. Everything below is a `--dart-define`:

| Define | Needed for |
|---|---|
| `REVENUECAT_APPLE_KEY` / `REVENUECAT_GOOGLE_KEY` | purchases. Both default to `''` |
| `APPLE_SERVICE_ID`, `APPLE_REDIRECT_URI` | Sign in with Apple web fallback |
| `GOOGLE_WEB_CLIENT_ID` | Google Sign-In on Android and web (iOS reads Info.plist) |
| `API_BASE_URL`, `USE_PRODUCTION_API` | which backend to talk to |
| `PRIVACY_POLICY_URL`, `TERMS_OF_USE_URL` | legal links |

---

## Releasing

`docs/ios-release-setup.md`. The workflow is manual
(`workflow_dispatch`) and needs the secrets listed there.

**iOS cannot be built or verified from Windows.** The pipeline is proven after
the first green Actions run, not before.
