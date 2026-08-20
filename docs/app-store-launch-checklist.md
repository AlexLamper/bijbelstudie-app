# Going live — what is done, what is left

Written 2026-08-20, after the Stripe live cut-over. Build **1.0 (7)** is on
TestFlight and is the build to submit.

---

## Part 1 — Stripe live: done

All of it was applied against `acct_1QkiMOGkd9Br8GXY` and verified.

| Object | Live id |
|---|---|
| Annual price €89,99/yr | `price_1U6SmcGkd9Br8GXYiQJ0AnKI` |
| Monthly price €9,99/mo | `price_1R6ap2Gkd9Br8GXY20SfFyzw` (pre-existing) |
| Product | `prod_S0c3528EdTZI6H`, renamed "Scriptura Pro" → **BijbelStudie Pro** |
| Webhook endpoint | `we_1U6Sn6Gkd9Br8GXYRksSZHxW` → `/api/webhooks/stripe`, 8 events |
| Billing portal | `bpc_1U6SnNGkd9Br8GXY1pGZje90`, default, cancellation off |
| Archived | `prod_Sj4gjhgI70JHuA` ("Pro"), `prod_Sj4eBGluJmQ65Q` ("Basic") |

Both prices carry `tax_behavior: unspecified`, matching the live monthly price.
Mixing that with the test mode's `inclusive` would tax the two plans
differently.

Vercel production now has `STRIPE_ANNUAL_PRICE_ID`,
`NEXT_PUBLIC_STRIPE_ANNUAL_PRICE_ID`, `NEXT_PUBLIC_STRIPE_PRICE_ID`, a new
`STRIPE_WEBHOOK_SECRET`, and `STRIPE_REQUIRE_TOS_CONSENT=true`. Deployed.

Two things were proved rather than assumed:

* **The webhook secret is right.** A request signed with the new secret and
  posted to the live endpoint returned `200 {"received":true}`. A request with a
  bogus signature returns `400 Invalid signature`, and one with no signature
  header returns `400 Missing signature`.
* **The Stripe ToS URL is already set** in Dashboard → Settings → Public
  details. The only way to test that from outside the Dashboard is to create a
  live Checkout Session with `consent_collection[terms_of_service]=required` —
  Stripe rejects the whole session if the URL is missing. It was accepted, and
  the session was expired immediately. That is why turning the env var on was
  safe.

Only one live subscription has ever existed (`sub_1RQW5z…`, canceled, monthly),
so the rename and the two archivings touched nothing billable.

### Clean-up to do now

Delete `STRIPE_ADMIN_KEY` from `C:\Projects\bijbelstudie\.env.local` and revoke
the `claude-setup-temp` restricted key in the Stripe Dashboard. It was a
temporary admin credential and there is nothing left for it to do.

### One side effect worth knowing

`STRIPE_WEBHOOK_SECRET` had been scoped to Preview **and** Production. Replacing
it dropped Preview. No webhook endpoint has ever pointed at a preview URL, so
nothing broke; add it back if you ever wire one up.

---

## Part 2 — App Store Connect: the three errors on your screen

Three separate blocks at once. Clear them in this order — each one gates the
next.

### 2a. "You must add a subscription price"

Your own screen shows why, even though it looks like a price is set:

```
Availability        : All countries or regions selected
Subscription Prices : Countries or Regions (1)
                      Netherlands (EUR)  €9.99
```

The subscription is **available** in every territory but **priced** in exactly
one. App Store Connect will not accept a subscription that is on sale somewhere
it has no price, so it reports the price as missing rather than as incomplete.

Fix — Subscription Prices → **View all Subscription Pricing** → *Edit* / *Add
Price*:

1. Pick **Netherlands** as the base country and **€9,99** as its price.
2. Let App Store Connect generate the equivalents for every other territory —
   it offers this automatically once a base is chosen. Do not deselect any.
3. Confirm. The table should then read "Countries or Regions (175)" or similar,
   not (1).

The alternative, if you genuinely only want to sell in the Netherlands, is to
change **Availability** to Netherlands only. Do not leave the two mismatched.

Repeat for `bijbelstudie_pro_yearly`. Its price showed as "1 Year Upfront, all
countries", which is the correct shape, but verify the territory count the same
way.

### 2b. Review Information → Screenshot is empty

Your screen shows `Screenshot? No file chosen`. This is mandatory for every
auto-renewable subscription. Upload this file to **both** subscriptions:

```
C:\Projects\bijbelstudie-app\screenshots\iap-review\paywall-1284x2778.png
```

1284×2778, RGB with no alpha channel (Apple rejects alpha). One file serves both
products.

Once 2a and 2b are done, each subscription's status flips from **Prepare for
Submission** to **Ready to Submit**. That flip is the signal that the metadata
is complete — do not move on before you see it.

### 2c. "Your first auto-renewable subscription must be submitted with a new app version"

Not an error to fix — a sequencing rule. Apple will not review a brand-new
subscription group on its own; it has to ride along with a build.

Once both subscriptions read *Ready to Submit*:

1. App Store Connect → Apps → BijbelStudie App → left sidebar, the **iOS App
   1.0** version page. It is editable again after the 1.0 (5) rejection.
2. Scroll to **In-App Purchases and Subscriptions** and click **+** / *Add*.
3. Select **both** `bijbelstudie_pro_monthly` and `bijbelstudie_pro_yearly`.
4. Under **Build**, select **1.0 (7)** — the 19 August build, which carries the
   crash fix, the BijbelStudie branding and the annual-first paywall. Build 5 is
   the one that was rejected; do not resubmit it.
5. Submit the version. The subscriptions go to review with it.

If the 1.0 version page is not editable (status "Developer Rejected" or "Removed
from Sale"), create version **1.0.1** instead and attach build 7 to that.
Nothing in the app needs rebuilding either way.

### 2d. RevenueCat "Missing Metadata"

It clears by itself once App Store Connect reaches *Ready to Submit* — it is
RevenueCat reporting what it read from Apple, not a RevenueCat problem. If it
has not cleared an hour later, check RevenueCat → Project Settings → Apple App
Store: the **In-App Purchase key** must be uploaded there, because that is what
RevenueCat uses to read product metadata.

Until it clears, StoreKit returns zero products and `premium_screen.dart` falls
back to `'—'` for both prices. A reviewer opening the paywall would see dashes
instead of prices — a fresh 3.1.2 rejection. So: App Store Connect first, then
the sandbox purchase, then submit.

### On the in-app price

`APP_STORE_MONETISATION.md` recommends **€10,99 / month** and **€99,99 / year**
in-app, against €9,99 / €89,99 on the web, so Apple's 15% commission comes out
of the price rather than out of your margin. App Store Connect currently has
€9,99. Charging more in-app is explicitly allowed; what is forbidden is telling
users inside the app that the web is cheaper. Your call — but if you want to
change it, do it now, before the price is locked into a submission.

Also apply for the **Small Business Program** if you have not: 15% instead of
30%, and this app qualifies by default.

---

## Part 3 — Store-readiness audit

### Verified working

| Area | Check | Result |
|---|---|---|
| Web | `/succes`, `/geannuleerd`, `/privacybeleid`, `/algemene-voorwaarden`, `/inloggen`, `/registreren`, `/abonnement` | all 200 |
| Web | Auth-gated routes (`/dashboard`, `/profiel`, `/studies`, `/instellingen`) | 307 → `/` when logged out, as designed |
| Mobile API | `POST /api/v1/auth/login` with bad credentials | `401 INVALID_CREDENTIALS` |
| Mobile API | `POST /api/v1/auth/register` with no body | `400 MISSING_FIELDS` |
| Mobile API | `GET /api/v1/me` with no token | `401 UNAUTHORIZED` |
| Mobile API | `GET /api/v1/bibles` unauthenticated | `200` — public content, intended |
| Mobile API | `POST /api/v1/auth/apple` and `/google` | `400 MISSING_FIELDS` — both routes live |
| Payments | RevenueCat webhook with no auth header | `401` — a missing secret would answer `500` |
| Payments | Stripe webhook: signed / bad signature / no header | `200` / `400` / `400` |
| Review account | `applereview@mail.com` in database `scriptura` | exists, `subscribed: true` |
| Paywall | name, duration, real price per period, restore button, EULA, privacy link, auto-renewal text | all present in `premium_screen.dart` |
| Paywall | no Stripe link, no "cheaper on the web" — guideline 3.1.1 | clean |
| Account deletion | `Profiel → Account verwijderen` → `DELETE /api/v1/account` | present — guideline 5.1.1(v) satisfied |
| Icon | `Icon-App-1024x1024@1x.png` | 1024×1024, RGB, no alpha |
| Build | `flutter analyze` | No issues found |
| Build | `flutter test` | 42/42 passed |
| Export compliance | `ITSAppUsesNonExemptEncryption` in Info.plist | `false` — no per-build prompt |

### Legal links on the auth screens

The login and register screens carry **"Meer over gegevensgebruik"**, which
opens a dialog linking:

* `https://www.bijbel-studie.com/privacybeleid` — 200
* `https://www.bijbel-studie.com/algemene-voorwaarden` — 200

`docs/app-review-1.0.5-rejection.md` still names the old `/privacy-policy` and
`/terms-of-service` URLs. The doc is stale; the code is right.

The paywall separately links Apple's standard EULA
(`apple.com/legal/internet-services/itunes/dev/stdeula/`), which is deliberate:
it is the one Apple explicitly accepts and it already carries the auto-renewal
terms review looks for.

### Three things to decide on

**1. That dialog's account-deletion text is out of date, and it is the one
sentence a 5.1.1(v) reviewer would read.** It currently says:

> Je kunt altijd je account laten verwijderen. Neem hiervoor contact op via
> info@bijbel-studie.com of via de supportkanalen in de app.

In-app deletion *does* exist, in `Profiel → Account verwijderen`. Pointing at
email instead reads like there is no in-app path. Worth changing to name the
screen. `lib/features/auth/present/widgets/user_data_info_link.dart:39`. This
needs a new build, so decide before submitting, not after.

**2. iOS has no social login at all.** `login_screen.dart` sets
`showGoogleSignIn = !isIOSApp`, and `buildAppleSignInButton` /
`signInWithApple()` exist but are never called from any screen. This is *not* a
4.8 violation — Sign in with Apple is only required when you offer another
third-party login, and on iOS you offer none. But it means iOS users have
email/password only, while the Apple entitlement, the Services ID, the
`/api/v1/auth/apple` route and the CI check for that entitlement are all in
place and unused. Either wire the button up or drop the dead code; leaving it
half-connected is how it gets shipped broken later.

**3. No app-level `PrivacyInfo.xcprivacy`.** The Flutter engine and the plugins
ship their own, and builds 2–7 uploaded without an ITMS-91053 warning, so this
is not blocking. Add one if Apple ever emails about required-reason APIs.

### Still only verifiable on a device

A real sandbox purchase and restore. Once the subscriptions are *Ready to
Submit*, on TestFlight build 7:

1. Fresh install, register a new account → lands on the dashboard. This is the
   exact step that failed review 1.0 (5).
2. Paywall shows annual first, selected by default, with real prices — not `—`.
3. Buy annual → entitlement `pro` active → `/api/v1/me` reports `isPro`.
4. Delete and reinstall → **Aankopen herstellen** restores Pro.
5. Sign in as `applereview@mail.com`, force-quit, reopen → Pro still active on
   the second launch.

### Before hitting Submit

- [ ] Both subscriptions read **Ready to Submit**
- [ ] Build **1.0 (7)** selected on the version
- [ ] Both subscriptions attached to the version
- [ ] 13" iPad screenshots uploaded from `screenshots/13-ipad/` — the app ships
      universal and the last reviewer used an iPad Air M3
- [ ] App Review Information names `applereview@mail.com` and a password that
      actually works. Verify by signing in yourself.
- [ ] Reply to the open App Review message naming the crash fix and the demo
      account, so the same reviewer knows what changed
- [ ] `STRIPE_ADMIN_KEY` deleted from `.env.local` and the key revoked
