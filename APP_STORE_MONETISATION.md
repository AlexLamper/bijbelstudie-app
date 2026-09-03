# App Store monetisation — setup and submission

Companion to `MONETISATION_SETUP.md` in the web repo. The app code for the
revenue work is done; these are the App Store Connect and RevenueCat steps that
cannot be done from the codebase.

---

## 1. The one rule that governs everything here

**Guideline 3.1.1 — In-App Purchase.** Digital content unlocked in the app must
be sold through StoreKit. The app may not link to, mention, or otherwise steer
users toward web checkout.

The revenue plan's "keep web checkout primary to avoid Apple's commission" is
**deliberately not implemented in the app.** On the Dutch storefront it is an
automatic rejection. `premium_screen.dart` has no Stripe link and no external
purchase URL, and the "already subscribed on the web" case only *states* that
access applies here — it gives no instructions to go and pay elsewhere, which is
what the multiplatform-service exception permits.

Do not add a "goedkoper op onze website" note anywhere in the binary.

---

## 2. Create the subscription products

App Store Connect → your app → Subscriptions → create one subscription group
(e.g. `BijbelStudie Pro`) containing:

| Product ID | Duration | Reference name |
|---|---|---|
| `bijbelstudie_pro_monthly` | 1 month | BijbelStudie Pro Maandelijks |
| `bijbelstudie_pro_yearly`  | 1 year  | BijbelStudie Pro Jaarlijks |

The product IDs must match `purchase_service.dart` exactly.

### Pricing — absorb the commission, do not eat it

Apple takes 15% (Small Business Program, ≤ $1M/yr — apply for this, it is the
default situation for this app) or 30%. The web prices are €9,99 / month and
€89,99 / year.

At 15% commission, to net the same as the web:

| Plan | Web price | Net on web (after Stripe ~2.9%) | App price to match net |
|---|---|---|---|
| Monthly | €9,99 | ~€9,40 | **€10,99** |
| Yearly | €89,99 | ~€86,90 | **€99,99** |

Recommended App Store tiers: **€10,99 / month** and **€99,99 / year**.

Charging more in-app than on the web is explicitly allowed — Apple only forbids
*telling users about the cheaper option inside the app*. Do not price the app
tier below the web tier; that is money given away to a channel that already
costs you 15%.

The paywall derives every figure — per week, saving, "% goedkoper" — from the
live `StoreProduct.price`, so setting these tiers is the only step needed. No
Dart change, and the per-week text is automatically correct in every storefront
and currency.

---

## 3. RevenueCat wiring

1. RevenueCat → Products: add both product IDs.
2. Offerings → create/confirm the **current** offering with two packages:
   - `$rc_monthly` → `bijbelstudie_pro_monthly`
   - `$rc_annual` → `bijbelstudie_pro_yearly`
3. Entitlements → create `pro` and attach both products.
   The identifier must be exactly `pro` (`kRcProEntitlement`).
4. App Store Connect → In-App Purchase key (or App-Specific Shared Secret) →
   paste into RevenueCat so receipt validation works.
5. Webhook → `https://www.bijbelstudie.io/api/mobile/revenuecat-webhook`,
   with the Authorization header value set to `REVENUECAT_WEBHOOK_AUTHORIZATION`
   from the web environment. That route already refuses to run if neither the
   auth header nor a signing secret is configured, so a missing value fails
   closed rather than handing out free Pro.

Build with the public SDK key:

```bash
flutter build ipa \
  --dart-define=REVENUECAT_APPLE_KEY=appl_xxx \
  --dart-define=USE_PRODUCTION_API=true
```

---

## 4. What App Review checks on the paywall

`premium_screen.dart` already satisfies these; re-verify after any redesign.

- [x] Subscription **name** — "BijbelStudie Pro", per plan tile.
- [x] **Duration** — "per jaar" / "per maand" in `billedLabel`.
- [x] **Price per period** — the real `priceString`, shown next to the derived
      per-week figure. The weekly figure alone would not satisfy this, which is
      why `billedLabel` is not optional in practice.
- [x] **Restore purchases** button, visible without purchasing.
- [x] **Privacy Policy** link — now `/privacybeleid` (was the old English route,
      which only resolved via a redirect; review checks these URLs load).
- [x] **Terms / EULA** link — Apple's standard EULA.
- [x] Auto-renewal disclosure text.

Also required **outside** the binary: the same Privacy Policy and EULA URLs in
the App Store Connect app listing metadata.

---

## 5. Demo account for review

Reviewers must reach the paywall and all gated content. Provide a demo account
in App Review notes. `scripts/` in the web repo has the review-account
provisioner (commit `360f4c4b`).

Add a note along the lines of:

> Pro content is gated. The reviewer account has Pro enabled. To test purchasing,
> sign out and register a new account; the paywall is reachable from Profiel →
> BijbelStudie Pro.

---

## 6. Sandbox test checklist

Use a Sandbox Apple ID (Settings → Developer → Sandbox Account).

1. Fresh install, register → paywall shows **annual first**, selected by default.
2. Prices render in the storefront currency, and "% goedkoper" plus
   "Je bespaart …" appear only when both products loaded. Switch the sandbox
   storefront to a non-euro country and confirm the per-week figure keeps that
   currency's symbol and decimal separator.
3. Buy annual → entitlement `pro` active → `/api/v1/me` reports `isPro` after
   `syncPremium` runs.
4. Delete and reinstall → **Aankopen herstellen** restores Pro.
5. Cancel in Sandbox → entitlement lapses → app returns to the paywall.
6. Confirm funnel rows land in the `analyticsevents` collection with
   `platform: "ios"`.

---

## 7. Analytics

The app posts to `POST /api/v1/analytics` with its normal bearer token. Events
share the allowlist in the web repo's `lib/analyticsSchema.ts` and every one
carries `platform`, so iOS and web funnels are comparable but never conflated —
which matters because the two have different prices and very different
conversion rates.

Nothing is sent while logged out; the endpoint requires a valid user, so there
is no anonymous write path from the app.
