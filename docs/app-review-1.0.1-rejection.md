# App review 1.0.1 (11) - rejection and fix

Submission ID `TODO(submission id from the App Review message)`, reviewed
August 2026. One guideline cited.

---

## 3.1.2 Business - Subscriptions (Schedule 2)

> The submission offers auto-renewable subscriptions but does not include a
> functional link to the Terms of Use (EULA) in the app metadata that appears on
> the app's App Store product page.
>
> If you are using the standard Apple Terms of Use (EULA), include a link to the
> Terms of Use in the App Description. If you are using a custom EULA, add it in
> App Store Connect.

### This is a metadata rejection, not a paywall rejection

Read the citation literally: it is about **the app metadata that appears on the
app's App Store product page**, not about the binary. The paywall was audited
again and is complete. Nothing in `lib/` caused this and nothing in `lib/` was
changed to fix it.

| Paywall requirement | Where | State |
|---|---|---|
| Subscription name | `premium_screen.dart` app bar plus per-plan tiles | present |
| Duration | `billedLabel`, "per jaar" / "per maand" | present |
| Price per period | live `StoreProduct.priceString` | present |
| Restore purchases | `SiteOutlineButton('Aankopen herstellen')` | present |
| Auto-renewal disclosure | `premium_screen.dart:166-171` | present |
| EULA link | `premium_screen.dart:176-179`, `AppConfig.termsOfUseUrl` | present, 200 |
| Privacy link | `premium_screen.dart:180-183`, `AppConfig.privacyPolicyUrl` | present, 200 |

`profile_screen.dart:104-112` carries the same two links a second time, outside
the purchase flow.

### Which of Apple's two remedies applies

The app uses **Apple's standard EULA**, not a custom one.
`AppConfig.termsOfUseUrl` defaults to
`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`, and
`app_config.dart:34-41` says so deliberately: it is the agreement Apple itself
accepts and it already carries the auto-renewal terms review checks for.

So the first branch of the citation is the one that applies:

> If you are using the standard Apple Terms of Use (EULA), include a link to the
> Terms of Use in the App Description.

**Do not** paste anything into App Store Connect's custom-EULA field. Doing so
would replace the standard EULA with a custom agreement, which is a different
and larger commitment than the one this app makes, and it would then also need
its own hosted, localised text.

The whole fix is the **App Description** field on the iOS App version page.

### Why the links were checked before writing them down

"Functional link" is the thing under test, and a dead URL in the description
earns the same rejection again. All three were probed:

| URL | Result |
|---|---|
| `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/` | 200, "Licensed Application End User License Agreement" |
| `https://www.bijbel-studie.com/privacybeleid` | 200, real route at `app/privacybeleid/page.tsx` |
| `https://www.bijbel-studie.com/algemene-voorwaarden` | 200, real route at `app/algemene-voorwaarden/page.tsx` |

The old English paths `/privacy-policy` and `/terms-of-service` also answer 200,
but only through the 308s in `next.config.ts`. The description names the Dutch
paths so the reviewer's click never depends on a redirect surviving.

### The price and duration go in too

Schedule 2 asks for the subscription name, length and price on the product page
as well, and a reviewer clearing a 3.1.2 rejection checks the whole clause in one
pass. The description below states both plans explicitly.

Prices are the ones this repo records as configured in App Store Connect:
`handoff-manual-steps.md` line 28, corroborated by `screenshots/README.md` and
the fixtures in `test/screenshots_test.dart`.

| Product ID | Reference name | Duration | Price |
|---|---|---|---|
| `bijbelstudie_pro_monthly` | BijbelStudie Pro Maandelijks | 1 maand | EUR 9,99 |
| `bijbelstudie_pro_yearly` | BijbelStudie Pro Jaarlijks | 1 jaar | EUR 69,99 |

> `APP_STORE_MONETISATION.md` still *recommends* EUR 10,99 / EUR 99,99, and
> `app-store-launch-checklist.md` leaves that as an open decision. It was never
> applied. **Re-read the two prices in App Store Connect before pasting the
> description.** A description that names a price the store does not charge is
> itself a 3.1.2 problem, and it is the one detail here that a human has to
> confirm rather than trust the repo for.

There is no introductory offer and no free trial on either product, so the
description deliberately omits the "ongebruikt deel van een gratis periode"
sentence from Apple's boilerplate. Add it only if a trial is ever configured.

---

## The App Description to paste

Dutch, plain text, no markdown. App Store Connect allows 4000 characters; this
is about 2500. Paste it into **App Store Connect - Apps - BijbelStudie App - the
iOS App version - Description**, replacing whatever is there.

```text
BijbelStudie is een Nederlandse app om de Bijbel te lezen en er echt in te duiken. Lees hoofdstuk voor hoofdstuk, pak het commentaar erbij, bekijk de grondtekst en bewaar je eigen notities.

LEZEN
- De Statenvertaling en de King James Version, hoofdstuk voor hoofdstuk.
- Stel lettertype, lettergrootte en regelafstand in zoals jij prettig leest.
- De app onthoudt waar je gebleven was en pakt de draad daar weer op.
- Zet een dagelijkse herinnering aan om te blijven lezen.

VERDIEPEN
- Bijbelcommentaren van Matthew Henry en Dachsel bij elk hoofdstuk.
- De grondtekst in het Hebreeuws en Grieks, met transliteratie en Strong-nummers.
- Begeleide studies die je stap voor stap door een thema of bijbelboek leiden.
- Een AI-assistent voor je vragen bij het hoofdstuk dat je leest.

BEWAREN
- Markeer verzen, schrijf notities en sla bladwijzers op.
- Alles synchroniseert met je account op www.bijbel-studie.com, dus je leest verder op je telefoon en op je laptop.

GRATIS BEGINNEN
Lezen, zoeken en notities maken kan zonder abonnement. BijbelStudie Pro is optioneel.

BIJBELSTUDIE PRO
Met BijbelStudie Pro krijg je:
- Hele bijbelboeken offline opslaan en lezen zonder verbinding.
- Alle commentaren bij elk hoofdstuk.
- De volledige grondtekst met transliteratie en Strong-nummers.
- Onbeperkt notities, markeringen en bladwijzers.

ABONNEMENTEN
- BijbelStudie Pro Maandelijks: abonnement van 1 maand, EUR 9,99 per maand.
- BijbelStudie Pro Jaarlijks: abonnement van 1 jaar, EUR 69,99 per jaar.

De betaling wordt bij bevestiging van de aankoop van je Apple ID afgeschreven. Het abonnement wordt automatisch verlengd tegen hetzelfde bedrag, tenzij je het minstens 24 uur voor het einde van de lopende periode opzegt. Je account wordt binnen 24 uur voor het einde van de lopende periode belast voor de verlenging. Je abonnement beheren of opzeggen doe je na aankoop in de instellingen van je Apple ID.

GEBRUIKSVOORWAARDEN EN PRIVACY
Gebruiksvoorwaarden (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacybeleid: https://www.bijbel-studie.com/privacybeleid
Algemene voorwaarden: https://www.bijbel-studie.com/algemene-voorwaarden

VRAGEN
Mail info@bijbel-studie.com of kijk op https://www.bijbel-studie.com/contact

De bijbelvertalingen en commentaren in deze app zijn publiek domein. De grondtekst komt van STEPBible (TAHOT/TAGNT) en is beschikbaar onder CC BY 4.0.
```

Three things about that block that are not cosmetic:

- **The URLs are written out in full, in plain text.** App Store Connect
  linkifies bare URLs in the description; a phrase like "zie onze website" does
  not satisfy "functional link" and is what the reviewer was looking for.
- **"Gebruiksvoorwaarden (EULA)" is the Apple URL**, matching what the paywall
  and the profile screen link. The Dutch algemene voorwaarden are listed
  separately because they are the product's own terms, not the EULA. Naming both
  without labelling them would invite the reviewer to guess which is the EULA.
- **The subscription block names product, length and price for both plans**, in
  that order, which is what Schedule 2 asks for.

---

## Also set, once, in App Store Connect

Both live outside the version page and are easy to miss:

- **App Information - License Agreement** must stay on Apple's **standard**
  EULA. If a custom agreement was ever pasted there, remove it; the app makes no
  custom licence commitment and there is no Dutch custom EULA to point at.
- **App Privacy - Privacy Policy URL** must be
  `https://www.bijbel-studie.com/privacybeleid`. `handoff-manual-steps.md` still
  told you to enter the old `/privacy-policy`, which only resolves through a
  redirect. Fixed there.

---

## Before resubmitting

- [ ] Confirm the live prices of `bijbelstudie_pro_monthly` and
      `bijbelstudie_pro_yearly` in App Store Connect, and correct the two
      ABONNEMENTEN lines if they differ from EUR 9,99 / EUR 69,99.
- [ ] Paste the description above into the iOS App version's **Description**.
- [ ] Set **Privacy Policy URL** to `/privacybeleid`.
- [ ] Confirm **License Agreement** is Apple's standard EULA, not a custom one.
- [ ] Click all three URLs from the rendered product page preview. This is
      literally the check that failed.
- [ ] Submit. **No new build is required** - nothing in the binary changed, so
      the build already attached to the version is still the right one.
- [ ] Reply to the App Review message saying the Terms of Use (EULA) and Privacy
      Policy links are now in the App Description and that the app uses Apple's
      standard EULA.
