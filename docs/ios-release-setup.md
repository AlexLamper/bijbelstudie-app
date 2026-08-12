# iOS Release via GitHub Actions — Setup Guide

The workflow at `.github/workflows/ios-release.yml` builds the Flutter IPA on a
macOS GitHub runner and uploads it to TestFlight. It is copied verbatim from an
already-shipping pipeline; the only differences are the working directory
(`bijbelstudie_mobile`) and the IPA search path.

You need the following **one-time setup** before it works.

Bundle identifier for this app: **`com.bijbelstudie.app`**
(RunnerTests: `com.bijbelstudie.app.RunnerTests`)

---

## Step 1 — Register the App ID and enable Sign in with Apple

1. [Apple Developer portal](https://developer.apple.com) → **Identifiers** →
   register App ID `com.bijbelstudie.app`.
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

## Step 2 — Fill in the Google Sign-In placeholders

`bijbelstudie_mobile/ios/Runner/Info.plist` ships with placeholders so no other
app's OAuth client can leak into this binary:

| Key | Placeholder | Replace with |
|---|---|---|
| `CFBundleURLTypes` → `CFBundleURLSchemes` | `PUT_YOUR_REVERSED_CLIENT_ID_HERE` | reversed client ID, e.g. `com.googleusercontent.apps.1234-abcd` |
| `GIDClientID` | `PUT_YOUR_GID_CLIENT_ID_HERE` | iOS client ID, e.g. `1234-abcd.apps.googleusercontent.com` |

Get both from **Google Cloud Console → Credentials → OAuth client ID (iOS)**
created for `com.bijbelstudie.app`.

Android additionally needs a *web* client ID passed at build time:
`--dart-define=GOOGLE_WEB_CLIENT_ID=...`. iOS does not — it reads `GIDClientID`
from Info.plist — so the iOS workflow does not set it.

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
   `com.bijbelstudie.app`. Regenerate it *after* Step 1, or the entitlement
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
| `APPLE_SERVICE_ID` | `com.bijbelstudie.app.signin` |
| `APPLE_REDIRECT_URI` | `https://www.bijbel-studie.com/api/v1/auth/apple/callback` |

The build step fails fast with a named message if any of these is missing, so a
misconfigured secret costs you one minute rather than a failed upload.

There is **no RevenueCat key hardcoded in the app**. `revenuecat_config.dart`
defaults both platform keys to the empty string; the only way one enters the
binary is `--dart-define`, which the workflow supplies from the secret above.

---

## Step 6 — Backend environment (Vercel)

The app talks to `https://www.bijbel-studie.com/api/v1`. That surface needs:

| Env var | Purpose |
|---|---|
| `MOBILE_JWT_SECRET` | signs mobile access tokens. **Must differ from `NEXTAUTH_SECRET`** — a leaked mobile secret must not forge website sessions |
| `APPLE_CLIENT_IDS` | `com.bijbelstudie.app` (comma-separated if you add the Services ID) |
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
