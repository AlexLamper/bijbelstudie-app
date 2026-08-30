# The subscriptions are "Developer Rejected" — what that means and how to clear it

Written 2026-08-30, after both products stopped appearing in the app.

| | |
|---|---|
| Products | `bijbelstudie_pro_monthly` (€9,99/mnd), `bijbelstudie_pro_yearly` (€69,99/jr) |
| Subscription group | `Pro` |
| RevenueCat entitlement | `pro` |
| App Store Connect app id | `6800668187` |

---

## What the status means

**"Developer Rejected" is not an Apple decision. It is yours.** Apple's own
rejection state is called *Rejected* (with a reviewer note attached);
*Developer Rejected* means the product was pulled out of the review queue from
your side.

There are only two ways an in-app purchase reaches it:

1. Somebody opened the product in App Store Connect and chose **Remove from
   Review**.
2. **Far more likely here:** the products were attached to an app version, and
   that *version* was withdrawn or rejected by the developer. In-app purchases
   submitted alongside a binary inherit the binary's fate — cancel the version
   and every IAP riding with it drops to Developer Rejected in the same move.

Given the history in `docs/app-review-1.0.1-rejection.md` and
`docs/app-review-1.0.5-rejection.md` — several submissions pulled and
resubmitted — reason 2 is almost certainly what happened, and it happened as a
side effect rather than as a decision anybody made about the subscriptions.

## Why this stops the app selling anything

An in-app purchase is only returned by StoreKit once it is **Approved** (or
while it is *Waiting for Review* / *In Review*, for a build installed through
TestFlight or a sandbox account). In Developer Rejected it is returned to
nobody.

So the chain fails at its very first link:

```
StoreKit returns no products
  → Purchases.getOfferings() has no packages
  → the direct getProducts([...]) fallback also comes back empty
  → PriceStatus.unavailable
  → the paywall shows "-" and "De App Store gaf geen abonnementen terug."
```

That message is the app correctly reporting an App Store Connect state. There
is no app-side change that can make an unapproved product purchasable, which is
why nothing in this repo needed fixing for it.

## What was checked on this side (2026-08-30)

Everything downstream of Apple's approval is wired and verified live, so the
moment the products go Approved the flow works end to end:

| Link | State |
|---|---|
| Product ids in `purchase_service.dart` | match App Store Connect exactly |
| Entitlement id `pro` | matches on client and server |
| Offering → package lookup, with a direct product-id fallback | present |
| `POST /api/v1/sync-premium` on production | **HTTP 200** — so `REVENUECAT_REST_API_KEY` is set and reconciliation runs |
| `GET /api/v1/me` | returns `isPro`, `proSource`, `proExpiresAt` |
| RevenueCat webhook | authenticated (`REVENUECAT_WEBHOOK_AUTHORIZATION`) and idempotent on `event.id` |
| Restore purchases | exposed on the paywall (App Store requires it) |
| Web (Stripe) subscribers | `isProFromWeb` shows "Actief via web" and **no** purchase button — guideline 3.1.1(b) |
| Post-purchase | `_syncServerPremium` retries 5× / 2s, invalidates `profileProvider`, paywall flips to `_ActiveCard` |

The one thing still outstanding on this side is `REVENUECAT_APPLE_KEY` — see
Step 1 of `handoff-manual-steps.md`. Without it the build has no store
configuration at all and the paywall says so explicitly.

## How to clear it — do this in App Store Connect

The subscriptions cannot be resubmitted from this repo or from any API key held
here. All of it is manual.

1. **App Store Connect → BijbelStudie App → Subscriptions → Pro.**
2. Open `bijbelstudie_pro_monthly`. Confirm every one of these is filled, or it
   silently falls back to *Missing Metadata* instead of entering review:
   - **Subscription duration** and **price** (€9,99 / month, all 175
     territories)
   - **Localisation** (Dutch): display name + description
   - **Review information → screenshot.** A simulator shot of the paywall is
     accepted. This is the field most often left empty.
   - **Review notes** (optional but helps)
3. Repeat for `bijbelstudie_pro_yearly` (€69,99 / year).
4. Each product's status should now read **Ready to Submit**.
5. **Check the Paid Applications Agreement.** *Business → Agreements, Tax, and
   Banking* — it must be **Active**, with banking and tax details complete. A
   pending agreement keeps products unpurchasable no matter what review says.
6. **Submit them with the next app version.** This is the part that catches
   people out: **an app's first-ever subscription cannot be submitted on its
   own.** It has to be attached to an app version submission. On the version
   page, under **In-App Purchases and Subscriptions**, tick both products, then
   submit the version.
   - Once one subscription has been approved, later ones *can* go on their own.
7. **Do not withdraw that version.** If the binary is pulled again for any
   reason, both products fall straight back to Developer Rejected and you
   repeat all of the above.

Expect ~24h. While they sit in *Waiting for Review* they already return prices
to TestFlight and sandbox builds, so the paywall can be tested before approval
lands.

## How to confirm it worked

- App Store Connect shows both products **Approved**.
- RevenueCat → *Product catalog → Products* shows both, with prices, and the
  `default` offering is marked **Current** with `$rc_monthly` / `$rc_annual`
  attached.
- In the app, the paywall shows real prices instead of `-`. The debug build
  logs `[RevenueCat][PurchaseService] Package=… price=…` for each one.
- A sandbox purchase flips `GET /api/v1/me` to `isPro: true` with
  `proSource: "apple"`.
