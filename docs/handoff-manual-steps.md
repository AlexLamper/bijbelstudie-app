# Setup you have to do yourself

Everything below needs a login to an account I do not have. Nothing here is
optional if you want the app in the App Store with working sign-in and working
payments.

Work top to bottom. Steps depend on each other, and the order matters in three
places (marked **⚠ order**).

| | Value |
|---|---|
| Bundle ID | `com.bijbelstudie.app` |
| Services ID | `com.bijbelstudie.app.signin` |
| App name | BijbelStudie |
| Backend | `https://www.bijbel-studie.com` |
| Apple redirect URI | `https://www.bijbel-studie.com/api/v1/auth/apple/callback` |

Keep a scratch file open. You will collect about a dozen values along the way,
and several of them are shown exactly once.

---

## Part 1 — Apple Developer Program

You need a paid membership (€99/year). If you do not have one:
<https://developer.apple.com/programs/enroll/>. Approval takes 24–48 hours for
an individual, longer for a company (a D-U-N-S number is required).

### 1.1 Find your Team ID

1. Sign in at <https://developer.apple.com/account>.
2. Scroll to **Membership details**.
3. Copy **Team ID** — 10 characters, e.g. `A1B2C3D4E5`.

> **Write down:** `APPLE_TEAM_ID`

### 1.2 Register the App ID

1. <https://developer.apple.com/account/resources/identifiers/list>
2. Click the blue **+**.
3. Select **App IDs** → **Continue**.
4. Select **App** → **Continue**.
5. **Description:** `BijbelStudie`
6. **Bundle ID:** select **Explicit**, type `com.bijbelstudie.app`
7. Scroll the **Capabilities** list and tick:
   - **Sign In with Apple** (mandatory — the app offers Google sign-in, and
     Apple's guideline 4.8 then requires Sign in with Apple too)
   - **In-App Purchase** (usually ticked already and greyed out)
   - **Push Notifications** — only if you later want server-sent reminders. The
     daily reading reminder in the app is local, so you can leave this off.
8. **Continue** → **Register**.

### 1.3 Create the Services ID (for Sign in with Apple)

1. Same Identifiers page, click **+**.
2. Select **Services IDs** → **Continue**.
3. **Description:** `BijbelStudie Sign In`
4. **Identifier:** `com.bijbelstudie.app.signin`
5. **Continue** → **Register**.
6. Now click the Services ID you just made to edit it.
7. Tick **Sign In with Apple** → click **Configure**.
8. **Primary App ID:** choose `com.bijbelstudie.app`.
9. **Domains and Subdomains:** `www.bijbel-studie.com`
10. **Return URLs:** `https://www.bijbel-studie.com/api/v1/auth/apple/callback`
11. **Next** → **Done** → **Continue** → **Save**.

> Apple rejects a bare domain here if it does not resolve over HTTPS. The site
> is live, so this passes — but if you get "domain verification failed", it is
> almost always a typo in the domain, not a real DNS problem.

### 1.4 Create the Sign in with Apple key

1. <https://developer.apple.com/account/resources/authkeys/list>
2. Click **+**.
3. **Key Name:** `BijbelStudie Sign In Key`
4. Tick **Sign in with Apple** → click **Configure** next to it.
5. **Primary App ID:** `com.bijbelstudie.app` → **Save**.
6. **Continue** → **Register**.
7. **Download** the `.p8` file. **You can only download it once.** Put it
   somewhere you will not lose it.
8. Copy the **Key ID** shown on the confirmation page (10 characters).

> **Write down:** Apple Sign In Key ID, and keep the `.p8` file.
> This key is not needed by the current backend — it verifies Apple identity
> tokens using Apple's public JWKS — but Apple support will ask for it if
> anything goes wrong, and you cannot regenerate a lost `.p8`.

### 1.5 Create the distribution certificate

You need a Mac for this step, or a Mac in the cloud
(<https://www.macincloud.com>, ~$1/hour, or a borrowed machine for 20 minutes).

**On the Mac:**

1. Open **Keychain Access** (Applications → Utilities).
2. Menu **Keychain Access → Certificate Assistant → Request a Certificate From
   a Certificate Authority…**
3. **User Email Address:** your Apple ID email
4. **Common Name:** `BijbelStudie Distribution`
5. **CA Email Address:** leave empty
6. Select **Saved to disk** → **Continue** → save `CertificateSigningRequest.certSigningRequest`.

**Back in the browser:**

7. <https://developer.apple.com/account/resources/certificates/list> → **+**
8. Select **Apple Distribution** → **Continue**.
9. Upload the `.certSigningRequest` file → **Continue**.
10. **Download** the resulting `distribution.cer`.

**Back on the Mac:**

11. Double-click `distribution.cer` — it installs into Keychain Access.
12. In Keychain Access, **login** keychain → **My Certificates**.
13. Find **Apple Distribution: <your name> (TEAMID)**, right-click →
    **Export "Apple Distribution: …"**.
14. File format **Personal Information Exchange (.p12)**, save as
    `certificate.p12`.
15. It asks for a password. **Invent one and write it down** — this is
    `P12_PASSWORD`.
16. Convert it to base64 for GitHub (in Terminal):

    ```bash
    base64 -i certificate.p12 | pbcopy
    ```

    That puts the whole thing on your clipboard. Paste it into your scratch
    file immediately.

> **Write down:** `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`

### 1.6 Create the provisioning profile

**⚠ order:** do this **after** step 1.2, or the profile will not carry the Sign
in with Apple entitlement and the CI build fails a deliberate check with
`missing com.apple.developer.applesignin`.

1. <https://developer.apple.com/account/resources/profiles/list> → **+**
2. Under **Distribution**, select **App Store Connect** → **Continue**.
3. **App ID:** `com.bijbelstudie.app` → **Continue**.
4. Select the **Apple Distribution** certificate from 1.5 → **Continue**.
5. **Provisioning Profile Name:** `BijbelStudie App Store` → **Generate**.
6. **Download** the `.mobileprovision`.
7. Base64 it the same way:

    ```bash
    base64 -i BijbelStudie_App_Store.mobileprovision | pbcopy
    ```

    On Windows, in Git Bash:

    ```bash
    base64 -w 0 BijbelStudie_App_Store.mobileprovision > profile.txt
    ```

> **Write down:** `BUILD_PROVISION_PROFILE_BASE64`

---

## Part 2 — App Store Connect

### 2.1 Create the app record

1. <https://appstoreconnect.apple.com/apps> → **+** → **New App**.
2. **Platforms:** iOS
3. **Name:** `BijbelStudie` — this must be globally unique across the App
   Store. If it is taken, use `BijbelStudie - Bijbel lezen`.
4. **Primary Language:** Dutch (Netherlands)
5. **Bundle ID:** select `com.bijbelstudie.app` from the dropdown. If it is not
   there, step 1.2 did not complete.
6. **SKU:** `bijbelstudie-ios-001` (internal only, never shown)
7. **User Access:** Full Access
8. **Create**.

### 2.2 Create the App Store Connect API key (for CI upload)

1. <https://appstoreconnect.apple.com/access/integrations/api>
2. Make sure you are on the **Team Keys** tab (not Individual Keys).
3. Click **+**.
4. **Name:** `GitHub Actions Upload`
5. **Access:** **App Manager**
6. **Generate**.
7. **Download** the `.p8`. **Once only.**
8. Copy the **Key ID** (10 chars) and the **Issuer ID** (a UUID, shown above
   the table).

> **Write down:** `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
> and the contents of the `.p8` file (open it in a text editor — it is plain
> text starting `-----BEGIN PRIVATE KEY-----`). That text is
> `APP_STORE_CONNECT_API_KEY_P8`.

### 2.3 Create the subscriptions

**⚠ order:** RevenueCat (Part 4) cannot see products that do not exist here
yet, and it will silently return an empty offering — the paywall then shows
`—` for both prices and no purchase can complete.

1. In your app → sidebar **Monetization → Subscriptions**.
2. Click **+** next to **Subscription Groups**.
3. **Reference Name:** `Pro` → **Create**.
4. Inside the group, click **+** to create the first subscription:
   - **Reference Name:** `BijbelStudie Pro Monthly`
   - **Product ID:** `bijbelstudie_pro_monthly` — exactly this string
   - **Create**
5. Fill in, on the product page:
   - **Subscription Duration:** 1 Month
   - **Subscription Prices** → **Add Subscription Price** → country
     **Netherlands** → pick your price (e.g. €4,99) → Apple fills in the rest
     of the world → **Confirm**.
   - **App Store Localization** → **+** → **Dutch (Netherlands)**
     - **Subscription Display Name:** `BijbelStudie Pro — maandelijks`
     - **Description:** `Alle commentaren, de grondtekst, offline lezen en
       onbeperkt gebruik van de AI-assistent.`
   - **Review Information** → upload a **screenshot** of the paywall screen.
     This is required. Without it the product stays in *Missing Metadata*
     forever. A screenshot from the simulator is fine.
6. Repeat for the yearly plan:
   - **Reference Name:** `BijbelStudie Pro Yearly`
   - **Product ID:** `bijbelstudie_pro_yearly`
   - **Duration:** 1 Year
   - Price, Dutch localization, and a review screenshot again.

Both products should end at status **Ready to Submit**. Anything else means a
field is missing.

### 2.4 Create a sandbox tester

You need this to test a purchase without being charged.

1. <https://appstoreconnect.apple.com/access/users> → **Sandbox Testers** tab
   (left sidebar, under *Sandbox*).
2. **+** → fill in a name and an email address that is **not** already an Apple
   ID. A `+` alias works: `you+sandbox@gmail.com`.
3. Password, region **Netherlands** → **Invite**.

> On the test device: **Settings → App Store → Sandbox Account** → sign in with
> this tester. Do **not** sign into iCloud with it.

---

## Part 3 — Google Cloud (Sign in with Google)

### 3.1 OAuth consent screen

Skip if the website's Google login already works — it uses the same project.
Verify at <https://console.cloud.google.com/apis/credentials/consent> that the
project is **In production** and lists `www.bijbel-studie.com` as an authorised
domain.

### 3.2 iOS client ID

1. <https://console.cloud.google.com/apis/credentials>
2. **+ Create Credentials** → **OAuth client ID**
3. **Application type:** iOS
4. **Name:** `BijbelStudie iOS`
5. **Bundle ID:** `com.bijbelstudie.app`
6. **Create**.
7. The dialog shows a **Client ID** like
   `123456789-abcdefg.apps.googleusercontent.com` and an **iOS URL scheme**
   like `com.googleusercontent.apps.123456789-abcdefg` (the reversed client ID).

Now edit `bijbelstudie_mobile/ios/Runner/Info.plist` and replace the two
placeholders:

| Key | Replace | With |
|---|---|---|
| `CFBundleURLSchemes` first item | `PUT_YOUR_REVERSED_CLIENT_ID_HERE` | the iOS URL scheme, e.g. `com.googleusercontent.apps.123456789-abcdefg` |
| `GIDClientID` | `PUT_YOUR_GID_CLIENT_ID_HERE` | the full Client ID, e.g. `123456789-abcdefg.apps.googleusercontent.com` |

Commit that change. It is not a secret — Google client IDs are public by
design.

### 3.3 Android client ID (only when you ship to Play)

1. Same page → **+ Create Credentials** → **OAuth client ID**
2. **Application type:** Android
3. **Package name:** `com.bijbelstudie.app`
4. **SHA-1 certificate fingerprint:** get it with

   ```bash
   cd bijbelstudie_mobile/android
   ./gradlew signingReport
   ```

   and copy the `SHA1` under `Variant: release`.
5. **Create**.

### 3.4 Web client ID

The Android and web builds need one, and the backend needs it in its allowlist.

1. **+ Create Credentials** → **OAuth client ID** → **Web application**
2. **Name:** `BijbelStudie Web (mobile)`
3. No redirect URIs needed for this use.
4. **Create**, copy the Client ID.

> **Write down:** the iOS, Android and Web client IDs. All three go into
> `GOOGLE_MOBILE_CLIENT_IDS` in Part 6, comma-separated.

---

## Part 4 — RevenueCat (payments)

Free up to $2,500/month of tracked revenue. <https://app.revenuecat.com>

### 4.1 Project and apps

1. Sign up, then **Create new project** → name it `BijbelStudie`.
2. **Project settings → Apps → + New** → **App Store**.
   - **App name:** BijbelStudie
   - **App bundle ID:** `com.bijbelstudie.app`
   - **Save**.
3. On the app's page, find **App Store Connect API** and paste the same
   `.p8`, **Key ID** and **Issuer ID** from step 2.2. This is what lets
   RevenueCat verify receipts and read your subscription status.
4. Also on that page, **In-app purchase key** → upload the *In-App Purchase*
   key. If you do not have one:
   App Store Connect → **Users and Access → Integrations → In-App Purchase**
   → **+** → download the `.p8` → upload it here. RevenueCat needs this for
   StoreKit 2.
5. Copy the **Public app-specific API key** at the top — it starts `appl_`.

> **Write down:** `REVENUECAT_APPLE_KEY` (the `appl_…` value)

Repeat 4.2–4.5 for a **Play Store** app later if you ship Android; the key
starts `goog_`.

### 4.2 Products

1. **Product catalog → Products → + New**.
2. **Store:** App Store, **Identifier:** `bijbelstudie_pro_monthly` → **Add**.
3. Repeat for `bijbelstudie_pro_yearly`.

If RevenueCat says it cannot find the product, App Store Connect has not
finished processing it. Wait 15 minutes and retry.

### 4.3 Entitlement

1. **Product catalog → Entitlements → + New**.
2. **Identifier:** `pro` — exactly this, lowercase. The backend defaults to it.
3. **Add**.
4. Open the entitlement → **Attach products** → attach both products.

### 4.4 Offering

1. **Product catalog → Offerings → + New**.
2. **Identifier:** `default`, **Description:** `Standaard`.
3. Open it → **+ New Package**:
   - **Identifier:** `$rc_monthly`, attach `bijbelstudie_pro_monthly`
   - **Identifier:** `$rc_annual`, attach `bijbelstudie_pro_yearly`
4. Make sure the offering is marked **Current**.

The paywall reads packages from the current offering. If it is not marked
current, the app shows an empty paywall.

### 4.5 Webhook

1. **Project settings → Integrations → + New → Webhooks**.
2. **Webhook URL:**
   `https://www.bijbel-studie.com/api/mobile/revenuecat-webhook`
3. **Authorization header value:** invent a long random string. Generate one:

   ```bash
   node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
   ```

4. **Environment:** send both Sandbox and Production.
5. **Save**.

> **Write down:** `REVENUECAT_WEBHOOK_AUTHORIZATION` (the same random string)

### 4.6 REST API key

1. **Project settings → API keys**.
2. Under **Secret API keys**, click **+ New**, name it `Backend sync`,
   scope **read-only** on Customers is enough.
3. Copy the `sk_…` value. **Shown once.**

> **Write down:** `REVENUECAT_REST_API_KEY`
>
> Without this, `/api/v1/sync-premium` cannot work — and that endpoint is what
> unlocks Pro after a **restore** or an **already-owned** purchase, for which
> RevenueCat never sends a webhook. Skipping this key means some paying users
> stay locked out.

---

## Part 5 — GitHub Actions secrets

Repo → **Settings → Secrets and variables → Actions**.

### Secrets tab (**New repository secret** for each)

| Name | Value from |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | step 1.5 |
| `P12_PASSWORD` | step 1.5 |
| `BUILD_PROVISION_PROFILE_BASE64` | step 1.6 |
| `KEYCHAIN_PASSWORD` | invent any random string; it is only used inside the CI runner |
| `APPLE_TEAM_ID` | step 1.1 |
| `APP_STORE_CONNECT_KEY_ID` | step 2.2 |
| `APP_STORE_CONNECT_ISSUER_ID` | step 2.2 |
| `APP_STORE_CONNECT_API_KEY_P8` | step 2.2 — paste the whole file including the BEGIN/END lines |
| `REVENUECAT_APPLE_KEY` | step 4.1 |

### Variables tab (**New repository variable**)

| Name | Value |
|---|---|
| `APPLE_SERVICE_ID` | `com.bijbelstudie.app.signin` |
| `APPLE_REDIRECT_URI` | `https://www.bijbel-studie.com/api/v1/auth/apple/callback` |

---

## Part 6 — Vercel environment variables

Vercel dashboard → the `bijbelstudie` project → **Settings → Environment
Variables**. Add each to **Production**, **Preview** and **Development**
unless noted.

| Name | Value | Status |
|---|---|---|
| `MOBILE_JWT_SECRET` | 48+ random bytes. **Must not equal `NEXTAUTH_SECRET`.** Generate: `node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"` | already in your local `.env.local`; Vercel needs its own |
| `APPLE_CLIENT_IDS` | `com.bijbelstudie.app` | already local, needed on Vercel |
| `GOOGLE_MOBILE_CLIENT_IDS` | the iOS + Android + Web client IDs from Part 3, comma-separated, no spaces | **not set anywhere yet** |
| `REVENUECAT_WEBHOOK_AUTHORIZATION` | step 4.5 | **not set yet** |
| `REVENUECAT_REST_API_KEY` | step 4.6 | **not set yet** |
| `REVENUECAT_PRO_ENTITLEMENT_ID` | `pro` | optional, this is the default |
| `GEMINI_API_KEY` | already in `.env.local` | copy it to Vercel if it is not there — the app's AI-assistent tab returns 503 without it |
| `GOOGLE_TTS_API_KEY` | already in `.env.local` | copy to Vercel — the voorlezen button needs it |

After adding them, **redeploy**. Vercel does not apply new environment
variables to an existing deployment.

### Verify the backend before touching Xcode

```bash
# Should return 200 and a JSON body with accessToken + refreshToken
curl -s -X POST https://www.bijbel-studie.com/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","password":"yourpassword"}'

# Should return 451, not 404 — the licensing gate is doing its job
curl -s -o /dev/null -w '%{http_code}\n' \
  https://www.bijbel-studie.com/api/v1/bibles/nbg51/Genesis/1

# Should return 200 and a list of allowed translations
curl -s https://www.bijbel-studie.com/api/v1/bibles
```

If the first one returns 500, `MOBILE_JWT_SECRET` is missing or the redeploy
has not happened.

---

## Part 7 — First build

1. Repo → **Actions** tab → **iOS Release** workflow → **Run workflow**.
2. It is `workflow_dispatch` only; it never runs on push.
3. Expect 12–20 minutes.
4. If it fails, the failing step names the missing secret. The most common
   failures, in order of how often they happen:
   - `missing com.apple.developer.applesignin` → the provisioning profile was
     generated before the capability was enabled. Regenerate the profile
     (step 1.6) and update `BUILD_PROVISION_PROFILE_BASE64`.
   - `No signing certificate` → the `.p12` was exported without its private
     key. Export from **My Certificates**, not from **Certificates**.
   - `Authentication failed` on upload → wrong Issuer ID, or the API key has
     Developer rather than App Manager access.

When it goes green, the build appears in App Store Connect →
**TestFlight** after 5–15 minutes of processing.

> **iOS cannot be built or verified from Windows.** The pipeline is proven
> after the first green Actions run, not before.

---

## Part 8 — Content licensing

Three sources on the website may **not** ship in the app. The block is
server-side in `lib/mobileLicensing.ts`; every `/api/v1` content route answers
**451 Unavailable For Legal Reasons** for them regardless of how the request is
spelled.

| Source | Why | Who to ask |
|---|---|---|
| `nbg51` | NBG-vertaling 1951 licence covers `www.bijbel-studie.com` only. Your contract runs to 2029-12-31 and is website-scoped. | Nederlands-Vlaams Bijbelgenootschap — ask for an app addendum |
| `net` | NET Bible: whole-text electronic distribution needs written permission and "cannot be bundled with anything sold" | permissions@netbible.com |
| `kingcomments_nl` | © Stichting Titus / Uitgeverij Daniël; they ship their own App Store app | Stichting Titus / Uitgeverij Daniël |

Also blocked: `hsv`, `basisbijbel`, `schlachter`, `afri` — copyrighted or
uncleared.

Granting one is a one-line change to the relevant `Set` in
`lib/mobileLicensing.ts` plus its attribution in `lib/mobileAttribution.ts`.

Keep the written permissions on file. Apple asks for them under guideline 5.2
if anyone complains.

---

## Part 9 — Before you submit for review

- [ ] **Reviewer account.** Create a real account, enable Pro on it manually in
      MongoDB (`subscribed: true`), and add a few notes and highlights.
      Reviewers reject apps they cannot get past an empty state in.
- [ ] **App Review notes.** Paste this:
      > The Bible translations and commentaries in this app are public domain.
      > The original-language text is STEPBible (TAHOT/TAGNT), CC BY 4.0, and
      > the attribution is displayed in the Grondtekst tab. Subscriptions use
      > StoreKit via RevenueCat. Existing web subscribers retain access under
      > the multiplatform exception (guideline 3.1.1(b)). Account deletion is
      > at Profiel → Account verwijderen.
- [ ] **Privacy nutrition labels:** email address, name, user content
      (notes/highlights), identifiers, purchases. Linked to identity: yes.
      Used for tracking: no.
- [ ] **Screenshots.** 6.7" and 6.5" are mandatory. Take them in the simulator:
      `flutter run` on an iPhone 15 Pro Max, then ⌘S in the simulator.
- [ ] **Support URL:** `https://www.bijbel-studie.com/contact`
- [ ] **Privacy policy URL:** `https://www.bijbel-studie.com/privacy-policy`
- [ ] **Age rating:** 4+, no objectionable content. Answer "Infrequent/Mild"
      to nothing.
- [ ] **Rights dossier** on file for guideline 5.2.

---

## What I could not do and why

| Thing | Blocker |
|---|---|
| Build or run the iOS app | iOS builds require macOS; this machine is Windows |
| Anything in Apple Developer / App Store Connect | needs your Apple ID |
| Anything in RevenueCat | needs your account |
| Vercel environment variables | needs your Vercel login |
| The Google client IDs in `Info.plist` | the values come from your Google Cloud project |
| Licensing permission for NBG / NET / KingComments | only the rights holders can grant it |
