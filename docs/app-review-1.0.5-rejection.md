# App review 1.0 (5) — rejection and fixes

Submission ID `9f2a3714-a953-4996-bb07-60b0471dfeac`, reviewed 14 August 2026 on
iPad Air 11-inch (M3) / iPadOS 26.6 and iPhone 17 Pro Max. Two guidelines cited,
plus a third problem the reviewer photographed but did not name.

---

## 2.1(a) Performance — App Completeness

> after we registered an new account, the app displayed only an error page and
> was further unresponsive

Reproducible on every device, not just iPad, and on the very first launch.

Four call sites navigated to `/home`. The router never declared that path — the
post-auth destination is `/dashboard`. go_router therefore rendered its default
error page (`GoException: no routes for location: /home`), whose only affordance
is a link to `/`. That is the splash screen, which checks for a session, finds
the one that was just created, and navigates to `/home` again. The loop is what
the reviewer described as unresponsive.

Fixed in `lib/features/auth/present/{splash,login,register}_screen.dart` and
`lib/features/onboarding/present/onboarding_screen.dart`.

Two guards so it cannot come back:

- `/home` is now a registered route that redirects to `/dashboard`, covering
  any link or route persisted by an older build.
- `errorBuilder` renders a real screen with a working button to `/dashboard`,
  so an unknown route can never dead-end again whatever causes it.

`test/router_links_test.dart` scans every `context.go`/`push`/`replace` literal
in `lib/` and asserts each one resolves against the real router. A route rename
is invisible to the compiler, so this is the only thing that catches the next
one. It currently checks 12 destinations.

## 2.1 Information Needed — demo account

> We were unable to sign in with the following demo account credentials

`applereview@mail.com` had never been created. Production returned
`401 INVALID_CREDENTIALS`.

The account now exists and authenticates. Recreate or repair it with:

```bash
cd C:/Projects/bijbelstudie
REVIEW_PASSWORD='...' node scripts/ensure-review-account.mjs         # report
REVIEW_PASSWORD='...' node scripts/ensure-review-account.mjs --write # apply
```

`REVIEW_PASSWORD` is whatever App Store Connect shows under **App Review
Information**. It is deliberately not stored in either repository — both are
public, and that password grants a Pro account on the production database.

Two things that script encodes, both of which are easy to get wrong by hand:

**The database is `scriptura`.** The `MONGODB_URI` in `.env.local` names
`Bijbelstudie`, a different, near-empty database on the same cluster. Writing
there succeeds, reports success, and changes nothing the deployed site can see.
The script pins the target rather than inheriting it from the URI.

**Pro is granted through `subscribed`, not `storePremium`.** The app calls
`POST /api/v1/sync-premium` on every launch, which asks RevenueCat for the truth
and overwrites `storePremium`. RevenueCat has never heard of this account, so a
`storePremium` grant is reset to false on the reviewer's *second* launch — Pro
on Monday, gone on Tuesday. `applyStorePremium` deliberately never touches
`subscribed`, so a grant made there survives. Verified by calling sync-premium
against the live account: it returns 200 and `isPro` stays true.

The reviewer therefore sees `proSource: "stripe"`, which puts the paywall in its
multiplatform-exception state (no purchase button, guideline 3.1.1(b)). The
purchase flow itself stays testable by registering a fresh free account.

## Not cited, but photographed: BijbelQuiz branding

The reviewer's second screenshot shows the login screen reading **BijbelQuiz**,
under a heading about a leaderboard. That is this binary, not another app — the
auth and onboarding flow was carried over from BijbelQuiz and never rewritten.

This would have failed 2.3.1 on its own once the crash was fixed, since it is
the first thing anyone sees:

| Where | Was |
|---|---|
| `splash_screen.dart` wordmark | `Bijbel` + `Quiz` |
| `splash_screen.dart` tagline | `TEST JOUW KENNIS VAN DE BIJBEL` |
| `login_screen.dart` | "mee te doen op de ranglijst" |
| `register_screen.dart` | "mee te doen op de ranglijst" |
| `onboarding_screen.dart` | three pages of quizzes, ranglijst, live multiplayer |
| `web/index.html`, `web/manifest.json` | "leuke quizzen en multiplayer" |

All rewritten for BijbelStudie: reading, commentaries and grondtekst, and
notes/plans synced with the website.

## Legal links on the auth screens

"Meer over gegevensgebruik" opened a dialog of static text and linked nothing.
It now links the hosted <https://www.bijbel-studie.com/privacy-policy> and
<https://www.bijbel-studie.com/terms-of-service> (both verified 200).

`AppConfig.termsOfServiceUrl` is new and separate from `termsOfUseUrl`: the
paywall keeps Apple's standard EULA, which already carries the auto-renewal
terms review looks for, while the Dutch signup screen links Dutch terms.

---

## Payments — verified, no changes needed

The RevenueCat to MongoDB chain was audited end to end and is correct and
configured in production. Probed live:

| Check | Result | Means |
|---|---|---|
| `POST /api/mobile/revenuecat-webhook`, no auth header | `401` | `REVENUECAT_WEBHOOK_AUTHORIZATION` is set. An unset one answers `500`. |
| `POST /api/v1/sync-premium`, authenticated | `200` | `REVENUECAT_REST_API_KEY` is set and the RevenueCat REST call succeeded. Unset answers `500`, a failed call `502`. |

The webhook is authenticated, idempotent through `WebhookEvent`, and deletes its
own ledger row on failure so RevenueCat's retry is not swallowed as a duplicate.
`resolveIsPro` ORs Stripe and store entitlements. `applyStorePremium` rejects an
`app_user_id` that is not a Mongo ObjectId, which is the failure mode worth
guarding: the whole chain rests on `Purchases.logIn(user.id)` passing the Mongo
`_id`.

None of the `REVENUECAT_*` keys were documented in `.env.example`. They are now,
with what breaks when each is missing — a fresh deploy would otherwise lose
purchases silently.

**Still unverified, and only verifiable on a device:** an actual sandbox
purchase and restore. Do that on TestFlight before resubmitting.

---

## Before resubmitting

- [ ] Rebuild and upload a new build — icons, copy and routing are all compiled
      in, so nothing here reaches Apple without one.
- [ ] Register a brand new account on the build and confirm it lands on the
      dashboard. This is the exact step that failed.
- [ ] Sign in as `applereview@mail.com`, force-quit, reopen. Confirm Pro is
      still active on the second launch.
- [ ] Run one sandbox purchase and one "Herstel aankopen" on TestFlight.
- [ ] Confirm the App Store Connect demo credentials still name
      `applereview@mail.com`, and that its password is the one you passed to
      `REVIEW_PASSWORD` above.
- [ ] Upload the 13" iPad screenshots from `screenshots/13-ipad/`. The app ships
      universal, and the reviewer used an iPad.
- [ ] Reply to the App Review message naming the crash and the demo account, so
      the same reviewer knows what changed.
