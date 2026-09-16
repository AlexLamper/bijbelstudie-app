# Google Play-release BijbelStudie: wat JIJ moet doen

Bijgewerkt **wo 16 sep 2026**. Hier staan **alleen de stappen die jij zelf moet doen**: dingen in Play Console, Google Cloud, RevenueCat, App Store Connect, en met je eigen telefoon en contacten. Alles wat Claude doet (code, builds, deploys, teksten, afbeeldingen, controles) staat in **[play-store-claude-plan.md](play-store-claude-plan.md)**.

**Wat Claude al gedaan heeft of nu doet**

- **Klaar en gepusht naar `main` (app):** targetSdk 36; op Android noemen paywall, profiel en reviewvraag Google Play in plaats van Apple; knop **Melden** onder elk AI-antwoord + "AI kan fouten maken"; prijs-fallback voor Play-abonnementen; versie 1.1.1; GitHub bouwt bij elke push een ondertekende AAB (versiecode = 100 + runnummer).
- **Klaar, maar nog NIET live (website):** nieuw privacybeleid, `/account-verwijderen`, volledig wissen van gegevens, AI-meldingen in `/beheer/feedback`, dagtekst-verbetering en een dagelijkse bewaartermijn-cron. Staat gecommit op branch `levensboom` van de website. Live zetten doe jij (stap **A0**), want de website-regels zeggen dat alleen jij `main` merget/pusht.
- **Klaar:** screenshots en afbeeldingen: `store-assets/google-play/phone/` (8 telefoon-screenshots), `store-assets/google-play/graphics/` (icoon + functieafbeelding), `store-assets/app-store-1.1.1/` (iPhone 6.9", 6.5", iPad 13"). Uitleg in `store-assets/README.md`.
- **Klaar:** alle plakteksten staan in `store-assets/google-play/`: `winkelvermelding.md`, `release-notes.md`, `app-content-antwoorden.md`, `abonnementen.md`, `productietoegang-antwoorden.md`, `testers-uitnodiging.md`.
- **Nu bezig:** de eerste GitHub-build 1.1.1 controleren en klaarzetten in `store-assets/google-play/builds/`; Gegevensveiligheid en winkeltekst nalopen; reviewer-account en Google-inlogconfig op de server controleren; Android 16-check.
- **Na jouw A0:** BijbelAPI deployen (dagtekst) en de live pagina's controleren.

**Zo lees je deze gids**

- Labels met **≈** zijn vertaald en niet in jouw console gecontroleerd. Klopt er een niet, kijk dan naar het Engelse label of typ een woord in de zoekbalk bovenin Play Console (bijv. `handelaar`, `licentie`, `ondertekening`).
- **Plak in de chat:** dit heeft Claude van je nodig om verder te kunnen.
- **Wacht op Claude:** begin pas als Claude in de chat heeft gemeld dat het klaar is.
- **Geheimen:** plak nooit `key.properties`, keystore-wachtwoorden, het reviewer-wachtwoord of de service-account-JSON in de chat. De `goog_…`-sleutel van RevenueCat en SHA-1-vingerafdrukken zijn niet geheim; die mag je wel plakken.

---

## Tijdlijn (snelste route)

De flessenhals is Google's regel: **12 testers, 14 dagen onafgebroken aangemeld** voor een gesloten test. Die klok start pas als de gesloten test door Google is goedgekeurd én je testers zich hebben aangemeld. Dus: gesloten test **zo vroeg mogelijk** indienen, en testers **vandaag** al werven.

| Datum | Jij | Claude |
|---|---|---|
| **wo 16 sep** (dag 0) | Fase A: account, testers werven, app aanmaken, betalingsprofiel, RevenueCat-sleutel, eerste AAB naar interne test, OAuth-clients, service account, App-content | Afbeeldingen, AI-melden, privacybeleid afmaken; website + BijbelAPI deployen; app pushen zodra jouw `goog_`-sleutel binnen is |
| **do 17 sep** (dag 1) | Fase B: winkelvermelding, build uploaden, **gesloten test indienen** | Build 1.1.1 controleren en klaarzetten, "GO gesloten test" melden |
| **vr 18 – ma 21 sep** | Fase C (terwijl Google beoordeelt): abonnementen, RevenueCat koppelen, licentietests, rooktest op je telefoon | Controles, eventuele fixes als update |
| **± ma 21 sep** | Fase D: gesloten test live → **iedereen dezelfde dag aanmelden** (≥ 12) | Tellen en loggen |
| **ma 21 sep – ma 5 okt** | Fase E: herinneringen sturen, updates uploaden, feedback doorsturen | Fixes bouwen, feedbacklog bijhouden |
| **ma 5 okt** | Fase F: **productietoegang aanvragen** | Antwoorden invullen met echte cijfers |
| **± wo 7 – ma 12 okt** | Goedkeuring (meestal ≤ 7 dagen) → **dezelfde dag** Fase G: productierelease indienen | Release notes, laatste build-check |
| **± do 15 okt** | **Live in Google Play** (beoordeling 1–3 dagen; zoeken werkt 1–2 dagen later) | Google Play-badge op de website |

**Doeldatum: live rond do 15 okt 2026.** Bandbreedte: 9 okt (alles snel) tot ± 26 okt (trage beoordelingen). Wordt de productietoegang afgewezen (meestal te weinig tester-activiteit), dan komen er minstens 14 dagen bij.

**Interne test: wel of niet?** Wel, maar alleen parallel. Hij heeft geen beoordeling, is binnen minuten klaar en is nodig om (1) abonnementen te kunnen aanmaken, (2) de SHA-1 van Google's ondertekeningssleutel te krijgen voor Google-inloggen en (3) zelf aankopen te testen. Hij vertraagt de gesloten test niet.

---

## Wat je aan Claude teruggeeft

| Stap | Plak in de chat |
|---|---|
| A0 | "website live" (na merge + deploy) |
| A11 | Je juridische naam + adres (+ KvK-nummer als je dat hebt), of Gemini-facturering aan staat, en de MongoDB Atlas-regio |
| A2 (dag 2) | Hoeveel mensen lid zijn van de testgroep |
| A6 | De RevenueCat-sleutel `goog_…` |
| A7 | "Interne test staat erop" + de versiecode die Play toont |
| A8 | De SHA-1 van de **app-ondertekeningssleutel** + "beide OAuth-clients aangemaakt" |
| A10 | Een App-content-onderdeel dat niet in `app-content-antwoorden.md` staat (alleen als dat gebeurt) |
| B3 | "Gesloten test ingediend" |
| C2 | "Abonnementen actief, RevenueCat gekoppeld" + de status bij *Service Account Credentials* |
| C4 | De uitkomst van de rooktest; bij een fout de tekst van **Kopieer diagnose** of de foutmelding |
| D1 | De datum waarop de test live ging en het aantal aangemelde testers |
| E3 | Feedback van testers (WhatsApp, mail) |
| F1 | Het aantal aangemelde testers op de Dashboard-kaart |
| F2 / G2 | Datum aangevraagd / goedgekeurd / live, of de afwijzingsmail |
| Altijd | Elke mail van Google over een afwijzing of beleid: de hele tekst |

---

## Fase A: vandaag (wo 16 sep), ± 3 uur

### A0. Website live zetten (30 min incl. testen)

De Play-formulieren verwijzen naar `https://www.bijbelstudie.io/privacybeleid` en `/account-verwijderen`. Die moeten live de nieuwe versie tonen vóór je de gesloten test indient.

1. Op branch `levensboom` in `C:\Projectsijbelstudie` staan 3 ongepushte commits:
   - 2 van je andere Claude-sessie (commandopalet, wachtwoord wijzigen, account verwijderen op de website, Pro-gates, lescursor, feedback-limieten). Die sessie vraagt je ze eerst lokaal te testen.
   - `3d6fba25` van deze sessie: dagtekst, AI-meldingen, privacybeleid, `/account-verwijderen`, bewaartermijn-cron.
2. Lokaal testen: `npm run dev` → open `/privacybeleid`, `/account-verwijderen`, `/beheer/feedback` (filter **AI-antwoord gemeld**) en de onderdelen van de andere sessie.
3. Mergen en deployen (de website-regels: alleen jij doet dit):
   ```bash
   cd /c/Projects/bijbelstudie
   git checkout main && git pull
   git merge levensboom
   git push
   ```
   Let op: `hooks/useBibleData.ts` en `lib/book-mapping.ts` zijn ongecommitte wijzigingen van nog een andere sessie. Die gaan niet mee, zolang je ze niet zelf commit.
4. **Vercel** → project BijbelStudie → **Settings** → **Environment Variables**:
   - **`CRON_SECRET`** (Production) = een lange willekeurige waarde, bijv. uit `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`. Nodig voor de nieuwe dagelijkse bewaartermijn-cron. Hij zet ook je bestaande abonnement-reconcile-cron aan, die nu elke dag faalt omdat er geen geheim is.
   - **`RESEND_API_KEY`** (Production): ontbreekt nu, dus **wachtwoord-vergeten-mails worden in productie niet verstuurd**. Maak een sleutel in Resend → **API Keys** en voeg hem toe.
   - Daarna **Deployments** → laatste deploy → **Redeploy**.

✅ **Klaar als** `https://www.bijbelstudie.io/privacybeleid` "Laatst bijgewerkt: 16 september 2026" toont en `/account-verwijderen` bestaat.
**Plak in de chat:** "website live". Claude controleert de pagina's en deployt daarna de BijbelAPI.


### A1. Play Console-account controleren (5 min)

1. Open <https://play.google.com/console> met het Google-account van je ontwikkelaarsaccount.
2. Kijk op de startpagina (**Alle apps**) of er meldingen staan over **identiteitsverificatie**, **telefoonnummer/e-mail verifiëren** of **toegang tot een Android-apparaat bevestigen** ≈. Doe wat er gevraagd wordt (dat laatste gaat via de Play Console-app op een Android-telefoon).

✅ **Klaar als** er bovenaan geen rode of gele melding meer staat over je account.

### A2. Testers werven: nu beginnen (20 min)

Werf er **20** (12 is het minimum; er haken er altijd een paar af). Alleen mensen met een **Android-telefoon** en een **gewoon Gmail-account** (geen werk-, school- of Family Link-account). Beste bronnen: familie en vrienden, je kerk/bijbelstudiegroep, bestaande gebruikers van bijbelstudie.io. Geen betaalde "12 testers"-diensten: Google keurt dan af.

1. Ga naar <https://groups.google.com> → **Groep maken**.
2. **Naam:** `BijbelStudie testers` · **E-mailadres groep:** `bijbelstudie-testers` (neem een ander als dit bezet is) · **Groepsbeschrijving:** blok 5 uit `store-assets/google-play/testers-uitnodiging.md` → **Volgende**.
3. Privacy-instellingen:
   - **Wie kan zoeken naar de groep:** Alleen groepsleden
   - **Wie kan deelnemen aan de groep:** **Iedereen kan deelnemen**
   - **Wie kan gesprekken bekijken:** Groepsleden
   - **Wie kan posten:** Groepsbeheerders
4. **Groep maken**. Kreeg je groep een ander adres dan `bijbelstudie-testers`? Pas het dan aan in `testers-uitnodiging.md` en `abonnementen.md` (of vraag het Claude).
5. Stuur **bericht 1** (WhatsApp) of **e-mail 3** uit `testers-uitnodiging.md` naar iedereen. Maak een WhatsApp-groep "BijbelStudie testers" voor herinneringen.

✅ **Klaar als** het bericht naar minstens 20 mensen is verstuurd.
**Plak in de chat (dag 2):** hoeveel mensen lid zijn (groups.google.com → je groep → **Leden**).

### A3. App aanmaken (5 min)

1. Play Console → **Alle apps** → **App maken**.
2. **App-naam:** `BijbelStudie` · **Standaardtaal:** `Nederlands – nl-NL` · **App of game:** App · **Gratis of betaald:** **Gratis** (abonnementen mogen gewoon).
3. Vink alle drie de **Declaraties** aan → **App maken**.

✅ **Klaar als** je op het **Dashboard** van BijbelStudie staat, met de takenlijst "Je app instellen" ≈.

### A4. Betalingsprofiel (15 min + wachten op de bank)

Nu doen, want het bevestigen van je bankrekening duurt 1–5 werkdagen, en zonder betalingsprofiel kun je geen abonnementen maken.

1. Play Console → **Alle apps** → **Instellingen** → **Betalingsprofiel**. Staat er al een? Ga dan naar punt 4.
2. **Betalingsprofiel maken**:
   - **Land/regio:** Nederland (kan nooit meer veranderen)
   - **Bedrijfsnaam:** je eigen naam of je KvK-naam
   - **Adres:** fysiek adres (geen postbus)
   - **Primaire contactpersoon:** je naam en e-mail
   - **Website:** `https://www.bijbelstudie.io` · **Productcategorie:** Software/apps · **Support-e-mail:** `info@bijbelstudie.io` · **Naam op afschrift** ≈: `BIJBELSTUDIE`
3. **Indienen**.
4. **Betaalmethoden** ≈ → bankrekening toevoegen. Google stort een klein testbedrag; bevestig dat bedrag zodra het binnen is.
5. **Belastinginformatie** ≈: vul de Amerikaanse belastingvragen in (W-8BEN, Nederlandse particulier/eenmanszaak, geen activiteiten in de VS).

✅ **Klaar als** het betalingsprofiel bestaat (de bankverificatie mag nog lopen).

### A5. Store-instellingen en handelaarsstatus (10 min)

1. BijbelStudie → **Aantal gebruikers vergroten** → **Aanwezigheid in Google Play Store** → **Store-instellingen**.
2. **App-categorie** → **Bewerken** en **Contactgegevens** → **Bewerken**: vul in wat onder **5. Store-instellingen** in `store-assets/google-play/winkelvermelding.md` staat → **Opslaan**.
3. **Handelaar (EU):** Play Console → **Alle apps** → **Instellingen** → **Ontwikkelaarsaccount** ≈ → **Accountgegevens** ≈ (of zoek op `handelaar`). Verklaar dat je **handelaar** bent (je verkoopt abonnementen). Je adres, telefoon en e-mail worden in de EU **openbaar** getoond: gebruik een zakelijk adres/nummer als je dat liever hebt.

✅ **Klaar als** categorie, contactgegevens en handelaarsstatus zijn opgeslagen.

### A6. RevenueCat: Android-app en `goog_`-sleutel (5 min)

Dit kan al voordat er iets in Play staat, en Claude heeft de sleutel nodig voor de eerste echte build.

1. <https://app.revenuecat.com> → project **BijbelStudie** → **Project settings** → **Apps & providers** (≈ **Apps**) → **+ New** → **Google Play Store**.
2. **App name:** `BijbelStudie (Android)` · **Google Play package:** `com.bijbelstudie.app` → **Save**.
3. **API keys** → kopieer de **public SDK key** van deze app (begint met `goog_`).

✅ **Klaar als** je een sleutel hebt die met `goog_` begint.
**Plak in de chat:** de `goog_…`-sleutel. Claude zet hem als GitHub-secret en start de build.

### A7. Eerste AAB naar de interne test (10 min)

> **Wacht op Claude:** de melding dat `store-assets/google-play/builds/bijbelstudie-1.1.1-101.aab` klaarstaat (de eerste GitHub-build, met AI-melden; alleen de RevenueCat-sleutel zit er nog niet in). Gebruik die in plaats van het lokale bestand hieronder. Alleen als Claude meldt dat de GitHub-build mislukt is, gebruik je de lokale build 1.0.7 (99).

Dit gebruikt de build 1.0.7 (99) die vandaag lokaal is gemaakt. Hij hoeft niet perfect te zijn: de interne test heeft geen beoordeling. Het doel is dat Play je app "kent" (abonnementen worden daarna mogelijk) en dat Google zijn ondertekeningssleutel aanmaakt.

1. BijbelStudie → **Testen en releasen** → **Testen** → **Interne tests**.
2. Tab **Testers** → **Mailinglijst maken** → naam `Intern` → je eigen Gmail (het account in de Play Store op je Android-telefoon) → **Wijzigingen opslaan** → vink `Intern` aan → **Feedback-URL of e-mailadres:** `info@bijbelstudie.io` → **Wijzigingen opslaan**.
3. **Nieuwe release maken** (rechtsboven).
4. **App-ondertekening van Play:** laat de standaard staan (**Door Google gegenereerde sleutel gebruiken** ≈). Upload **geen** eigen sleutel.
5. **App-bundels** → **Uploaden** → kies `C:\Projects\bijbelstudie-app\bijbelstudie_mobile\build\app\outputs\bundle\release\app-release.aab`.
   (Staat dat bestand er niet? Sla stap A7 en A8b over en doe ze in B2 met de GitHub-build.)
6. Wacht tot de rij **99 (1.0.7)** toont. **Releaseopmerkingen:** blok A uit `store-assets/google-play/release-notes.md`.
7. **Volgende** → fouten blokkeren, waarschuwingen mogen → **Opslaan en publiceren** ≈ (of **Opslaan** → **Release starten voor interne tests** ≈).

Weigert Play het publiceren omdat er nog setup-taken openstaan? Doe dan eerst A10 en probeer opnieuw.

✅ **Klaar als** de release onder Interne tests de status **Beschikbaar voor interne testers** ≈ heeft.
**Plak in de chat:** "Interne test staat erop, versiecode <101 of 99>".

### A8. Google-inloggen: twee Android OAuth-clients (15 min)

**A8a. Client voor de uploadsleutel**

1. Open <https://console.cloud.google.com/auth/clients> en kies in de projectkiezer (linksboven) het project met **projectnummer `1005113136089`**. Je herkent het aan de webclient `1005113136089-24a9hvcjkm2qv8r0tll8n9r424gnaf2l` in de lijst **Clients**.
2. Links **Audience**: *Publishing status* moet **In production** zijn. Staat er *Testing*? Klik **Publish app**.
3. **Clients** → **+ Create client** → **Application type:** Android.
4. **Name:** `BijbelStudie Android – upload key` · **Package name:** `com.bijbelstudie.app` · **SHA-1:** `FF:2C:27:A0:E2:EF:F0:2E:C6:A4:5E:AC:F9:2C:77:8A:AC:14:E7:7E` → **Create**. Het client-ID hoef je nergens in te vullen.

**A8b. Client voor Google's ondertekeningssleutel** (na A7)

5. Play Console → BijbelStudie → **Testen en releasen** → **App-integriteit** → **App-ondertekening van Play** ≈ (in nieuwere consoles: **Beveiligd met Play** → **Play Store-distributie** ≈ → **App-ondertekening**).
6. Controleer: de kaart **Certificaat van uploadsleutel** ≈ toont SHA-1 `FF:2C:27:A0:…:7E`. Zo niet: stop en meld het in de chat.
7. Kopieer de **SHA-1** van de kaart **Certificaat van app-ondertekeningssleutel** ≈.
8. Google Cloud → **Clients** → **+ Create client** → Android → **Name:** `BijbelStudie Android – Play signing` · **Package name:** `com.bijbelstudie.app` · **SHA-1:** de gekopieerde waarde → **Create**.

✅ **Klaar als** er onder **Clients** twee Android-clients staan met package `com.bijbelstudie.app`.
Foutmelding *"package name and fingerprint are already in use"*? Dan bestaat dat paar al in een ander Cloud-project: plak de melding in de chat.
**Plak in de chat:** de SHA-1 van de app-ondertekeningssleutel + "beide OAuth-clients aangemaakt".

### A9. Service account voor RevenueCat (20 min)

Nu doen: Google heeft soms tot 36 uur nodig voordat deze toegang werkt.

**In Google Cloud** (zelfde project `1005113136089`):

1. <https://console.cloud.google.com/apis/library> → zoek en klik **Enable** bij: **Google Play Android Developer API**, **Google Play Developer Reporting API**, **Cloud Pub/Sub API**.
2. **IAM & Admin** → **Service Accounts** → **+ Create service account** → naam `revenuecat-play` → **Create and continue** → rollen **Pub/Sub Editor** en **Monitoring Viewer** → **Continue** → **Done**.
3. Klik op het nieuwe account → tab **Keys** → **Add key** → **Create new key** → **JSON** → **Create**. Verplaats het gedownloade bestand naar `C:\Users\alexl\.android-keys\revenuecat-play-service-account.json` (niet in de repo, niet in de chat).
4. Kopieer het e-mailadres van het service account (`revenuecat-play@….iam.gserviceaccount.com`).

**In Play Console:**

5. **Alle apps** → **Gebruikers en rechten** → **Nieuwe gebruikers uitnodigen** → e-mailadres = het service account.
6. Tab **Accountrechten** ≈, vink aan:
   - **App-gegevens bekijken en bulkrapporten downloaden (alleen-lezen)**
   - **Financiële gegevens, bestellingen en reacties op opzeggingsenquête bekijken**
   - **Bestellingen en abonnementen beheren**
   - **Aanwezigheid in Google Play Store beheren**
7. **Gebruiker uitnodigen** → **Uitnodiging verzenden** ≈.

**In RevenueCat:**

8. Project **BijbelStudie** → de app **BijbelStudie (Android)** → **Service Account Credentials JSON** → upload het JSON-bestand → **Save**.

✅ **Klaar als** het service account in **Gebruikers en rechten** staat en RevenueCat het JSON-bestand heeft (status *Valid credentials* mag nog even duren).

### A10. App-content invullen (45 min)

1. BijbelStudie → **Controleren en verbeteren** → **Beleid en programma's** → **App-content**.
2. Werk alle onderdelen af met `store-assets/google-play/app-content-antwoorden.md` (staat in dezelfde volgorde als in de console). Voor **App-toegang** heb je het wachtwoord van `applereview@mail.com` nodig: hetzelfde als in App Store Connect → App Review Information.
3. **Gegevensveiligheid** kun je nu al invullen; Claude controleert het tegen het nieuwe privacybeleid en laat weten als er een regel moet veranderen.
4. Bij **Privacybeleid** en **Link voor accountverwijdering**: de URL's werken pas goed na **A0**.

### A11. Gegevens voor het privacybeleid (5 min)

Het nieuwe privacybeleid mist nog een paar dingen die alleen jij weet. **Plak in de chat:**
- je juridische naam, adres (plaats is genoeg als je geen bedrijfsadres wilt tonen; Google toont bij betaalde apps sowieso het adres uit je betalingsprofiel) en KvK-nummer als je dat hebt;
- of **facturering aan staat** voor het Google Cloud-project van de Gemini API (het beleid zegt dat vragen niet voor training gebruikt worden; dat klopt alleen met betaalde facturering);
- de **regio van je MongoDB Atlas-cluster** (Atlas → Database → cluster → regio, bijv. `AWS / Frankfurt (eu-central-1)`).

✅ **Klaar als** het tabblad **Vereist aandacht** leeg is.
Staat er een onderdeel dat niet in het bestand voorkomt? **Plak in de chat:** de titel ervan.

---

## Fase B: gesloten test indienen (do 17 sep)

> **Wacht op Claude:** de melding **"GO gesloten test"**. Die komt als (1) het nieuwe privacybeleid en `/account-verwijderen` live staan, (2) build 1.1.1 met "AI-antwoord melden" en jouw `goog_`-sleutel klaarstaat in `store-assets/google-play/builds/`, (3) de afbeeldingen klaar zijn en (4) Gegevensveiligheid is gecontroleerd. Fase C mag je al eerder doen.

### B1. Winkelvermelding en afbeeldingen (20 min)

1. BijbelStudie → **Aantal gebruikers vergroten** → **Aanwezigheid in Google Play Store** → **Store-vermeldingen** → **Primaire Store-vermelding** ≈.
2. Plak **App-naam**, **Korte beschrijving** en **Volledige beschrijving** uit `store-assets/google-play/winkelvermelding.md`.
3. Upload onder **Grafische items**: **App-icoon**, **Functieafbeelding** en **Screenshots telefoon** uit `store-assets/google-play/graphics/` (icoon + functieafbeelding) en `store-assets/google-play/phone/` (8 screenshots). Screenshots in de volgorde van de bestandsnamen.
4. **Opslaan** (onderaan).

✅ **Klaar als** de Dashboard-taak "Store-vermelding instellen" ≈ is afgevinkt.

### B2. Build 1.1.1 uploaden (5 min)

1. Claude meldt de bestandsnaam, bijvoorbeeld `store-assets/google-play/builds/bijbelstudie-1.1.1-101.aab`.
2. **Testen en releasen** → **Testen** → **Interne tests** → **Nieuwe release maken** → **Uploaden** → dat `.aab`-bestand. **Releaseopmerkingen:** blok A uit `release-notes.md` → **Volgende** → **Opslaan en publiceren** ≈.
3. (Heb je A7 overgeslagen? Doe nu A8b.)

✅ **Klaar als** de nieuwe versiecode (101 of hoger) onder Interne tests beschikbaar is.

Heb je de build liever zelf van GitHub? **Actions** → workflow **Android Build (signed AAB for Google Play)** → de bovenste groene run → onderaan **Artifacts** → `bijbelstudie-<versie>-<code>-aab` → zip uitpakken.

### B3. Gesloten test instellen en indienen (15 min)

1. **Testen en releasen** → **Testen** → **Gesloten test** → track **Gesloten test - Alpha** ≈ → **Track beheren**.
2. Tab **Landen/regio's** → **Landen/regio's toevoegen** → **Nederland**, **België** en elk land waar een tester zijn Play-account heeft (bijv. Duitsland) → **Toevoegen** → **Opslaan**.
3. Tab **Testers** → **Google Groepen** → `bijbelstudie-testers@googlegroups.com` → **Feedback-URL of e-mailadres:** `info@bijbelstudie.io` → **Wijzigingen opslaan**.
4. **Nieuwe release maken** → **Toevoegen uit bibliotheek** → de build uit B2 (hoogste versiecode) → **Toevoegen aan release** ≈ → **Releaseopmerkingen:** blok A uit `release-notes.md` → **Volgende** → **Opslaan**.
5. Links **Publicatieoverzicht** → controleer dat **Beheerde publicatie** **uit** staat → **Wijzigingen ter beoordeling versturen** ≈ → bevestigen.

✅ **Klaar als** het Publicatieoverzicht **In behandeling** ≈ toont.
**Plak in de chat:** "Gesloten test ingediend".

Blokkeert Play het versturen met een lijst open taken? Werk die af (meestal een vergeten onderdeel uit A5, A10 of B1) en probeer opnieuw.

---

## Fase C: terwijl Google beoordeelt (do 17 – ma 21 sep)

### C1. Abonnementen aanmaken (20 min)

Kan zodra het betalingsprofiel bestaat (A4) en er een AAB staat (A7 of B2).

1. BijbelStudie → **Inkomsten genereren met Play** → **Producten** → **Abonnementen** → **Abonnement maken**.
2. Maak **beide** abonnementen precies zoals in `store-assets/google-play/abonnementen.md`: product-ID, naam, voordelen, beschrijving, basisabonnement, prijs → **Opslaan** → **Activeren**. Kopieer de ID's: een verkeerd getypte product-ID is voor altijd bezet.

✅ **Klaar als** `bijbelstudie_pro_monthly` en `bijbelstudie_pro_yearly` elk een basisabonnement met status **Actief** hebben, en NL/BE € 9,99 en € 69,99 tonen.

### C2. RevenueCat koppelen (15 min)

1. **Realtime meldingen:** RevenueCat → app **BijbelStudie (Android)** → **Google developer notifications** ≈ → **Connect to Google** → kies/maak een Pub/Sub-topic → kopieer de topicnaam (`projects/…/topics/…`).
2. Play Console → BijbelStudie → **Inkomsten genereren met Play** → **Instellingen voor inkomsten genereren** ≈ → **Realtime ontwikkelaarsmeldingen** ≈ → **Meldingen inschakelen** ≈ → **Onderwerpnaam** ≈ = de topicnaam → **Testmelding verzenden** ≈ → **Wijzigingen opslaan**. In RevenueCat hoort *Last received: just now* te verschijnen.
3. RevenueCat → **Product catalog** → **Products** → **+ New** (of **Import**) → Store **Google Play** → de twee producten uit de RevenueCat-tabel in `abonnementen.md`.
4. **Entitlements** → `pro` → **Attach** → beide Play-producten.
5. **Offerings** → `default` → package `$rc_monthly` en `$rc_annual` → **Edit** → Google Play-product toevoegen volgens `abonnementen.md` → **Save**. Laat de App Store-producten staan.

Toont RevenueCat bij de credentials na 36 uur nog steeds een fout? Open in Play Console een abonnement, verander één letter in de beschrijving, **Opslaan**, zet hem terug, **Opslaan**.

✅ **Klaar als** beide Play-producten aan `pro` en aan `default` hangen.
**Plak in de chat:** "Abonnementen actief, RevenueCat gekoppeld" + de credentials-status (bijv. *Valid credentials*).

### C3. Licentietests (3 min)

1. Play Console → **Alle apps** → **Instellingen** → **Licentietests**.
2. Voeg je eigen Gmail toe, en `bijbelstudie-testers@googlegroups.com` als het veld dat accepteert (dan kunnen testers Pro gratis proberen met een testkaart).
3. **Licentiereactie** ≈: `RESPOND_NORMALLY` → **Wijzigingen opslaan**.

✅ **Klaar als** je eigen Gmail in de lijst staat.
Accepteert het veld de groep niet? Meld het in de chat; Claude past dan de testersberichten aan.

### C4. Rooktest op je eigen telefoon (30 min)

1. **Interne tests** → tab **Testers** → **Link kopiëren** (onder *Deelnemen via internet* ≈) → open hem op je Android-telefoon → **Uitnodiging accepteren** ≈ → installeer via de Play Store. (Nog "niet beschikbaar"? Wacht 15–60 min. Controleer dat de Play Store op je tester-account staat.)
2. Vink af:
   - [ ] Nieuw account registreren lukt en je komt op Start.
   - [ ] **Inloggen met Google** werkt (kan pas 5–30 min na A8b).
   - [ ] Lezen, commentaar, Grondtekst, notitie maken, zoeken, vraag aan de AI-assistent, en een AI-antwoord **melden**.
   - [ ] Herinnering aanzetten → Android vraagt meldingstoestemming → melding komt binnen.
   - [ ] Paywall toont **€ 9,99 / maand** en **€ 69,99 / jaar** en noemt **Google Play**, niet Apple.
   - [ ] Jaarabonnement kopen met **Testkaart, altijd goedgekeurd** → Pro gaat aan → blijft aan na app afsluiten en opnieuw openen.
   - [ ] App verwijderen, opnieuw installeren, inloggen → **Aankopen herstellen** → Pro blijft.
   - [ ] Inloggen met `applereview@mail.com` → Pro actief.
   - [ ] **Account verwijderen** werkt (met een wegwerpaccount, **niet** het reviewer-account).

✅ **Klaar als** alles is afgevinkt.
**Plak in de chat:** wat niet lukte, met de tekst van **Kopieer diagnose** (paywall) of de exacte foutmelding (bijv. `ApiException: 10`).

### C5. Inloggegevens voor Google's robottest (2 min, optioneel)

**Testen en releasen** → **Testen** → **Pre-lanceringsrapport** ≈ → **Instellingen** → **Inloggegevens** ≈ → `applereview@mail.com` + wachtwoord → **Opslaan**. Claude leest daarna de crashresultaten niet zelf; kijk na een uur bij **Pre-lanceringsrapport** → **Overzicht** en plak crashes in de chat.

---

## Fase D: gesloten test live (verwacht ± ma 21 sep)

### D1. Iedereen dezelfde dag aanmelden

Je krijgt een mail, of het **Publicatieoverzicht** toont **Wijzigingen gepubliceerd** ≈.

1. Stuur **bericht 2** (WhatsApp) of **e-mail 4** uit `testers-uitnodiging.md` naar iedereen die lid is van de groep.
2. Vraag om een screenshot van de geïnstalleerde app. Jaag 's avonds iedereen na die nog niet gereageerd heeft.
3. Kijk op het **Dashboard** naar de kaart over productietoegang ≈: daar staat het aantal aangemelde testers en het aantal dagen.

✅ **Klaar als** de Dashboard-kaart **12 of meer** aangemelde testers toont.
**Plak in de chat:** de datum dat de test live ging + het aantal aangemelde testers.

---

## Fase E: de 14 dagen (± ma 21 sep – ma 5 okt)

### E1. Testers actief houden

Stuur de herinneringen uit blok 6 van `testers-uitnodiging.md` op **dag 1, 3, 7, 10 en 13** in de WhatsApp-groep. Google kijkt bij de aanvraag of testers de app echt gebruikten.

### E2. Updates van Claude doorzetten (5 min per update)

Claude meldt: bestandsnaam in `store-assets/google-play/builds/` + releaseopmerkingen.

1. **Gesloten test** → **Track beheren** → **Nieuwe release maken** → **Uploaden** → het `.aab`-bestand → releaseopmerkingen plakken → **Volgende** → **Opslaan**.
2. **Publicatieoverzicht** → **Wijzigingen ter beoordeling versturen** ≈. Updates reset de 14 dagen **niet**.

Plan minstens één update rond dag 7: Google vraagt bij de aanvraag wat je op basis van feedback hebt veranderd.

### E3. Feedback doorsturen

**Plak in de chat:** wat testers je via WhatsApp of mail melden. Feedback uit de app zelf (Profiel → Feedback geven) haalt Claude zelf op.

**Nooit doen tijdens de 14 dagen:** de track **onderbreken** ≈, de track verwijderen, de Google Group vervangen door een mailinglijst, of testers uit de groep halen. Dan kunnen aanmeldingen vervallen en begint de klok opnieuw.

✅ **Klaar als** de Dashboard-kaart 14 dagen met ≥ 12 testers toont en de knop **Productietoegang aanvragen** klikbaar is.

---

## Fase F: productietoegang aanvragen (± ma 5 okt)

### F1. Cijfers aan Claude geven

**Plak in de chat:** het aantal aangemelde testers op de Dashboard-kaart. Claude vult de placeholders in `store-assets/google-play/productietoegang-antwoorden.md` in en meldt "productietoegang-antwoorden ingevuld".

### F2. Aanvragen (15 min)

1. **Dashboard** → **Productietoegang aanvragen**.
2. Plak de antwoorden uit `productietoegang-antwoorden.md` (drie delen, Engels). Kies bij de keuzevragen wat in het bestand staat.
3. **Indienen**.

✅ **Klaar als** het Dashboard toont dat je aanvraag in behandeling is.
**Plak in de chat:** "aangevraagd". Na de mail van Google: "goedgekeurd", of de hele afwijzingsmail. Bij een afwijzing: laat de gesloten test gewoon doorlopen; Claude maakt een plan voor 14 extra dagen.

---

## Fase G: productierelease (dezelfde dag als de goedkeuring)

### G1. Release maken (10 min)

1. **Testen en releasen** → **Productie**.
2. Tab **Landen/regio's** → **Landen/regio's toevoegen** → **Nederland** en **België** (optioneel ook Suriname, Aruba, Curaçao, Sint-Maarten, Caribisch Nederland) → **Toevoegen** → **Opslaan**.
3. **Nieuwe release maken** → **Toevoegen uit bibliotheek** → de **hoogste** versiecode uit de gesloten test.
4. **Releaseopmerkingen:** blok C uit `release-notes.md`.
5. **Volgende** → **Uitrolpercentage** ≈: **100%** (eerste release; er zijn nog geen gebruikers om te beschermen) → **Opslaan**.
6. **Publicatieoverzicht** → **Beheerde publicatie** uit → **Wijzigingen ter beoordeling versturen** ≈.

✅ **Klaar als** het Publicatieoverzicht **In behandeling** ≈ toont.

### G2. Live

Na goedkeuring (meestal 1–3 dagen) staat de app op `https://play.google.com/store/apps/details?id=com.bijbelstudie.app`. Zoeken op naam werkt 1–2 dagen later. Laat de gesloten test gewoon doorlopen: dat is je bètakanaal.

✅ **Klaar als** de link hierboven de app toont op een telefoon die geen tester is.
**Plak in de chat:** "live". Claude zet de Google Play-badge op de website.

---

## App Store 1.1.1: screenshots uploaden (15 min)

> **Wacht op Claude:** melding dat `store-assets/app-store-1.1.1/` klaar is.

1. <https://appstoreconnect.apple.com> → **Apps** → **BijbelStudie** → links onder iOS-app de versie **1.1.1** (bestaat die nog niet: **+** naast *iOS-app* → `1.1.1`).
2. Scroll naar **Previews and Screenshots** ≈ (*Voorvertoningen en screenshots*).
3. Kies per tabblad het formaat dat overeenkomt met een submap in `store-assets/app-store-1.1.1/` (bijv. iPhone **6,9"**; iPad **13"** alleen als er een iPad-map is).
4. Verwijder de oude screenshots (vuilnisbak bij hover, of **Delete All** ≈) → sleep de bestanden uit die submap erin, in de volgorde van de bestandsnamen.
5. **App Previews** (video): optioneel, overslaan.
6. **Save** (rechtsboven).

✅ **Klaar als** elk formaat de nieuwe screenshots toont en er geen waarschuwing over ontbrekende screenshots staat. Build kiezen en indienen doe je zoals altijd, zodra Claude meldt dat TestFlight-build 1.1.1 klaarstaat.

---

## Als het misgaat (alleen wat jij tegenkomt)

| Wat je ziet | Wat je doet |
|---|---|
| Upload: *versiecode is al gebruikt* | Vraag Claude om een nieuwe build (niets zelf bouwen). |
| Upload: *ondertekend met de verkeerde sleutel* / *foutopsporingsmodus* | Stop. Plak de melding in de chat. |
| Google-inloggen: `ApiException: 10`, `DEVELOPER_ERROR`, *Developer console is not set up correctly* | Controleer dat beide clients uit A8 bestaan met package `com.bijbelstudie.app` in project `1005113136089`; wacht 30 min; telefoon → Instellingen → Apps → Google Play-services → Opslag → **Cache wissen**. Nog steeds fout: plak de melding in de chat. |
| Paywall toont `—` in plaats van prijzen | Paywall → **Details** → **Kopieer diagnose** → plak in de chat. (Vaak: credentials nog niet geldig, abonnement niet **Actief**, of app niet via Play geïnstalleerd.) |
| Testaankoop kost echt geld | Je account staat niet in **Licentietests** (C3). Aankoop terugbetalen via Play Console → **Bestellingbeheer** ≈. |
| Tester: *app niet beschikbaar* / kan niet installeren | Verkeerd Google-account actief in de Play Store; niet in de groep; land niet in **Landen/regio's** (B3); werk-/schoolaccount; of de test is net pas live (paar uur wachten). |
| Mail van Google: afwijzing (Gegevensveiligheid, App-toegang, AI-content, abonnementen, accountverwijdering) | Plak de **hele** mail in de chat. Niets zelf aanpassen voordat Claude antwoordt. |
| Reviewer kan niet inloggen | Plak de mail in de chat; Claude herstelt het reviewer-account, daarna **App-toegang** → **Beheren** → **Opslaan** → opnieuw versturen. |

---

## Checklist

**Fase A – wo 16 sep**
- [ ] A0 Website gemerged + gedeployd, `CRON_SECRET` en `RESEND_API_KEY` in Vercel *(→ chat)*
- [ ] A1 Account zonder meldingen
- [ ] A2 Google Group + bericht 1 naar 20 mensen *(dag 2: aantal leden → chat)*
- [ ] A3 App aangemaakt
- [ ] A4 Betalingsprofiel + bankrekening
- [ ] A5 Store-instellingen + handelaarsstatus
- [ ] A6 RevenueCat Android-app *(goog_-sleutel → chat)*
- [ ] A7 AAB 101 (of 99) op Interne test *(→ chat)*
- [ ] A8 Twee Android OAuth-clients *(ondertekenings-SHA-1 → chat)*
- [ ] A9 Service account (Cloud + Play Console + RevenueCat)
- [ ] A10 App-content: "Vereist aandacht" leeg
- [ ] A11 Naam/adres/KvK, Gemini-facturering, Atlas-regio *(→ chat)*

**Fase B – do 17 sep** (na "GO gesloten test")
- [ ] B1 Winkelvermelding + afbeeldingen
- [ ] B2 Build 1.1.1 op Interne test
- [ ] B3 Gesloten test ingediend *(→ chat)*

**Fase C – tijdens beoordeling**
- [ ] C1 Twee abonnementen **Actief**
- [ ] C2 RTDN + producten aan `pro` en `default` *(→ chat)*
- [ ] C3 Licentietests
- [ ] C4 Rooktest *(uitkomst → chat)*
- [ ] C5 Pre-lanceringsrapport-inlog (optioneel)

**Fase D–G**
- [ ] D1 Test live, bericht 2 verstuurd, ≥ 12 aangemeld *(datum + aantal → chat)*
- [ ] E1 Herinneringen dag 1, 3, 7, 10, 13
- [ ] E2 Updates van Claude geüpload
- [ ] F2 Productietoegang aangevraagd *(→ chat)*
- [ ] G1 Productierelease ingediend
- [ ] G2 Live *(→ chat)*

**iOS**
- [ ] App Store 1.1.1-screenshots geüpload
