# iOS Release via GitHub Actions — Setup Guide

The workflow at `.github/workflows/ios-release.yml` builds the Flutter IPA on a
macOS GitHub runner and uploads it to TestFlight. It is copied verbatim from an
already-shipping pipeline; the only differences are the working directory
(`bijbelstudie_mobile`) and the IPA search path.

You need the following **one-time setup** before it works.

Bundle identifier for this app: **`com.bijbel-studie.app`**
(RunnerTests: `com.bijbel-studie.app.RunnerTests`)

---

## Step 1 — Register the App ID and enable Sign in with Apple

1. [Apple Developer portal](https://developer.apple.com) → **Identifiers** →
   register App ID `com.bijbel-studie.app`.
2. Enable the **Sign In with Apple** capability on it.

This is not optional. The workflow **hard-fails** if the provisioning profile
does not carry `com.apple.developer.applesignin`:

```
Provisioning profile is missing Sign in with Apple entitlement.
```

That check exists because the entitlement silently missing from the IPA produces
a runtime `AuthorizationError 1000` that is very hard to diagnose on a device.
Generate the profile **after** enabling the capability (Step 4), never before.

---

## Step 2 — Google Sign-In

Google issues a **different OAuth client per platform**, and the server pins the
ID token's `aud` claim (`lib/oauthVerify.ts` → `googleAudiences()`). A token
minted for the wrong client is a perfectly valid JWT and is rejected on purpose,
so every client id below has to be registered in both places or sign-in fails
with `INVALID_TOKEN`.

### 2a. Create the iOS OAuth client

**Google Cloud Console → APIs & Services → Credentials → Create credentials →
OAuth client ID**, type **iOS**, bundle ID `com.bijbel-studie.app`. Use the same
project as the existing web client. Neither value it gives you is a secret — an
iOS OAuth client is public by design and is bound to the bundle ID.

You get two forms of the same id:

| | Example |
|---|---|
| Client ID | `123456789012-abcdefg.apps.googleusercontent.com` |
| Reversed client ID | `com.googleusercontent.apps.123456789012-abcdefg` |

### 2b. Tell the server to accept it

Add the iOS client id to **`GOOGLE_MOBILE_CLIENT_IDS`** on Vercel
(Production + Preview + Development), comma-separated alongside the web client
id, then redeploy:

```
GOOGLE_MOBILE_CLIENT_IDS=<web client id>,<ios client id>
```

Without this the app gets a token Google is happy with and the server answers
401 `INVALID_TOKEN`.

### 2c. Tell the build about it

Set two **repository variables** (Settings → Secrets and variables → Actions →
Variables — not secrets; these are public ids):

| Variable | Value |
|---|---|
| `GOOGLE_IOS_CLIENT_ID` | the iOS client ID from 2a |
| `GOOGLE_WEB_CLIENT_ID` | the existing web client ID (used by Android and web) |

`ios-release.yml` passes both as `--dart-define` and rewrites the two
`Info.plist` placeholders (`GIDClientID`, `CFBundleURLSchemes`) with PlistBuddy
before building. For a local build, do the same by hand:

```
flutter build ios --release   --dart-define=GOOGLE_IOS_CLIENT_ID=<ios client id>   --dart-define=GOOGLE_WEB_CLIENT_ID=<web client id>
```

### What happens if you skip this

Nothing breaks. `GoogleSignInConfig.isAvailable` is false without a client id
for the platform, so the Google button simply does not render and the screens
look exactly as they did before — Sign in with Apple plus email/password, which
already satisfies guideline 4.8 on its own.

### Account linking

Already handled server-side, in both directions and with no extra work:
`app/api/v1/auth/google/route.ts` looks up `googleId` first, then falls back to
a **case-insensitive email match** and links `googleId` onto the account it
finds. So signing into the app with Google lands on the *same* account as the
website, and a password account whose address matches gains Google as a second
way in rather than a second account. `/auth/apple` does the same with `appleId`.

Linking by email is safe here only because Google asserts the address in a
signed token — never do it from a client-supplied email.

---

## Step 3 — Create an App Store Connect API key

1. Log in to [App Store Connect](https://appstoreconnect.apple.com).
2. **Users and Access → Integrations → App Store Connect API → Team Keys**.
3. **Generate API Key**, name it `GitHub Actions`, role **App Manager**.
4. Download the `.p8` private key — it is downloadable exactly once.
5. Note the **Key ID** and the **Issuer ID** on that page.

---

## Step 4 — Export the Distribution certificate and provisioning profile

On a Mac signed into your Apple Developer account:

1. **Keychain Access** → find your **Apple Distribution** certificate.
2. Right-click → **Export** → `distribution.p12`, with a strong password.
3. Base64 it: `base64 -i distribution.p12 | pbcopy`
4. Developer portal → **Profiles** → new **App Store** distribution profile for
   `com.bijbel-studie.app`. Regenerate it *after* Step 1, or the entitlement
   check in the workflow fails by design.
5. Download the `.mobileprovision` and base64 it:
   `base64 -i BijbelStudie_AppStore.mobileprovision | pbcopy`

---

## Step 5 — Add GitHub Secrets and Variables

GitHub repository → **Settings → Secrets and variables → Actions**.

### Secrets

| Secret name | Value |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | base64 of `distribution.p12` |
| `P12_PASSWORD` | password chosen when exporting the .p12 |
| `BUILD_PROVISION_PROFILE_BASE64` | base64 of the `.mobileprovision` |
| `KEYCHAIN_PASSWORD` | any random string; used only for the temp CI keychain |
| `APPLE_TEAM_ID` | 10-character Apple Developer Team ID |
| `APP_STORE_CONNECT_KEY_ID` | Key ID from Step 3 |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from Step 3 |
| `APP_STORE_CONNECT_API_KEY_P8` | base64 of the `.p8`: `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `REVENUECAT_APPLE_KEY` | RevenueCat **public** iOS SDK key (`appl_...`) |

### Variables

| Variable name | Value |
|---|---|
| `APPLE_SERVICE_ID` | `com.bijbel-studie.app.signin` |
| `APPLE_REDIRECT_URI` | `https://www.bijbelstudie.io/api/v1/auth/apple/callback` |

The build step fails fast with a named message if any of these is missing, so a
misconfigured secret costs you one minute rather than a failed upload.

There is **no RevenueCat key hardcoded in the app**. `revenuecat_config.dart`
defaults both platform keys to the empty string; the only way one enters the
binary is `--dart-define`, which the workflow supplies from the secret above.

---

## Step 6 — Backend environment (Vercel)

The app talks to `https://www.bijbelstudie.io/api/v1`. That surface needs:

| Env var | Purpose |
|---|---|
| `MOBILE_JWT_SECRET` | signs mobile access tokens. **Must differ from `NEXTAUTH_SECRET`** — a leaked mobile secret must not forge website sessions |
| `APPLE_CLIENT_IDS` | `com.bijbel-studie.app` (comma-separated if you add the Services ID) |
| `GOOGLE_MOBILE_CLIENT_IDS` | iOS + Android + web OAuth client IDs, comma-separated |
| `REVENUECAT_WEBHOOK_AUTHORIZATION` | exact value set in the RevenueCat webhook config |
| `REVENUECAT_REST_API_KEY` | `sk_...`, required by `/api/v1/sync-premium` |
| `REVENUECAT_PRO_ENTITLEMENT_ID` | optional; defaults to `pro` |

---

## How it runs

- **Manual only**: GitHub → Actions → "iOS Build & Upload to TestFlight" →
  **Run workflow**. The push trigger is commented out on purpose.
- Optional inputs: `build_name` (defaults to the version in `pubspec.yaml`) and
  `build_number` (defaults to the GitHub run number, so it auto-increments).

After a successful run the build appears in **App Store Connect → TestFlight**
(processing takes 5–15 minutes).

### If the upload "succeeds" but nothing appears

`xcrun altool` exits 0 on some rejections. The workflow greps its output and
fails explicitly:

```
::error::TestFlight upload failed. Common cause: the version string is already
approved/closed — bump the version (e.g. 1.0.2 → 1.0.3).
```

That grep is the only thing catching a duplicate version string. Do not remove it.

---

## What cannot be verified from Windows

Nothing in this pipeline can be exercised on a Windows machine: `xcodebuild`,
`codesign`, `security` and `altool` are macOS-only. The pipeline is proven after
the first green Actions run, not before.
