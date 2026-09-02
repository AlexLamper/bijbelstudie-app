# Paywall shows no prices — what to check

The app side is exhausted: it asks the current RevenueCat offering, falls back to
a direct store lookup of the two product ids, matches packages by id then type
then billing period, retries on demand, and keeps prices that were fetched even
if a later call in the same load fails. If the paywall still shows `-`, the
answer is in one of the five places below.

**Read the diagnosis first.** On the paywall, the red "Prijzen niet beschikbaar"
card has a **Details** expander and a **Kopieer diagnose** button. That block
names the key source, whether the SDK is configured, the offering it found and
how many packages were in it, the product ids requested, how many came back, and
the raw error. Every item below says which line of that block points at it.

---

## 1. You are testing somewhere that has no store

*Diagnose says: `sleutel: none:apple` — or configured `false`.*

- The **iOS Simulator** returns no products at all unless the StoreKit
  configuration file is active. `ios/Runner/BijbelStudie.storekit` now exists and
  the Debug scheme points at it, so a simulator run should show €9,99 / €69,99.
- A **local `flutter run` has no RevenueCat key** — the key only arrives through
  a `--dart-define`, and without it the SDK never contacts the store:

  ```
  flutter run --dart-define=REVENUECAT_APPLE_KEY=appl_xxxxx
  ```

- A **TestFlight build has the key** (CI passes the `REVENUECAT_APPLE_KEY`
  secret, which is set). If prices work in TestFlight but not locally, this was
  the whole problem.

## 2. Paid Applications Agreement is not active

*Diagnose says: 0 products returned, 0 packages, no error.*

This is the most common cause of "approved products that return nothing". In
**App Store Connect → Business**, the Paid Applications Agreement must show
**Active**, with banking and tax details complete. While it is pending, StoreKit
returns an empty product list for every request and reports no error — which
looks exactly like a code bug and is not one.

## 3. Product ids do not match

*Diagnose says: products requested `bijbelstudie_pro_yearly, bijbelstudie_pro_monthly`, 0 returned.*

The app asks for exactly:

- `bijbelstudie_pro_monthly`
- `bijbelstudie_pro_yearly`

In **App Store Connect → Subscriptions**, the Product ID column must match those
two strings character for character — no prefix, no capital letters, no trailing
whitespace. If yours differ, either rename them there or change the two constants
at the top of `bijbelstudie_mobile/lib/features/premium/data/purchase_service.dart`.

## 4. RevenueCat is pointed at a different app

*Diagnose says: configured `true`, but 0 offerings and 0 packages.*

In the **RevenueCat dashboard → Project settings → Apps**:

- The iOS app's **bundle id** must be `com.bijbel-studie.app`.
- The **App Store Connect shared secret** must be filled in, or RevenueCat
  cannot validate anything against your account.
- The key in the `REVENUECAT_APPLE_KEY` secret must be the **public SDK key**
  for that same project (starts `appl_`), not a secret `sk_` key.

## 5. The offering is not marked "current"

*Diagnose says: offering `(geen)` with N offerings available, or an offering with 0 packages.*

In **RevenueCat → Offerings**, one offering must be flagged **Current**, and it
needs both packages attached — normally `$rc_monthly` and `$rc_annual`, pointing
at the two products from step 3.

This one is the least urgent: the app falls back to a direct product lookup, so a
broken offering costs the packaging, not the prices. If the diagnose shows
packages but still no match, the app now also matches on package type and billing
period, so a custom package name is no longer fatal.

---

## Newly approved subscriptions

Apple's approval can take a few hours to propagate to StoreKit. If everything
above is right and the products were approved very recently, wait and retry with
the button on the card before digging further.

## If none of it fits

Press **Kopieer diagnose** on the paywall and send the block. It contains the key
source, configuration state, offering id, package count, requested ids, returned
count and raw error — enough to tell which of the five above it is without
guessing.
