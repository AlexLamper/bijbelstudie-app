# Android App Links: bijbelstudie.io-links openen in de app

Geschreven 2026-10-19, bij het invullen van **App-indexering** in de Google
Play Console.

Een App Link is een gewone `https://`-link naar je eigen site die Android
rechtstreeks in de app opent in plaats van in de browser. Daar zijn drie
dingen voor nodig, en ze moeten alle drie kloppen, anders valt het stil terug
op de browser zonder foutmelding:

1. een intent-filter in de app die de host en de paden claimt,
2. een `assetlinks.json` op de website die de app terugherkent,
3. een nieuwe release, want een intent-filter zit in de build.

Punt 1 staat in deze repo en is klaar. Punt 2 staat in de **website-repo**
(`C:\Projects\bijbelstudie`) en moet nog. Punt 3 gaat mee met je volgende
Play-release.

---

## Wat er in deze repo is gewijzigd

| Bestand | Wat |
|---|---|
| `android/app/src/main/AndroidManifest.xml` | intent-filter met `android:autoVerify="true"` voor `bijbelstudie.io` en `www.bijbelstudie.io` |
| `lib/core/router/deep_link_routes.dart` | vertaalt een website-pad naar een app-route, en houdt de link vast tot de splash klaar is |
| `lib/core/router/app_router.dart` | `redirect` op de GoRouter die dat afhandelt |
| `lib/features/auth/present/splash_screen.dart` | pakt de vastgehouden link op na de sessiecheck |
| `test/deep_link_routes_test.dart` | 8 tests over de vertaling en de overdracht |

### Welke paden de app claimt

Alleen de secties die de app ook echt kan tonen:

| Website | App | Waarom |
|---|---|---|
| `/bijbel/<boek>/<nummer>` | `/studie/hoofdstuk/<boek>/<nummer>` | de site leest een hoofdstuk hier, de app toont hetzelfde hoofdstuk met het studiepaneel |
| `/bijbel` | `/read` | de lezer |
| `/studie/...` | gelijk | hoofdstukstudie en lesdagen |
| `/studies`, `/studies/<id>` | gelijk | overzicht en losse studie |
| `/bronnen`, `/bronnen/<slug>` | gelijk | achtergrond per bijbelboek |

Alles wat hier niet in staat blijft in de browser. Dat is met opzet: een
host-brede claim zou ook `/prijzen`, `/contact` en de links uit je
wachtwoord-herstelmails opslokken, en die horen op het web.

Verander je deze lijst, pas dan **beide** plekken aan: de `pathPrefix`-regels
in het manifest en `_handledPrefixes` in `deep_link_routes.dart`. Wijken ze af,
dan opent Android de app voor een pad dat de app vervolgens weggooit, en komt
de lezer op het dashboard uit. Dat leest als een kapotte link.

### Waarom er een wachtrij in zit

Een koude start via een link geeft de router het diepe pad als beginlocatie,
dus de splash wordt overgeslagen. Een uitgelogde lezer landt dan op een scherm
dat een sessie nodig heeft. De `redirect` parkeert de link daarom en stuurt
eerst naar `/`; de splash doet zijn auth-check en navigeert er daarna heen.
Dat is dezelfde constructie die `NotificationService` al gebruikt voor een tik
op een melding tijdens het opstarten. Volgt er allebei een, dan wint de link:
dat is de recentere handeling.

---

## Wat jij nog moet doen

### 1. De vingerafdruk ophalen

Play Console → **BijbelStudie** → **Release** → **Setup** → **App-ondertekening**.

Neem de **SHA-256-certificaatvingerafdruk** van de
**app-ondertekeningssleutel**, niet die van de uploadsleutel. Op die pagina
staan ze allebei, en met de verkeerde faalt de verificatie zonder melding.
Het is een reeks van 32 hex-paren met dubbele punten ertussen.

### 2. `assetlinks.json` op de website zetten

In de website-repo `C:\Projects\bijbelstudie`, als
`public/.well-known/assetlinks.json`:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.bijbelstudie.app",
      "sha256_cert_fingerprints": [
        "VUL:HIER:DE:SHA256:VAN:PLAY:APP:SIGNING:IN"
      ]
    }
  }
]
```

Eisen van Google, alle vier verplicht:

- bereikbaar op **`https://bijbelstudie.io/.well-known/assetlinks.json`** en op
  dezelfde plek onder `www`,
- `content-type: application/json`,
- **geen** redirect naar de andere host, geen 301 naar `www` of andersom.
  Let op: `https://bijbelstudie.io/...` stuurt nu met een 301 door naar
  `https://www.bijbelstudie.io/...` (gemeten 2026-10-19). Voor gewone pagina's
  is dat prima, maar de verificatie van App Links volgt geen redirect. Het
  bestand moet dus op **beide** hosts rechtstreeks met een 200 komen, met een
  uitzondering op de www-redirect voor het pad `/.well-known/assetlinks.json`,
- geen authenticatie ervoor.

Controleer na het uitrollen met:

```bash
curl -i https://bijbelstudie.io/.well-known/assetlinks.json
curl -i https://www.bijbelstudie.io/.well-known/assetlinks.json
```

Twee keer `200` en `application/json`, zonder `Location`-header ertussen.

Het stond er op 2026-10-19 nog niet: beide gaven `404`.

### 3. App-indexering in de Play Console

Play Console → **BijbelStudie** → **Groeien** → **App-indexering** → de site
`https://bijbelstudie.io` toevoegen.

Verifieer hem in Google Search Console met **hetzelfde Google-account** als je
Play-ontwikkelaarsaccount. Neem daar het liefst een **Domein-property**
(`bijbelstudie.io`, via een DNS TXT-record): die dekt in een keer `http` en
`https`, met en zonder `www`, en alle subdomeinen.

Dit stuk mag je nu al doen. Het werkt los van punt 1 en 2 en kan geen kwaad.

### 4. Uitrollen en nameten

De intent-filter zit in de build, dus hij gaat pas werken na een nieuwe
Play-release. Na installatie van die build controleer je op een toestel:

```bash
adb shell pm get-app-links com.bijbelstudie.app
```

Je wilt `verified` zien staan bij beide hosts. Staat er `none` of
`legacy_failure`, dan klopt `assetlinks.json` niet, of was hij nog niet
bereikbaar toen de app werd geinstalleerd. Opnieuw laten verifieren:

```bash
adb shell pm verify-app-links --re-verify com.bijbelstudie.app
```

Daarna een link openen vanuit bijvoorbeeld een chat-app:
`https://bijbelstudie.io/bijbel/genesis/1` hoort de app te openen op Genesis 1
met het studiepaneel.

---

## Nog niet gedaan: iOS

Hetzelfde verhaal heet daar Universal Links en vraagt om
`apple-app-site-association` op de site plus de **Associated Domains**-
capability in het Xcode-project. Dat raakt de ondertekening, en die is
vastgelegd in `docs/ios-release-setup.md` en `docs/handoff-manual-steps.md`.
Lees die eerst; niet opnieuw afleiden uit het Xcode-project.
