# Plan voor Claude: Google Play-release BijbelStudie

Bijgewerkt **wo 16 sep 2026**. Dit is het werk dat Claude doet, zodat Alex alleen de stappen uit [play-store-release-guide.md](play-store-release-guide.md) hoeft te doen. Stapnummers als **A6**, **C2** verwijzen naar die gids.

**Regels die voor elke taak gelden**

- Repo-regels uit `CLAUDE.md`: nooit `screenshots/`, `build/` (behalve het ene AAB-bestand in taak 12) of `.dart_tool/` doorzoeken; één testbestand tegelijk; Flutter-commando's via de Bash-tool vanuit `bijbelstudie_mobile/`.
- `flutter test` herschrijft PNG's in `screenshots/`: vóór elke commit `git status --short screenshots/` en eventueel `git checkout -- screenshots/`.
- Bekende basisruis: `preview_mode_test` faalt op `main` (fix 773bad4 zit alleen op `daily-verse-translation`); de website heeft 2 bestaande `tsc`-fouten. Geen blokkade.
- `store-assets/` staat in `.gitignore`: alles daarin is lokaal, niet op GitHub.
- Productie-database = `scriptura`; alleen **read-only** zonder expliciet akkoord van Alex.
- Nooit geheimen printen (`key.properties`, keystore, service-account-JSON, reviewer-wachtwoord).
- Commit/push alleen als onderdeel van taak 6, 7, 8 of 20 (door Alex opgedragen in deze sessie); niet op eigen initiatief daarbuiten.

---

## Overzicht

| # | Taak | Status | Wacht op |
|---|---|---|---|
| 1 | Afbeeldingen: App Store 1.1.1 + Play (screenshots, icoon, functieafbeelding) | **Klaar** (`store-assets/`) | – |
| 2 | "AI-antwoord melden" in de app | **Klaar** (app gepusht; backend op website-branch) | – |
| 3 | Privacybeleid herschrijven + 90-dagen-purge automatiseren | **Klaar** (gecommit `levensboom` 3d6fba25); open punten → Alex **A11** | – |
| 4 | Prijs-fallback Play-product-ID's (R5) + pubspec 1.1.1 | **Klaar** (gepusht) | – |
| 5 | Plakteksten in `store-assets/google-play/` | **Klaar** | – |
| 6 | Website committen + deployen | Gecommit op `levensboom`; **merge/push = Alex A0** (website-CLAUDE.md) | Alex **A0** |
| 7 | BijbelAPI deployen (Render) | Gecommit 5982018 (tests OK), **push na A0** | Alex **A0** |
| 8 | App-repo committen + naar `main` pushen (Android AAB + iOS TestFlight) | **Klaar** (f6bf1a9 + b7315f3 op `main`) | – |
| 9 | Gegevensveiligheid controleren tegen nieuw privacybeleid | **Bezig** (agent) | – |
| 10 | GitHub-secret `REVENUECAT_GOOGLE_KEY` zetten | Te doen | Alex **A6** |
| 11 | CI-AAB downloaden, verifiëren, klaarzetten voor Alex | **Bezig** (run 35109937787) | – |
| 12 | Lokale AAB 1.0.7 (99) controleren voor Alex' eerste upload | Alleen nodig als CI-build faalt (lokaal: SHA-1 uploadsleutel geverifieerd) | 11 |
| 13 | Reviewer-account `applereview@mail.com` controleren | **Klaar**: bestaat in `scriptura`, `subscribed: true`, heeft wachtwoord, niet gearchiveerd | – |
| 14 | URL-checks website | Te doen | Alex **A0** |
| 15 | Winkeltekst-claims verifiëren tegen productie | **Bezig** (agent) | – |
| 16 | `GOOGLE_MOBILE_CLIENT_IDS` op Vercel controleren | **Klaar**: bevat de webclient `1005113136089-24a9…` | – |
| 17 | Android 16-emulatorcheck (edge-to-edge, terug-gebaar, draaien) | **Bezig** (agent, API 36-image wordt geïnstalleerd) | – |
| 18 | Google-inloggen- en RevenueCat-mapping verifiëren | Te doen | Alex **A8**, **C2**, **C4** |
| 19 | Testerfeedback verzamelen + productietoegang-antwoorden invullen | Te doen | Alex **D1**; dag 13 |
| 20 | Fixes/updates tijdens de gesloten test | Te doen | Alex **D1** |
| 21 | Melding "GO gesloten test" aan Alex | Te doen | 1, 2, 6, 8, 9, 11, 14, 15 |
| 22 | Logboek bijhouden (onderaan dit bestand) | Doorlopend | – |
| 23 | Na livegang: Google Play-badge op de website | Te doen | Alex **G2** |
| 24 | Optioneel: wervingsbanner op de website | Optioneel | < 15 groepsleden op dag 2 + akkoord Alex |
| 25 | Optioneel: Pro voor testers via backend | Optioneel | Groep niet accepteerbaar in Licentietests (**C3**) + akkoord Alex |
| 26 | Optioneel: automatische upload naar Interne test via Play Developer API | Optioneel, na livegang | akkoord Alex + apart service account |
| 27 | Memory bijwerken met Play-feiten | Te doen | 11, 18 |

**Al klaar vóór dit plan (2026-09-16):** targetSdk 36 (`android/app/build.gradle.kts`); `StoreCopy` (Google Play-teksten op Android in paywall, profiel, reviewvraag); workflow `.github/workflows/android-release.yml` (nog **ongetrackt**, dus nog niet op GitHub); secrets `ANDROID_KEYSTORE_BASE64`/`…_PASSWORD`/`ANDROID_KEY_PASSWORD`/`ANDROID_KEY_ALIAS` + variabele `GOOGLE_WEB_CLIENT_ID`; `TERMS_OF_USE_URL` in de CI-build (R4); lokale AAB 1.0.7 (99) ondertekend met uploadsleutel; website `/account-verwijderen` + `lib/accountPurge.ts` (niet gedeployd); dagtekst-curatie website + BijbelAPI (niet gedeployd).

---

## Taken

### 1. Afbeeldingen voor beide stores

- **Doel:** Play: app-icoon 512 × 512, functieafbeelding 1024 × 500, 2–8 telefoon-screenshots 1080 × 1920. App Store 1.1.1: screenshots per vereist formaat.
- **Bestanden:** `store-assets/google-play/graphics/`, `store-assets/app-store-1.1.1/<formaat>/`.
- **Afhankelijkheid:** geen. **Status:** Klaar.
- **Verificatie** (na oplevering):
  ```bash
  cd /c/Projects/bijbelstudie-app && python - <<'EOF'
  from PIL import Image; import pathlib
  for p in sorted(pathlib.Path('store-assets').rglob('*')):
      if p.suffix.lower() in ('.png','.jpg','.jpeg'):
          im=Image.open(p); print(p, im.size, im.mode, p.stat().st_size//1024,'KB')
  EOF
  ```
  Eisen: icoon 512×512, ≤ 1024 KB; functieafbeelding 1024×500 zonder alpha (mode `RGB`); Play-screenshots zonder alpha, lange zijde ≤ 2× korte; App Store 6,9" 1320×2868 of 1290×2796.
- **Daarna:** exacte bestandsnamen in `winkelvermelding.md` tabel 4 zetten; Alex melden dat **B1** en de App Store-sectie kunnen.

### 2. "AI-antwoord melden"

- **Doel:** per AI-antwoord een in-app meldactie (Play-beleid voor AI-gegenereerde content), zonder de app te verlaten.
- **Bestanden:** `bijbelstudie_mobile/lib/features/ai/present/ai_assistant_pane.dart`, feedback-repository in `lib/features/feedback/data/`.
- **Afhankelijkheid:** geen. **Status:** Klaar.
- **Verificatie:** `flutter analyze`; het bijbehorende testbestand in `test/`; het exacte knoplabel opzoeken en de reviewer-instructie (regel 3) in `store-assets/google-play/app-content-antwoorden.md` daarop laten kloppen; ook "Meld het direct in de app" in `winkelvermelding.md`.

### 3. Privacybeleid + automatische purge

- **Doel:** volledig privacybeleid (verwerkers, bewaartermijnen, rechten, accountverwijdering); het archief van verwijderde accounts automatisch na 90 dagen wissen.
- **Repo:** `C:\Projects\bijbelstudie` (`app/privacybeleid/page.tsx`, `scripts/purge-deleted-accounts.mjs`, `docs/privacy-policy-draft.md`, planning via Vercel cron of GitHub Action).
- **Afhankelijkheid:** geen. **Status:** Klaar.
- **Verificatie:** `npx tsc --noEmit` (alleen de 2 bekende fouten); relevante lokale vitest-bestanden in `tests/`; na deploy taak 14. Lijst met verwerkers doorgeven aan taak 9.

### 4. Prijs-fallback (R5) + versie

- **Doel:** als de RevenueCat-offering leeg is, moet de directe productlookup Play-ID's `bijbelstudie_pro_monthly:monthly` / `bijbelstudie_pro_yearly:yearly` matchen op het deel vóór `:`.
- **Bestanden:** `lib/features/premium/present/premium_controller.dart` (rond r. 251–254), `lib/features/premium/data/purchase_service.dart` (heeft al een ongecommitte wijziging die `subscriptionId:basePlanId` noemt: eerst lezen, niet dubbel doen), `pubspec.yaml`.
- **Status:** `pubspec.yaml` staat al op `version: 1.1.1+14` (**Klaar**, ongecommit). R5: **Bezig/controleren**.
- **Verificatie:** `flutter analyze`; één premium-testbestand (bijv. `flutter test test/<premium>_test.dart`) met een geval voor `bijbelstudie_pro_yearly:yearly`.

### 5. Plakteksten

- **Status:** **Klaar** (2026-09-16).
- **Bestanden:** `store-assets/google-play/winkelvermelding.md` (naam 12, kort 71, lang 2601 tekens), `release-notes.md` (204 / 120+ / 159), `app-content-antwoorden.md` (reviewer-instructie 451 tekens), `productietoegang-antwoorden.md`, `testers-uitnodiging.md`, `abonnementen.md`.
- **Hertellen na wijzigingen:**
  ```bash
  cd /c/Projects/bijbelstudie-app/store-assets/google-play && python -c "import re,sys;s=open('winkelvermelding.md',encoding='utf-8').read();print([len(b) for b in re.findall(r'\`\`\`\n(.*?)\n\`\`\`',s,re.S)])"
  ```

### 6. Website committen en deployen

- **Doel:** live: `/account-verwijderen`, `lib/accountPurge.ts`, nieuw privacybeleid, purge-automatisering, dagtekst-curatie, FAQ "Hoe verwijder ik mijn account?" (`lib/content/helpFaq.ts`, controleren of die al is bijgewerkt), plus de nog ongecommitte owner-guard/archief-wijzigingen (memory: owner-account-deleted-2026-09-08).
- **Repo:** `C:\Projects\bijbelstudie` (Vercel deployt bij push naar `main`).
- **Afhankelijkheid:** taak 3. **Status:** Gecommit op `levensboom` (3d6fba25, alleen eigen bestanden). **Niet** mergen/pushen: website-`CLAUDE.md` en de andere sessie (bijbelstudie-52) zeggen dat `main` door Alex wordt gemerged/gepusht na lokaal testen → Alex **A0**. Ook nodig: `CRON_SECRET` en `RESEND_API_KEY` (ontbreekt → wachtwoord-reset-mails worden niet verstuurd) in Vercel.
- **Stappen (historisch):**
  ```bash
  cd /c/Projects/bijbelstudie
  git status --short
  npx tsc --noEmit            # verwacht: alleen de 2 bekende fouten
  npx vitest run tests/<relevant>.test.ts   # lokaal, tests/ is gitignored
  git add <specifieke bestanden>   # geen .env*, geen tests/
  git commit -m "..."        # met Co-Authored-By-regel
  git push origin main
  ```
- **Verificatie:** Vercel-deploy groen (`vercel ls` of `gh`/Vercel-dashboardstatus), daarna taak 14.

### 7. BijbelAPI deployen

- **Doel:** dagtekst-curatie live.
- **Repo:** `C:\Projects\bijbelapi` (heeft `render.yaml`; Render deployt bij push).
- **Afhankelijkheid:** Alex **A0** (oude website toont bij passages de verkeerde verwijzing). **Status:** Gecommit 5982018, tests OK (`.venv/Scripts/python.exe -m unittest tests.test_daytext`). Na "website live": `git -C /c/Projects/bijbelapi push origin main`, dan `curl 'https://bijbelapi.com/api/daytext?version=sv&seed=2026-09-17'`.
- **Stappen:** `git status`, tests van die repo draaien, gericht committen, `git push origin main`.
- **Verificatie:** Render-deploy geslaagd; het dagtekst-endpoint met `curl` aanroepen en controleren dat de website/app de gecureerde tekst tonen.

### 8. App-repo committen en naar `main` pushen

- **Doel:** eerste CI-build 1.1.1 voor Play (met AI-melden, R5, StoreCopy, targetSdk 36, `goog_`-sleutel) en iOS TestFlight 1.1.1.
- **Repo:** `C:\Projects\bijbelstudie-app`. Huidige branch `feature/bijbel-gelezen` staat op dezelfde commit als `main` (2731f23) plus ongecommitte wijzigingen.
- **Afhankelijkheid:** taak 2 en 4. **Status:** Klaar: f6bf1a9 (code) + b7315f3 (docs) gepusht naar `main` vanaf `feature/bijbel-gelezen` via `git push origin HEAD:main`, alleen eigen hunks (Bijbel gelezen-scherm en `/profile/bijbel`-links van sessie bijbelstudie-52 bewust niet meegenomen). Runs: Android 35109937787, iOS 35109937791.
- **Stappen:**
  ```bash
  cd /c/Projects/bijbelstudie-app/bijbelstudie_mobile
  flutter analyze
  flutter test test/<gewijzigde features>_test.dart     # per bestand
  cd .. && git status --short && git status --short screenshots/
  git add .github/workflows/android-release.yml bijbelstudie_mobile/lib bijbelstudie_mobile/pubspec.yaml bijbelstudie_mobile/android/app/build.gradle.kts docs/
  git commit -m "..."        # met Co-Authored-By-regel
  git checkout main && git merge --ff-only feature/bijbel-gelezen && git push origin main
  gh run list --workflow android-release.yml -L 1
  gh run watch <run-id> --exit-status
  gh run list --workflow ios-release.yml -L 1 && gh run watch <run-id> --exit-status
  ```
  Let op: de workflow `android-release.yml` is nu **ongetrackt**; pas na deze push bestaat de knop *Run workflow* en `gh workflow run`.
- **Bij falen:** `gh run view <run-id> --log-failed`, fixen, nieuwe commit, opnieuw pushen. Versiecode wordt automatisch 100 + runnummer.
- **Verificatie:** beide runs groen; Android-samenvatting noemt `Android AAB ready: 1.1.1 (1xx)` zonder waarschuwing over `REVENUECAT_GOOGLE_KEY`. Daarna taak 11; TestFlight-buildnummer aan Alex melden.

### 9. Gegevensveiligheid controleren

- **Doel:** het formulier in `store-assets/google-play/app-content-antwoorden.md` §7 klopt met het nieuwe privacybeleid en met wat de app echt verstuurt.
- **Afhankelijkheid:** taak 3. **Status:** Te doen.
- **Controleren:**
  - verwerkers uit het privacybeleid (hosting, database, RevenueCat, Google Sign-In, Google Gemini, TTS, e-mail) → blijven "verzameld, niet gedeeld" zolang ze verwerker zijn;
  - `pubspec.lock`: geen nieuwe SDK's met eigen dataverzameling (ads, crash, analytics, Firebase);
  - AAB-manifest (taak 11): geen `AD_ID`, locatie, contacten;
  - `lib/core/analytics/analytics.dart` stuurt alleen eventnaam + `platform` + props (geen apparaat-ID);
  - zoekgeschiedenis: tijdelijk verwerkt = Ja (server slaat niets op, "Recent gezocht" lokaal);
  - worden er marketingmails gestuurd? Dan "Berichten van de ontwikkelaar" bij E-mailadres.
- **Verificatie:** banner "wordt door Claude gecontroleerd" in §7 vervangen door "Gecontroleerd op <datum>"; als er iets verandert, Alex in de chat precies melden welke regel.

### 10. `REVENUECAT_GOOGLE_KEY` zetten

- **Afhankelijkheid:** Alex plakt de `goog_…`-sleutel (**A6**). **Status:** Te doen.
- **Stappen:**
  ```bash
  gh secret set REVENUECAT_GOOGLE_KEY --repo AlexLamper/bijbelstudie-app --body "goog_…"
  gh secret list --repo AlexLamper/bijbelstudie-app | grep REVENUECAT_GOOGLE_KEY
  # draaide taak 8 al zonder sleutel:
  gh workflow run android-release.yml --repo AlexLamper/bijbelstudie-app --ref main
  ```
- **Verificatie:** secret staat in de lijst; volgende run heeft geen `REVENUECAT_GOOGLE_KEY`-waarschuwing. Sleutel in het logboek (hij is publiek, geen geheim).

### 11. CI-AAB downloaden, verifiëren en klaarzetten

- **Doel:** Alex hoeft niet door GitHub te klikken; hij sleept één bestand (**B2**, **E2**).
- **Afhankelijkheid:** taak 8 (of 20). **Status:** Te doen.
- **Stappen:**
  ```bash
  cd /c/Projects/bijbelstudie-app
  mkdir -p store-assets/google-play/builds
  gh run download <run-id> -n bijbelstudie-1.1.1-<code>-aab -D store-assets/google-play/builds/
  AAB=store-assets/google-play/builds/bijbelstudie-1.1.1-<code>.aab
  keytool -printcert -jarfile "$AAB" | grep -E "Owner|SHA1"     # SHA1 FF:2C:27:A0:…:14:E7:7E
  [ -f /c/Users/alexl/bundletool.jar ] || curl -L -o /c/Users/alexl/bundletool.jar https://github.com/google/bundletool/releases/download/1.18.1/bundletool-all-1.18.1.jar
  java -jar /c/Users/alexl/bundletool.jar dump manifest --bundle "$AAB" | grep -E 'package=|versionCode|versionName|targetSdkVersion|uses-permission'
  ```
- **Verificatie:** `package="com.bijbelstudie.app"`, `versionName="1.1.1"`, `targetSdkVersion="36"`, versiecode > 99; geen `AD_ID`, locatie, SMS, exacte alarmen of foreground service. Dan Alex melden: bestandsnaam + welk blok uit `release-notes.md` (of de ingevulde update-tekst).

### 12. Lokale AAB 1.0.7 (99) controleren

- **Doel:** zeker weten dat Alex in **A7** het goede bestand uploadt (package ligt na de eerste upload voor altijd vast).
- **Status:** Te doen (nu, vóór Alex bij A7 is).
- **Stappen** (alleen dit ene bestand, geen `build/` doorzoeken):
  ```bash
  AAB=/c/Projects/bijbelstudie-app/bijbelstudie_mobile/build/app/outputs/bundle/release/app-release.aab
  keytool -printcert -jarfile "$AAB" | grep -E "Owner|SHA1"
  java -jar /c/Users/alexl/bundletool.jar dump manifest --bundle "$AAB" | grep -E 'package=|versionCode|targetSdkVersion'
  ```
- **Verificatie:** uploadsleutel-SHA-1, `com.bijbelstudie.app`, versiecode 99, targetSdk 36. Klopt iets niet of ontbreekt het bestand: Alex melden "sla A7 over, doe het in B2".

### 13. Reviewer-account controleren

- **Doel:** `applereview@mail.com` bestaat en heeft Pro (Play-reviewers gebruiken hetzelfde account als Apple).
- **Status:** Te doen (nu).
- **Stappen:** read-only query op productie (`scriptura`) volgens het bekende diag-patroon: gebruiker bestaat, niet in het verwijderde-accountsarchief, Pro/`subscribed` actief. Wachtwoord niet nodig en niet vragen.
- **Herstel (alleen met akkoord van Alex, hij geeft het wachtwoord zelf in zijn terminal):** `C:\Projects\bijbelstudie\scripts\ensure-review-account.mjs --write`.
- **Verificatie:** resultaat in het logboek; afwijkingen direct aan Alex melden (blokkeert **A10** App-toegang).

### 14. URL-checks website

- **Afhankelijkheid:** taak 6. **Status:** Te doen.
- **Stappen:**
  ```bash
  for u in privacybeleid account-verwijderen algemene-voorwaarden contact; do
    curl -s -o /dev/null -w "%{http_code} $u\n" "https://www.bijbelstudie.io/$u"; done
  curl -s https://www.bijbelstudie.io/account-verwijderen | grep -oE "BijbelStudie|Google Play|90 dagen|info@bijbelstudie.io" | sort -u
  curl -s https://www.bijbelstudie.io/privacybeleid | grep -oiE "RevenueCat|Gemini|Vercel|bewaar|verwijder" | sort -u
  ```
- **Verificatie:** alle vier `200` zonder redirect; accountpagina noemt BijbelStudie, stappen, wat bewaard blijft (90 dagen) en dat een Google Play-abonnement apart opgezegd moet worden; privacybeleid noemt de verwerkers.

### 15. Winkeltekst-claims verifiëren

- **Doel:** de volledige beschrijving mag niets beloven wat de Android-build niet heeft.
- **Status:** Te doen (nu).
- **Controleren** in `bijbelstudie_mobile/lib` (grep, geen hele grote bestanden lezen) en tegen de productie-API: NBG-vertaling 1951, Statenvertaling, KJV beschikbaar in de app (niet HTTP 451); commentaren Matthew Henry, Dachsel, KingComments; lettergrootte + regelafstand + donkere weergave; dagelijkse herinnering; begeleide studies; leesreeks en badges; dagtekst; gratis notities (met limiet) vs. Pro "onbeperkt".
- **Verificatie:** `winkelvermelding.md` aangepast waar nodig, tellingen opnieuw (taak 5), zin "Claims gecontroleerd tegen productie op <datum>" bijwerken.

### 16. `GOOGLE_MOBILE_CLIENT_IDS` op Vercel

- **Doel:** de backend accepteert ID-tokens van Android (aud = webclient).
- **Status:** Te doen (nu).
- **Stappen:**
  ```bash
  cd /c/Projects/bijbelstudie
  vercel env pull "<scratchpad>/vercel-prod.env" --environment=production --yes
  grep -c "1005113136089-24a9hvcjkm2qv8r0tll8n9r424gnaf2l" "<scratchpad>/vercel-prod.env"   # alleen tellen, niets printen
  rm "<scratchpad>/vercel-prod.env"
  ```
- **Verificatie:** telling ≥ 1 binnen `GOOGLE_MOBILE_CLIENT_IDS`. Zo niet: toevoegen vereist akkoord van Alex + redeploy.

### 17. Android 16-emulatorcheck

- **Doel:** statusbalk/navigatiebalk bedekken geen reader-header of tabs (edge-to-edge), systeem-terug sluit sheets en popt routes, draaien werkt.
- **Afhankelijkheid:** taak 8 (zelfde code). **Status:** Te doen (blokkeert indienen niet).
- **Stappen:**
  ```bash
  cd /c/Projects/bijbelstudie-app/bijbelstudie_mobile
  flutter emulators                       # API 36-AVD kiezen of melden dat die ontbreekt
  flutter emulators --launch <avd_id>
  flutter run --release --dart-define=USE_PRODUCTION_API=true \
    --dart-define=GOOGLE_WEB_CLIENT_ID="$(gh variable get GOOGLE_WEB_CLIENT_ID)" \
    --dart-define=TERMS_OF_USE_URL=https://www.bijbelstudie.io/algemene-voorwaarden
  adb exec-out screencap -p > "<scratchpad>/a16-<scherm>.png"    # nooit naar screenshots/
  adb shell input keyevent KEYCODE_BACK
  ```
- **Verificatie:** screenshots van Start, reader, split-studie, paywall en een open sheet bekeken; problemen als fix in taak 20.

### 18. Google-inloggen en RevenueCat-mapping verifiëren

- **Afhankelijkheid:** Alex **A8** (SHA-1 + clients), **C2** (producten), **C4** (rooktest). **Status:** Te doen.
- **Controleren:**
  - `lib/features/auth/.../google_sign_in_config.dart`: `serverClientId` = `GOOGLE_WEB_CLIENT_ID`; knop verborgen zonder waarde;
  - CI-variabele `gh variable get GOOGLE_WEB_CLIENT_ID` = `1005113136089-24a9…`;
  - `purchase_service.dart` / `premium_controller.dart`: `kRcProductIds`, packages `$rc_monthly`/`$rc_annual`, R5-fallback matcht `:monthly`/`:yearly`;
  - diagnose-tekst die Alex plakt interpreteren (`sleutel: none:google` = build zonder sleutel; 0 producten = credentials/abonnement/offering/sideload).
- **Verificatie:** conclusie aan Alex; SHA-1 van Play-ondertekening en de gekoppelde product-ID's in het logboek.

### 19. Testerfeedback + productietoegang-antwoorden

- **Afhankelijkheid:** Alex **D1** (startdatum); invullen op dag 13 (± zo 4 okt) na Alex' tellingen (**F1**). **Status:** Te doen.
- **Stappen:**
  - feedback sinds de startdatum read-only uit productie halen (feedback-tabel, incl. AI-meldingen), plus wat Alex in de chat plakte;
  - `git log --oneline --since=<startdatum>` voor de lijst met wijzigingen per build (logboek);
  - testaankopen: tellen uit RevenueCat-webhookgegevens in de database als store/omgeving wordt opgeslagen, anders Alex vragen (RevenueCat → Customers → Sandbox);
  - placeholders `<N_TESTERS>`, `<N_PURCHASES>`, `<N_UPDATES>`, `<FEEDBACK_POINTS>`, `<CHANGES>`, `<ANDROID_RANGE>` in `store-assets/google-play/productietoegang-antwoorden.md` invullen.
- **Verificatie:** geen `<` placeholders meer (`grep -c "<[A-Z_]*>" productietoegang-antwoorden.md` = 0); alles waarheidsgetrouw; Alex melden "productietoegang-antwoorden ingevuld".

### 20. Fixes en updates tijdens de gesloten test

- **Afhankelijkheid:** feedback of crashes. **Status:** Te doen. Minstens één update rond dag 7 (Google vraagt wat er veranderd is).
- **Stappen:** fix → gerichte test → commit → `git push origin main` → taak 11 → blok B uit `release-notes.md` invullen (≤ 500 tekens) → Alex melden met bestandsnaam + tekst (**E2**) → logboek.
- **Niet doen:** niets wijzigen dat de package, de ondertekening of de versiecode-reeks raakt; geen nieuwe SDK zonder taak 9 opnieuw.

### 21. Melding "GO gesloten test"

- **Afhankelijkheid:** taken 1, 2, 6, 8, 9, 11, 14, 15 klaar (13 zonder problemen). **Status:** Te doen.
- **Bericht aan Alex:** "GO gesloten test" + bestandsnaam van de AAB + eventuele wijzigingen in Gegevensveiligheid of App-toegang-tekst + dat de afbeeldingen klaarstaan. Streefmoment: **do 17 sep**.

### 22. Logboek bijhouden

- Onderaan dit bestand: versiecode per track, SHA-1's, sleutels (alleen publieke), datums (ingediend, live, 12e tester, aanvraag, goedkeuring, live), feedback → wijziging.

### 23. Na livegang: Google Play-badge op de website

- **Afhankelijkheid:** Alex **G2**. **Status:** Te doen.
- **Repo:** `C:\Projects\bijbelstudie`: "Ontdek het op Google Play"-badge (officiële badge, volgens Google's richtlijnen) naast de App Store-link, link `https://play.google.com/store/apps/details?id=com.bijbelstudie.app`. Commit + push na akkoord.
- **Verificatie:** badge zichtbaar op productie, link opent de Play-pagina.

### 24. Optioneel: wervingsbanner op de website

- **Wanneer:** Alex meldt op dag 2 minder dan 15 groepsleden, en geeft akkoord.
- **Wat:** tijdelijke banner voor ingelogde webgebruikers: "Heb je Android? Test de nieuwe app mee" → `https://groups.google.com/g/bijbelstudie-testers`. Verwijderen na goedkeuring productietoegang.

### 25. Optioneel: Pro voor testers via backend

- **Wanneer:** Licentietests accepteert de Google Group niet (**C3**) en Alex wil dat testers Pro kunnen proberen.
- **Wat:** tijdelijke Pro-vlag (zoals het reviewer-account) voor de e-mailadressen die testers opgeven, met einddatum; productie-schrijfactie **alleen met akkoord**. Testersberichten in `testers-uitnodiging.md` aanpassen ("niet kopen, Pro staat al aan").

### 26. Optioneel (na livegang): automatische upload naar Interne test

- **Wat:** apart service account met alleen "Releases naar testtracks uitbrengen" (Alex maakt het aan), JSON als GitHub-secret `PLAY_SERVICE_ACCOUNT_JSON`, extra stap in `android-release.yml` die de AAB als concept naar de interne track zet. Scheelt Alex de upload bij elke update. Niet vóór livegang (kan niet de eerste upload doen en voegt risico toe op het kritieke pad).

### 27. Memory bijwerken

- **Na taak 11 en 18:** memory-bestand met Play-feiten: Play-ondertekenings-SHA-1, eerste CI-versiecode, testgroepadres, datum gesloten test live, dat `store-assets/` gitignored is.

---

## Gevonden in de oude gids (en zo opgelost)

- Oude gids noemde pubspec `1.0.6+14`, targetSdk 35 en uploadrij "15 (1.0.7)"; werkelijk: pubspec `1.1.1+14`, targetSdk 36, lokale AAB 99, CI 101+.
- Oude gids zei "Run workflow" in GitHub, maar `android-release.yml` is nog ongetrackt → bestaat pas na taak 8.
- "Alle vertalingen en commentaren zijn publiek domein" (beschrijving + reviewer-tekst) klopt niet: NBG 1951 en KingComments zijn met toestemming (`profile_screen.dart`). Aangepast.
- Doelgroep "18+, optioneel 16–17" versus productietoegang "adults (16+)": nu overal 18+.
- Testersbericht beloofde gratis Pro met testkaart, maar dat werkt alleen als de groep in Licentietests staat (onzeker) → bericht zegt nu "zie je geen testkaart, stop"; taak 25 als uitweg.
- Pad `C:\Projectsijbelstudie` in de oude gids (backslash-fout) → `C:\Projects\bijbelstudie`.

---

## Logboek

| Datum | Versiecode (versie) | Track | Notitie |
|---|---|---|---|
| 2026-09-15 | 14 (1.0.6) | – | targetSdk 35, niet gebruiken |
| 2026-09-16 | 99 (1.0.7) | Interne test (Alex **A7**) | lokaal, uploadsleutel, targetSdk 36, zonder RevenueCat-sleutel |
| | 101+ (1.1.1) | Interne + Gesloten test | eerste CI-build |

| Gegeven | Waarde |
|---|---|
| Uploadsleutel SHA-1 | `FF:2C:27:A0:E2:EF:F0:2E:C6:A4:5E:AC:F9:2C:77:8A:AC:14:E7:7E` |
| Play-ondertekening SHA-1 | `<na Alex A8>` |
| RevenueCat Android-sleutel | `goog_…` `<na Alex A6>` |
| Reviewer-account | `applereview@mail.com` (gedeeld met Apple) |
| Testgroep | `bijbelstudie-testers@googlegroups.com` `<bevestigen na Alex A2>` |
| Gesloten test ingediend / live | `<>` / `<>` |
| 12e tester aangemeld | `<>` |
| Productietoegang aangevraagd / goedgekeurd | `<>` / `<>` |
| Live in productie | `<>` |

| Datum | Feedback | Wijziging / build |
|---|---|---|
| | | |
