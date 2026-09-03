# What is done, and what is still on you

Last updated 2026-08-12.

| | Value |
|---|---|
| iOS bundle ID | `com.bijbel-studie.app` |
| Android applicationId | `com.bijbelstudie.app` (no hyphen — Android forbids it) |
| Services ID | `com.bijbel-studie.app.signin` |
| Apple Team ID | `4K4D59MXKW` |
| App Store Connect app id | `6800668187` ("BijbelStudie App") |
| Repo | <https://github.com/AlexLamper/bijbelstudie-app> |
| Backend | `https://www.bijbelstudie.io` |
| Apple redirect URI | `https://www.bijbelstudie.io/api/v1/auth/apple/callback` |

---

## Already done — do not redo these

| Thing | State |
|---|---|
| Git repo + GitHub remote | `AlexLamper/bijbelstudie-app`, public, `main` pushed |
| CI trigger | every push to `main` builds and uploads to TestFlight; `workflow_dispatch` still works |
| Distribution `.p12` | rebuilt from `distribution.pem` + `distribution_key.pem`, password `BijbelStudie2026`, saved as `apple-signing/BijbelStudie/BijbelStudie_distribution.p12` |
| Provisioning profile | **regenerated** as `BijbelStudie App Store CI` (id `2XWYGY5WRY`) — see the warning below |
| GitHub secrets | all set, `REVENUECAT_APPLE_KEY` included (set 2026-08-12) |
| GitHub variables | `APPLE_SERVICE_ID`, `APPLE_REDIRECT_URI` |
| App Store Connect subscriptions | group `Pro`, `bijbelstudie_pro_monthly` (€9,99/mnd) and `bijbelstudie_pro_yearly` (€69,99/jr), Dutch localisations, all 175 territories — both are **approved by Apple** and purchasable |
| Vercel env vars | `MOBILE_JWT_SECRET`, `APPLE_CLIENT_IDS`, `GEMINI_API_KEY`, `GOOGLE_TTS_API_KEY`, `REVENUECAT_WEBHOOK_AUTHORIZATION`, `REVENUECAT_PRO_ENTITLEMENT_ID` added to Production/Preview/Development and redeployed |

> **Why the profile was regenerated.** The `BijbelStudie App Store` profile you
> downloaded is bound to certificate serial `607E78BC…` — an *iPhone
> Distribution* cert from 2026-03-31 whose private key is not on this machine.
> The only private key you have is for *Apple Distribution* serial `3DEF2785…`
> (`distribution_key.pem`, expires 2027-05-02). A profile that does not list
> the signing certificate cannot sign the archive. The new profile lists the
> right one. The old profile still exists; you can delete it in the Apple
> Developer portal.

---

## Step 1 — RevenueCat (this is the only thing blocking a green build)

Everything else is wired. The workflow deliberately refuses to build without
`REVENUECAT_APPLE_KEY`, because a build with a broken paywall is worse than no
build.

### 1.1 In App Store Connect: the In-App Purchase key

RevenueCat needs this to verify StoreKit 2 transactions.

You may already have one — check for
`apple-signing/SubscriptionKey_ZD2BGDJ4JU.p8`. Apple names In-App Purchase keys
`SubscriptionKey_<KEYID>.p8`, and the key is team-wide, so that file works for
BijbelStudie too. Its Key ID is `ZD2BGDJ4JU`.

If you do not have it or are unsure:

1. <https://appstoreconnect.apple.com/access/integrations/api>
2. **In-App Purchase** tab → **+**
3. Name it `RevenueCat`, **Generate**, **Download**. Once only.

### 1.2 Create the RevenueCat project

1. <https://app.revenuecat.com> → sign up / log in.
2. **Create new project** → name `BijbelStudie` → **Create project**.

### 1.3 Add the App Store app

1. In the project: **Project settings → Apps → + New → App Store**.
2. **App name:** `BijbelStudie`
3. **App bundle ID:** `com.bijbel-studie.app`
4. **Save**.

On the app's settings page that opens:

5. **App Store Connect API** → upload `AuthKey_6KPH737U27.p8`
   - **Issuer ID:** `6de0d408-c678-4c60-9a6f-572cf850399d`
   - **Key ID:** `6KPH737U27`
6. **In-app purchase key** → upload the `SubscriptionKey_*.p8` from 1.1.
7. Copy the **public app-specific API key** at the top of the page. It starts
   with `appl_`.

> That `appl_…` string is `REVENUECAT_APPLE_KEY`. Send it to me, or set it
> yourself:
> ```bash
> gh secret set REVENUECAT_APPLE_KEY --repo AlexLamper/bijbelstudie-app --body "appl_xxxxx"
> ```

### 1.4 Import the products

1. **Product catalog → Products → + New**.
2. **Store:** App Store. **Identifier:** `bijbelstudie_pro_monthly` → **Add**.
3. Repeat for `bijbelstudie_pro_yearly`.

Both already exist in App Store Connect, so RevenueCat will find them. If it
says it cannot, wait 15 minutes — Apple's product propagation is slow.

### 1.5 Entitlement

1. **Product catalog → Entitlements → + New**.
2. **Identifier:** `pro` — exactly this, lowercase. `purchase_service.dart` and
   the backend both key off it.
3. **Add** → open it → **Attach products** → attach both.

### 1.6 Offering

1. **Product catalog → Offerings → + New**.
2. **Identifier:** `default`, **Description:** `Standaard`.
3. Open it → **+ New Package** twice:
   - **Identifier:** `$rc_monthly` → attach `bijbelstudie_pro_monthly`
   - **Identifier:** `$rc_annual` → attach `bijbelstudie_pro_yearly`
4. Mark the offering **Current**.

The paywall reads packages from the current offering. Not marked current means
an empty paywall with `—` for both prices.

### 1.7 Webhook

1. **Project settings → Integrations → + New → Webhooks**.
2. **Webhook URL:** `https://www.bijbelstudie.io/api/mobile/revenuecat-webhook`
3. **Authorization header value:** the value already stored in Vercel as
   `REVENUECAT_WEBHOOK_AUTHORIZATION`. Read it back with:
   ```bash
   cd C:\Projects\bijbelstudie
   vercel env pull .env.vercel.tmp
   ```
   then copy the value and delete that file.
4. **Environment:** send **both** Sandbox and Production.
5. **Save**.

### 1.8 REST API key

1. **Project settings → API keys → Secret API keys → + New**.
2. Name `Backend sync`, read access on Customers is enough.
3. Copy the `sk_…` value — shown once — and add it to Vercel:
   ```bash
   cd C:\Projects\bijbelstudie
   printf 'sk_xxxxx' | vercel env add REVENUECAT_REST_API_KEY production
   ```
   Repeat for `preview` and `development`, then redeploy.

> Without this, `/api/v1/sync-premium` cannot run. That endpoint is what unlocks
> Pro after a **restore** or an **already-owned** purchase — RevenueCat sends no
> webhook for either. Skipping it means some paying users stay locked out.

---

## Step 2 — Sandbox tester

1. <https://appstoreconnect.apple.com/access/users> → **Sandbox Testers**.
2. **+** → any name, an email that is **not** already an Apple ID (a `+` alias
   works: `you+sandbox@gmail.com`), region **Netherlands** → **Invite**.
3. On the test iPhone: **Settings → App Store → Sandbox Account** → sign in as
   this tester. Do **not** sign into iCloud with it.

---

## Step 3 — Finish the App Store Connect listing

The app record exists but is empty. In <https://appstoreconnect.apple.com/apps>
→ BijbelStudie App → the `1.0` version:

- [ ] **App name.** Currently `BijbelStudie App`. Rename to `BijbelStudie` if
      it is still free, under **App Information**.
- [ ] **Subtitle**, **Promotional text**, **Keywords** - Dutch.
- [ ] **Description.** Paste the block under "The App Description to paste" in
      `docs/app-review-1.0.1-rejection.md` verbatim. It is not free copy: the
      1.0.1 (11) rejection was guideline 3.1.2, because the product page carried
      no Terms of Use (EULA) link. The description must keep, as plain-text
      clickable URLs, all three of:
      `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`,
      `https://www.bijbelstudie.io/privacybeleid` and
      `https://www.bijbelstudie.io/algemene-voorwaarden`, plus the name,
      length and price of both subscriptions. Rewriting the description without
      them re-earns the same rejection.
- [ ] **App Information → License Agreement.** Leave it on Apple's **standard**
      EULA. The app links that EULA from the paywall (`AppConfig.termsOfUseUrl`),
      so a custom agreement pasted here would contradict the binary.
- [ ] **Screenshots.** 6.7" (1290×2796) and 6.5" (1284×2778) are mandatory.
      Take them on an iPhone 15 Pro Max simulator: `flutter run`, then ⌘S.
- [ ] **Subscription review screenshots.** Each of the two products needs one
      under **Review Information**, or it stays in *Missing Metadata* forever.
      A simulator shot of the paywall is fine.
- [ ] **Support URL:** `https://www.bijbelstudie.io/contact`
- [ ] **Privacy policy URL:** `https://www.bijbelstudie.io/privacybeleid`
      (the old `/privacy-policy` only resolves through a 308, and review does
      click these)
- [ ] **Age rating:** 4+, nothing objectionable.
- [ ] **Privacy nutrition labels:** email address, name, user content
      (notes/highlights), identifiers, purchases. Linked to identity: yes.
      Used for tracking: no.
- [x] **Reviewer account.** Done — `applereview@mail.com`, created by
      `scripts/ensure-review-account.mjs` in the bijbelstudie repo. Re-run it
      with `--write` if the credentials ever stop working. Note it grants Pro
      through `subscribed`, not `storePremium`: the launch-time RevenueCat sync
      overwrites the latter. See `docs/app-review-1.0.5-rejection.md`.
- [ ] **App Review notes.** Paste this:
      > The Bible translations and commentaries in this app are public domain.
      > The original-language text is STEPBible (TAHOT/TAGNT), CC BY 4.0, and
      > the attribution is displayed in the Grondtekst tab. Subscriptions use
      > StoreKit via RevenueCat. Existing web subscribers retain access under
      > the multiplatform exception (guideline 3.1.1(b)). Account deletion is
      > at Profiel → Account verwijderen.

Worth doing while you are there: enrol in the **App Store Small Business
Program** (<https://developer.apple.com/app-store/small-business-program/>).
It drops Apple's cut from 30% to 15% — on €9,99 that is €8,49 to you instead of
€7,02.

---

## Step 4 — Google Sign-In on iOS

The code side is done. What is left is **three pieces of configuration**, all
manual, none of which can be created from this repo:

1. **Google Cloud** — create an OAuth client, type *iOS*, bundle ID
   `com.bijbel-studie.app`, in the same project as the existing web client.
2. **Vercel** — add that client id to `GOOGLE_MOBILE_CLIENT_IDS`
   (comma-separated, alongside the web client id) and redeploy. The server pins
   the ID token's `aud`, so it rejects tokens from a client it has not been
   told about.
3. **GitHub repository variables** — `GOOGLE_IOS_CLIENT_ID` and
   `GOOGLE_WEB_CLIENT_ID`. The workflow passes both as `--dart-define` and
   substitutes the `Info.plist` placeholders during the build.

Full walkthrough with examples: `docs/ios-release-setup.md`, Step 2.

Until all three are in place the app behaves exactly as it did before: the
Google button is gated on `GoogleSignInConfig.isAvailable`, which is false
without a client id, so the login and register screens render Sign in with Apple
and email/password only.

**Sign in with Apple is no longer optional once Google is on.** Guideline 4.8
requires a privacy-preserving equivalent beside any third-party login, so both
screens now render the Apple button on iOS. It was already implemented in
`AuthController.signInWithApple`; it had simply never been placed on a screen,
which was fine only while iOS offered no third-party login at all.

Accounts link themselves: `/api/v1/auth/google` matches on `googleId`, then
falls back to a case-insensitive email match and attaches `googleId` to the
account it finds. Signing in with Google on the phone therefore reaches the same
account as the website — including one originally created with a password.

---

## Step 5 — Content licensing

Three sources on the website may **not** ship in the app. The block is
server-side in `lib/mobileLicensing.ts`; every `/api/v1` content route answers
**451 Unavailable For Legal Reasons** for them regardless of how the request is
spelled. Verified live on production.

| Source | Why | Who to ask |
|---|---|---|
| `nbg51` | NBG-vertaling 1951 licence covers `www.bijbel-studie.com` only. Your contract runs to 2029-12-31 and is website-scoped. | Nederlands-Vlaams Bijbelgenootschap — ask for an app addendum |
| `net` | NET Bible: whole-text electronic distribution needs written permission and "cannot be bundled with anything sold" | permissions@netbible.com |
| `kingcomments_nl` | © Stichting Titus / Uitgeverij Daniël; they ship their own App Store app | Stichting Titus / Uitgeverij Daniël |

Also blocked: `hsv`, `basisbijbel`, `schlachter`, `afri`.

Granting one is a one-line change to the relevant `Set` in
`lib/mobileLicensing.ts` plus its attribution in `lib/mobileAttribution.ts`.
Keep the written permissions on file — Apple asks under guideline 5.2 if anyone
complains.

---

## Reference: the CI pipeline

`.github/workflows/ios-release.yml`, `macos-latest`.

| Secret | Set? |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | yes |
| `P12_PASSWORD` | yes (`BijbelStudie2026`) |
| `BUILD_PROVISION_PROFILE_BASE64` | yes (the CI profile) |
| `KEYCHAIN_PASSWORD` | yes (random) |
| `APPLE_TEAM_ID` | yes |
| `APP_STORE_CONNECT_KEY_ID` | yes (`6KPH737U27`) |
| `APP_STORE_CONNECT_ISSUER_ID` | yes |
| `APP_STORE_CONNECT_API_KEY_P8` | yes |
| `REVENUECAT_APPLE_KEY` | yes (set 2026-08-12) |

| Variable | Value |
|---|---|
| `APPLE_SERVICE_ID` | `com.bijbel-studie.app.signin` |
| `APPLE_REDIRECT_URI` | `https://www.bijbelstudie.io/api/v1/auth/apple/callback` |

The build number is `github.run_number`, which only increases, so consecutive
pushes cannot collide. The version name comes from `pubspec.yaml` unless you
override it on a manual run.

Common failures:

- `Missing required secret: REVENUECAT_APPLE_KEY` → Step 1.
- `Provisioning profile is missing Sign in with Apple entitlement` → the profile
  was generated before the capability was enabled on the App ID.
- `No signing certificate` → the `.p12` has no private key in it.
- `Authentication failed` on upload → wrong Issuer ID, or the API key has
  Developer rather than App Manager access.

**iOS cannot be built or verified from Windows.** The pipeline is proven by a
green Actions run, not by reading it.
