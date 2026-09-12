# Handoff: BijbelStudie — schermherontwerp

## Overview

Een herontworpen set schermen voor de BijbelStudie Flutter-app (`AlexLamper/bijbelstudie-app`, branch `main`, root `bijbelstudie_mobile/lib`). Zeven schermen zijn nieuw ontworpen; vijf zijn een 1:1 weergave van wat er al staat en dienen alleen als referentie voor stijl en consistentie — die hoeven **niet** opnieuw gebouwd te worden.

Doel van het herontwerp: de Studies-pagina had te veel concurrerende secties en geen duidelijke hiërarchie. De nieuwe set geeft één primaire actie per scherm, één accentkleur, en haalt sierelementen weg die geen informatie dragen.



## Alleen layout en weergave — niet de werking

Dit is een **herontwerp van de presentatielaag**. Alles wat vandaag werkt, moet daarna precies zo blijven werken. Verander niets aan:

- **datamodellen, repositories, services en API-aanroepen** — de schermen tonen dezelfde velden uit dezelfde bronnen;
- **state-logica, providers en business rules** — voortgang, XP, reeks, badges, vergrendelde lessen en abonnementstatus worden berekend zoals nu;
- **routing, navigatie en deeplinks** — met één uitzondering: het nieuwe scherm *Studies · alle boeken*, dat als extra route op de studies-stack komt;
- **opslag, synchronisatie, offline gedrag en caching**;
- **authenticatie, rechten en de admin-afscherming**;
- **bestaande widgets die al goed werken** — hergebruik ze liever dan ze te vervangen.

Wat wél mag veranderen: widgetboom en layout binnen een scherm, spacing, kleur, typografie, iconen, kopteksten en de volgorde waarin bestaande onderdelen op het scherm staan.

Twee gevallen waarin de UI toch nieuwe data nodig heeft — voeg die toe als **lees-alleen afgeleide** van wat er al is, zonder het bestaande model te wijzigen:

1. een voortgangsstatus per bijbelboek (afgerond / bezig / nog niet) voor het boekenoverzicht;
2. het aantal notities en markeringen van het geopende hoofdstuk, voor de kop van de lezer.

Als een ontwerpkeuze hieronder botst met bestaand gedrag: **het gedrag wint.** Meld het en pas het ontwerp aan, ga niet de werking herschrijven om de mock te laten kloppen. Verwijder ook geen bestaande functie omdat die niet in een mock voorkomt — de mocks tonen één toestand van een scherm, niet de volledige functieset.

## Scope — wat wel en wat niet

Pas **alleen** deze zeven schermen aan:

| # | Scherm | Bestand |
| --- | --- | --- |
| 1 | Bijbel (lezer) | `features/bible/present/read_screen.dart` |
| 2 | Studie (commentaar) | `features/commentary/present/commentary_pane.dart` |
| 3 | Studies · Ontdek | `features/studies/present/studies_screen.dart` |
| 4 | Studies · alle boeken | nieuw scherm, gevoed door `core/data/bible_books.dart` |
| 5 | Studie-detail | `features/studies/present/study_detail_screen.dart` |
| 6 | Les afgerond | `features/levensboom/present/`, `features/study/present/` |
| 7 | Notities | `features/notes/present/` |

**Laat deze vijf schermen ongemoeid.** Ze zien er goed uit zoals ze nu zijn en staan alleen in dit pakket als stijlreferentie, zodat de zeven nieuwe schermen ernaast niet uit de toon vallen:

- Start (`features/dashboard/present/`)
- Profiel (`features/profile/present/profile_screen.dart`)
- Mijn voortgang (`features/levensboom/present/`)
- Instellingen
- Profielmenu (`features/profile/present/profile_menu_sheet.dart`)

Als iets in die vijf schermen niet klopt met wat hieronder staat, wint het bestaande scherm — niet dit document.

## About the Design Files

De bestanden in dit pakket zijn **ontwerpreferenties, gemaakt in HTML**. Het zijn prototypes die laten zien hoe het eruit moet zien en zich moet gedragen — geen productiecode om over te nemen. De opdracht is om deze ontwerpen **na te bouwen in Flutter**, in de bestaande structuur van `bijbelstudie_mobile/`, met de bestaande widgets, thema en routing van het project.

Concreet betekent dat:

- Gebruik `core/theme/app_theme.dart` voor kleur en typografie. Voeg tokens toe aan het thema als er iets ontbreekt; schrijf geen losse hexwaarden in schermcode.
- Gebruik bestaande widgets uit `core/ui/app_widgets.dart` (kaart, knop, pill) in plaats van nieuwe te maken.
- Gebruik `Icons.*` uit het Material-icoonpakket. De HTML tekent die iconen na met SVG-paden; in Flutter gebruik je het echte icoon (namen staan hieronder per scherm).
- De boom-, versscène- en badge-illustraties worden in de app runtime getekend (`TreeView` / `VerseScenePainter` / `mini_tree.dart`). In de HTML zijn dat benaderingen met gradiënten. **Neem de HTML-benadering niet over** — gebruik de bestaande painters.

## Fidelity

> Hifi geldt voor **hoe het eruitziet**. Voor hoe het werkt is dit document geen bron — zie “Alleen layout en weergave” hierboven.


**High-fidelity.** Kleuren, typografie, spacing, radii en copy zijn definitief en staan hieronder exact. Bouw de UI pixel-nauwkeurig na met de bestaande Flutter-widgets. Twee dingen zijn expliciet géén hifi: de runtime-getekende illustraties (zie hierboven) en de studiebanners, die van de server komen (`study_banner.dart`, met de teal → `#0F172A` fallback).

De HTML rendert op een frame van **390 × 844** (iPhone-maat, logische pixels). Alle px-waarden hieronder zijn logische pixels en vertalen 1:1 naar Flutter's `double`.

---

## Design Tokens

### Kleur

| Rol | Hex | Gebruik |
| --- | --- | --- |
| `teal` (primary) | `#0D9488` | knoppen, actieve pill, actieve tab, links, voortgang, actief tabbalkitem |
| `tealDark` | `#0F766E` | gradiëntstart banners, kop boven boekgroepen |
| `tealSoft` | `#CCFBF1` | tegel "bezig", versstreep in notities |
| `tealWash` | `rgba(13,148,136,.10)` | icoonvakjes achter een teal glyph |
| `tealFaint` | `#F0FDFA` | icoonvak op Start |
| `ink` | `#111827` | koppen, primaire tekst |
| `inkBody` | `#374151` | lopende tekst, inactief icoon in de werkbalk |
| `inkMuted` | `#6B7280` | secundaire tekst, versfragment, inactief tabbalklabel |
| `inkFaint` | `#9CA3AF` | meta (datum, telling), placeholders, versnummers |
| `line` | `#E5E7EB` | randen, hairlines, lege voortgangsbalk |
| `lineSoft` | `#F3F4F6` | tegel "nog niet", zoekveld, segment-achtergrond, citaatblok |
| `surface` | `#FFFFFF` | alle schermachtergronden |
| `success` | `#059669` | afgeronde les, reeksteller |
| `successSoft` | `#ECFDF5` | pill "Pro via web" |
| `warn` | `#EA580C` | reeks-pill tekst, hart in versscène |
| `warnSoft` | `#FFF7ED` | pill "dagen reeks" |
| `gold` | `#CA9A16` | niveau-ring en niveau-pill op voortgang |
| `danger` | `#DC2626` | Uitloggen |
| `badge` | `#7C3AED` op `#F5F3FF` | badge-ringen op profiel |
| `bannerEnd` | `#0F172A` | eindkleur bannergradiënt |

Bannergradiënt: `linear-gradient(135deg, #0F766E, #0F172A)`; variant `#0D9488 → #0F172A`.
Avondscène (Start / voortgang): `linear-gradient(#4B3A63 0%, #7E5E6E 45%, #C88463 100%)`; heuvels `#3F7A4E` en `#2F6142`, stam `#5B4330`, kroon `#3E6B45` / `#4B7C50`.

### Typografie

Twee families, zoals in `app_theme.dart`: **Inter** voor UI, **Lora** (serif) voor bijbeltekst en versfragmenten.

| Rol | Stijl |
| --- | --- |
| Schermtitel groot | Inter 28 / 700, letter-spacing −0.5 |
| Schermtitel (appbar) | Inter 16–19 / 600 |
| Sectiekop | Inter 16–17 / 700 |
| Groepskop (caps) | Inter 11–11.5 / 600, letter-spacing 1.0–1.3, uppercase, `inkFaint` (teal op voortgang) |
| Lijsttitel | Inter 14.5–15 / 600 |
| Body | Inter 14–15.5 / 400, line-height 1.6–1.75 |
| Meta | Inter 12–12.5 / 400, `inkFaint` |
| Pill / chip | Inter 12.5 / 500–600 |
| Knoplabel | Inter 15 / 600 |
| Bijbeltekst | Lora 17 / 400, line-height 1.75 |
| Versfragment (notitie) | Lora 13 / 400, line-height 1.6, `inkMuted` |
| Versnummer | Inter 11 / 600, `inkFaint`, superscript |

Minimum in de hele set: 10px (alleen het woord "Wissel", uppercase met letter-spacing). Lopende tekst nergens onder 12px.

### Spacing, radius, elevatie

- Horizontale schermmarge: **16**. Bannerkop en tijdlijn: **20**.
- Verticale ritme: 8 / 12 / 14 / 18 / 22.
- Radius: pill `999`, tegel `8–10`, kaart `14–16`, knop `12`, sheet `20` (alleen boven).
- Randen: 1px `line`; geselecteerde tegel 2px `teal`; niveau-ring 3–4px `gold`.
- Schaduw: alleen op de FAB — `0 6px 16px rgba(13,148,136,.35)`. Kaarten gebruiken een rand, geen schaduw.
- Tabbalk: hoogte **92** inclusief `padding-bottom: 14` (safe area). Icoon 21, label 11–12.
- Raakvlakken: elke tikbare rij ≥ 44 hoog; tegels in het boekenoverzicht 48.

---

## Screens / Views

De canvas toont ze van links naar rechts in appvolgorde. Nieuw = bouwen. Bestaand = alleen referentie.

### 1. Start — *bestaand, referentie*
`features/dashboard/present/`. Ongewijzigd overgenomen. Gebruik als ijkpunt voor kaartstijl (rand 1px `line`, radius 16, padding 14) en voor de avondscène.

### 2. Bijbel (lezer) — **nieuw**
`features/bible/present/read_screen.dart`

**Doel:** een hoofdstuk lezen, met de leesgereedschappen binnen bereik en één tik naar de studiekant.

**Kop** (wit, onder de statusbalk, `padding: 6 16 0`):
- Rij 1: links de hoofdstuktitel "Genesis 5" (Inter 19/700, ls −0.3) met `Icons.keyboard_arrow_down` (15) ernaast, daaronder "Statenvertaling" (Inter 11.5/400, `inkFaint`). Rechts een segmented control.
- Segmented control: achtergrond `lineSoft`, radius 10, padding 3. Segmenten `padding: 7 15`, radius 8. Actief = `teal` vlak met witte tekst (Inter 13/600); inactief = `inkMuted`, Inter 13/500. Labels: **Bijbel** | **Studie**.
- Rij 2 (`padding: 9 0 8`): links een teal statusregel — `Icons.edit_note_outlined` (15, teal) + "2 notities" (Inter 12.5/600, teal) + punt `#D1D5DB` (3px) + "3 markeringen" (Inter 12.5/500, `inkMuted`). Rechts vier knoppen van 36 × 36, radius 8, gap 2, in deze volgorde: **zoeken** (`Icons.search`), **weergave** (`Icons.text_fields` / Tt), **vertaling** (`Icons.translate`), **offline** (`Icons.download_outlined`). Stroke `inkBody`, 19px. Actieve knop krijgt `tealWash` achtergrond.

**Tekst:** `padding: 18 20 0`, Lora 17, line-height 1.75, `#1F2937`. Versnummer als superscript, Inter 11/600 `inkFaint`, 4px marge rechts. Alinea-afstand 16.

**Hoofdstuknavigatie** (vast onderaan de content, boven de tabbalk): border-top 1px `line`, `padding: 18 16 20`, `space-between`. Links `Icons.arrow_back` (16, teal) + "Vorige"; midden "5 / 50" (Inter 11, `inkFaint`); rechts "Volgende" + `Icons.arrow_forward`. Labels Inter 13/**400** — nadrukkelijk niet vet.

**Tabbalk:** Bijbel actief.

### 3. Studie (commentaar) — **nieuw**
`features/commentary/present/commentary_pane.dart`

Zelfde kop en segmented control als 2, met **Studie** actief. Daarna, in deze volgorde:

1. **Tabs**, `padding-top: 11`, gap 20, doorlopend tot de schermrand (`margin: 0 -16`, `padding-left/right: 16`) met een **border-bottom 1px `line`** die de tabs van de rest scheidt. Actief: Inter 13.5/600 teal met 2px teal onderstreping; inactief Inter 13.5/500 `inkFaint`. Labels: **Commentaar · Grondtekst · Info · Notities · Assistent**.
   De vijfde tab is de AI-assistent. Hij draagt links een klein paars glyph (14 px, gevuld `#7C3AED`) zodat hij zich onderscheidt van de vier inhoudstabs, en heet **Assistent** — voluit "AI-assistent" past niet binnen 390 px met de andere vier. De gap tussen de tabs is hier **14** in plaats van 20, precies om alle vijf te laten passen; verklein die niet verder en houd de rij horizontaal scrollbaar voor grotere tekstinstellingen.
2. **Bronregel**, `padding: 9 0 8`, gap 8: icoonvak 22 × 22, radius 6, `tealWash`, met open boek (13, teal); dan "Matthew Henry (NL)" (Inter 12.5/600); rechts "WISSEL" (Inter 10/600, ls 0.8, uppercase, `inkFaint`) + `Icons.keyboard_arrow_down` (14). Opent `source_picker_sheet.dart`.

**Content:** `padding: 18 20 0`. Eerst een pill "INLEIDING" (`tealWash`, `#0F766E`, Inter 10.5/600, ls 0.9, uppercase, `padding: 5 10`, radius 999). Dan body Inter 15.5/400 lh 1.75 `inkBody`. Een uitgelicht citaat staat links van een 2px teal streep met 14px inspringing, gezet in Lora 15/1.7 `ink`. Verskoppen: Inter 12/600, ls 0.9, uppercase, `inkFaint`.

**Geen hoofdstuknavigatie op dit scherm.** Het commentaar volgt het hoofdstuk dat op de Bijbel-kant open staat.

### 4. Studies · Ontdek — **nieuw** (het hoofdpunt van de herziening)
`features/studies/present/studies_screen.dart`

**Doel:** één duidelijke vervolgactie, daarna ontdekken.

**Kop** (wit, border-bottom 1px `line`, `padding: 4 16 14`): "Studies" (Inter 28/700, ls −0.5) met daaronder "77 studies · 4 begonnen" (Inter 12.5/400, `inkFaint`). Geen gekleurd vlak — de kop is wit.

**Zoekveld:** `lineSoft`, radius 12, hoogte 44, `padding: 0 14`, gap 10. `Icons.search` (17, `inkMuted`) + placeholder "Bijbelboek, persoon of thema" (Inter 14/400, `inkMuted`).

**Filterrij:** border-bottom 1px `line`, `padding: 12 16`, gap 8, horizontaal scrollbaar. Actief = **teal** vlak, witte tekst, Inter 12.5/600, `padding: 7 13`, radius 999. Inactief = 1px `line`, `inkBody`, Inter 12.5/500. Labels: **Voor jou · Bijbelboeken · Personen · Thema's**. (Eén filterrij — de tweede rij uit het oude ontwerp is vervallen.)

**Verder waar je was:** `padding: 16 16 14`, border-bottom 1px `line`, gap 14. Links een ring van 46 met `conic-gradient(teal 0 10%, line 10% 100%)` en daarbinnen een 36px bannerminiatuur. Midden: "VERDER WAAR JE WAS" (Inter 11/600, ls 0.9, uppercase, `inkFaint`) boven "Genesis · les 6" (Inter 16/700). Rechts een teal knop "Lezen" (Inter 13/600, `padding: 9 15`, radius 12).

**Nieuw deze maand:** sectiekop "Nieuw deze maand" (Inter 16/700) met rechts "Alle 8" (Inter 12.5/600, teal). Horizontale carrousel, kaartbreedte **196**, gap 12, `padding: 12 16 0`. Kaart: banner 112 hoog radius 14, titel Inter 14.5/700 (9px eronder), meta Inter 12/400 `inkFaint`.

**Alle studies:** sectiekop links, rechts uitgelijnd de link **"Per bijbelboek"** met `Icons.chevron_right` (Inter 12.5/600, teal) → opent scherm 5. Daaronder maximaal een handvol rijen, elk `padding: 12 16`, border-top 1px `lineSoft`, gap 13: miniatuur 44 radius 10, titel Inter 14.5/600, meta Inter 12/400 `inkFaint`, en bij een begonnen studie een balkje van 4px (`line` / teal) op 78% breedte. Rechts "Verder" of "Start" (Inter 12.5/600, teal).

### 5. Alle studies · per bijbelboek — **nieuw**
Nieuw scherm, gevoed door `core/data/bible_books.dart`.

**Doel:** alle 66 boeken bereikbaar maken zonder eindeloos scrollen op het Studies-scherm.

**Appbar** (hoogte 56): `Icons.arrow_back_ios_new`, titel "Alle studies" (Inter 16/600) met subtitel "66 boeken · 12 begonnen" (Inter 11.5/400, `inkFaint`), rechts `Icons.search`.

**Legenda** (border-bottom 1px `line`, `padding: 11 16`, gap 14): drie 12px vierkanten radius 3 met labels Inter 11.5/500 `inkMuted` — teal "afgerond", `tealSoft` "bezig", `lineSoft` met rand "nog niet".

**Inhoud:** zes canongroepen, elk met een kop (`padding: 18 0 10`): groepsnaam Inter 11.5/700 ls 1.0 uppercase `tealDark`, daarnaast het aantal (Inter 11.5/500 `inkFaint`) en een 1px vullijn. Groepen en volgorde:

| Groep | Boeken |
| --- | --- |
| Wet | 5 |
| Geschiedenis | 12 |
| Poëzie en wijsheid | 5 |
| Profeten | 17 |
| Evangeliën en Handelingen | 5 |
| Brieven en Openbaring | 22 |

De groepsindeling is een ontwerpkeuze; `bible_books.dart` kent alleen de OT/NT-splitsing en de canonieke volgorde. Neem de indeling over in een constante naast die lijst, en behoud per groep de canonieke volgorde.

**Tegels:** grid van 3 kolommen, gap 7, minimale hoogte **48**, radius 10, gecentreerde volledige boeknaam (Inter 12/600, lh 1.2, 2 regels toegestaan, `padding: 6 5`). Drie statussen: afgerond = teal vlak / witte tekst / 700; bezig = `tealSoft` / `#0F766E` / 700; nog niet = `lineSoft` / `inkBody` / 600.

### 6. Studie-detail — **nieuw**
`features/studies/present/study_detail_screen.dart`

**Appbar** (wit, 52, border-bottom 1px `line`, gap 14): terugpijl, "Genesis" (Inter 16/600), rechts instellingen-glyph.

**Banner:** hoogte **150**, serverafbeelding (`study_banner.dart`) met de gradiëntfallback. Linksboven een klein label "BANNER-SVG VAN DE SERVER" alleen ter aanduiding in de mock — laat dat weg. Linksonder twee pills, gap 8: wit vlak met `tealDark` tekst "Bijbelboek", en `rgba(17,24,39,.55)` met witte tekst "50 lessen · ±8,5 uur" (beide Inter 11.5/600, `padding: 5 10`, radius 999).

**Introtekst:** `padding: 18 20 0`. Titel "Genesis" (Inter 28/1.15, 700, ls −0.5), daaronder body Inter 14/400 lh 1.6 `inkMuted` met afsluitend "Lees meer" in teal 600.

**Tabs:** `padding: 18 20 0`, gap 24, border-bottom 1px `line`. Actief Inter 14/600 `ink` met 2px `ink` onderstreping; inactief Inter 14/500 `inkFaint`. Labels: **Lessen · Over · Notities**.

**Lessentijdlijn:** `padding: 14 20 0`. Een verticale lijn van 2px `line` op x = 31, vanaf y = 26. Elke les is een rij met gap 14 en 14–16px onderruimte:
- afgerond: bol 24 `success` met wit vinkje (stroke 3.2); titel Inter 14/500 `inkMuted`, meta Inter 12/400 `inkFaint`.
- huidig: bol 24 wit met 2.5px teal rand; titel Inter 15/700 `ink`; meta Inter 12/600 **teal**, met achtervoegsel "· nu".
- vergrendeld: bol 24 `lineSoft` met 1px `line`; titel Inter 14/500 `inkFaint`, meta Inter 12/400 `#D1D5DB`.

**Voetblok** (vast onderaan, border-top 1px `line`, `padding: 12 16 16`) — dit is de bestaande voortgangsbalk op zijn huidige plek:
1. rij: "Je bent bezig met deze studie" (Inter 13/400 `inkMuted`) links, "10 %" (Inter 13/600 `inkMuted`) rechts;
2. balk 6px radius 999, spoor `line`, vulling teal, marge `8 0 12`;
3. knop: teal, radius 12, hoogte 48, "Verder met les 6" (Inter 15/600, wit) met `Icons.arrow_forward` (18).

### 7. Les afgerond — **nieuw**
`features/levensboom/present/`, `features/study/present/`. Overgenomen uit richting B, ongewijzigd. Gebruikt de bestaande `TreeView`/XP-weergave.

### 8. Notities — **nieuw**
`features/notes/present/`

**Doel:** terugvinden wat je hebt opgeschreven, zonder visuele ruis.

**Kop** (wit, border-bottom 1px `line`, `padding: 4 16 0`): geen grote titel. Links een kleine kapitaalregel **"JOUW STUDIE"** (Inter 11/600, ls 1.2, uppercase, `inkFaint`), rechts "2 notities · 7 markeringen" (Inter 12.5/400, `inkFaint`). Daaronder tabs, gap 22, `padding-bottom: 11`: actief teal 600 met 2px teal onderstreping, inactief `inkMuted` 500. Labels: **Notities · Markeringen · Bladwijzers**.

**Notitieregels — geen kaarten.** Rand tot rand, `padding: 17 16`, gescheiden door één hairline 1px `line`. Geen datumkoppen, geen groepering. Per regel:
1. metarij: bron "Genesis 2" (Inter 12.5/600, teal) · punt 3px `#D1D5DB` · datum (Inter 12.5/400, `inkFaint`) · rechts een `Icons.more_vert` (17, `inkFaint`);
2. notitietekst, 8px eronder: Inter 14/**400**, lh 1.6, `ink` — niet vet;
3. versfragment, 9px eronder: links een 2px `tealSoft` streep met gap 10, tekst Lora 13/400 lh 1.6 `inkMuted`.

**FAB:** 56, teal, radius 999, wit plus-icoon, rechtsonder op 16, schaduw `0 6px 16px rgba(13,148,136,.35)`.

### 9–12. Profiel · Mijn voortgang · Instellingen · Profielmenu — *bestaand, referentie*
`features/profile/present/profile_screen.dart`, `profile_menu_sheet.dart`, `features/levensboom/present/`. 1:1 nagebouwd zodat de nieuwe schermen ertegen te leggen zijn. Niet opnieuw implementeren.

---

## Interactions & Behavior

- **Segmented control Bijbel ⇄ Studie:** wisselt de onderste helft, houdt hoofdstuk en scrollpositie vast. Geen paginanavigatie, geen laadscherm — de gebruiker moet zich niet opnieuw hoeven oriënteren.
- **"Per bijbelboek" →** pusht scherm 5 op de studies-stack. Tikken op een tegel opent studie-detail van dat boek.
- **Vorige / Volgende** (alleen op de Bijbel-kant) navigeert per hoofdstuk; de teller "5 / 50" toont de positie binnen het boek.
- **Bronregel "Wissel"** opent `source_picker_sheet.dart` als bottom sheet.
- **Vertaling-, weergave- en offline-knoppen** openen respectievelijk de bestaande sheets (`reader_settings_sheet.dart` voor weergave).
- **Notitieregel** tikken opent de notitie; `more_vert` opent acties (delen, verwijderen). De FAB maakt een losse notitie.
- **Lessentijdlijn:** afgeronde en huidige lessen zijn tikbaar; vergrendelde niet (geen ripple, geen snackbar).
- **Studies-filters:** één actief filter tegelijk; de lijst eronder ververst zonder scroll-reset naar boven.
- Transities: gebruik wat de app al gebruikt. Voortgangsbalken animeren 300 ms `easeOut` bij verandering; er is verder geen nieuwe animatie in dit ontwerp.

## State Management

Volg de bestaande aanpak per feature. Wat de nieuwe schermen nodig hebben:

| Scherm | State |
| --- | --- |
| Bijbel / Studie | `activePane` (bijbel \| studie), `book`, `chapter`, `translationId`, `readerSettings`, `commentarySourceId`, `activeStudyTab`, tellingen van notities/markeringen voor dit hoofdstuk |
| Studies · Ontdek | `activeFilter`, `searchQuery`, `continueStudy` (nullable), `newThisMonth[]`, `allStudies[]` |
| Alle studies | `bookProgress` per boek (afgerond \| bezig \| nog niet), `activeFilter` |
| Studie-detail | `study`, `lessons[]` met status, `currentLessonIndex`, `progressPercent`, `activeTab` |
| Notities | `activeTab` (notities \| markeringen \| bladwijzers), `notes[]` gesorteerd op datum aflopend |

Datavereisten die mogelijk nieuw zijn: een per-boek voortgangsstatus voor scherm 5, en een telling van notities/markeringen per hoofdstuk voor de kop van scherm 2.

## Assets

Geen nieuwe assets. Studiebanners komen van de server via `study_banner.dart` (met teal → `#0F172A` fallback). Iconen zijn Material-iconen; de SVG's in de HTML zijn benaderingen van `Icons.search`, `Icons.text_fields`, `Icons.translate`, `Icons.download_outlined`, `Icons.menu_book_outlined`, `Icons.auto_stories_outlined`, `Icons.edit_note_outlined`, `Icons.local_library_outlined`, `Icons.settings_outlined`, `Icons.local_fire_department_outlined`, `Icons.more_vert`, `Icons.chevron_right`, `Icons.keyboard_arrow_down`. Illustraties blijven runtime getekend.

## Screenshots

In `screenshots/` staan de zeven aan te passen schermen op 2× (784 × 1692 px):

| Bestand | Scherm |
| --- | --- |
| `01-studies-ontdek.png` | Studies · Ontdek |
| `02-studies-alle-boeken.png` | Studies · alle boeken |
| `03-studie-detail.png` | Studie-detail |
| `04-les-afgerond.png` | Les afgerond |
| `05-bijbel.png` | Bijbel (lezer) |
| `06-studie.png` | Studie (commentaar) |
| `07-notities.png` | Notities |

In `screenshots/referentie/` staan de vijf bestaande schermen die **niet** aangepast worden: Start, Profiel, Mijn voortgang, Instellingen en het profielmenu.

De schermen zijn 390 × 844 groot; wat daarbuiten valt is scrollinhoud en staat niet op de afbeelding. Voor die delen is het HTML-prototype de bron — daar kun je doorheen scrollen.

## Files

- `BijbelStudie Screens.dc.html` — alle twaalf schermen op één canvas, van links naar rechts in appvolgorde. Open in een browser; `support.js` moet ernaast staan.
- `support.js` — runtime voor het HTML-prototype. Niet relevant voor de implementatie.
- `github.md` — koppeling met de repo en de kaart van scherm → bronbestanden.
- `screenshots/` — de zeven aan te passen schermen; `screenshots/referentie/` de vijf bestaande.

## Hoe je dit het beste aanpakt met Claude Code

1. Open het prototype naast je editor en houd het open tijdens het bouwen — de README beschrijft de waarden, de HTML laat de verhoudingen zien.
2. Begin met de tokens: controleer of alle kleuren en tekststijlen hierboven in `app_theme.dart` bestaan en vul aan wat ontbreekt. Doe dit vóór het eerste scherm.
3. Bouw daarna in deze volgorde, van gedeeld naar specifiek: de segmented control en de filter-pill (herbruikbaar), dan Studies · Ontdek, het boekenoverzicht, studie-detail, de lezer (Bijbel en Studie) en als laatste notities.
4. Zet in elke prompt de regel erbij dat alleen de UI verandert en de werking gelijk blijft. Geef Claude Code per scherm één opdracht met de bijbehorende paragraaf uit deze README erbij, plus het pad naar het bestaande Dart-bestand. Eén scherm per keer levert betrouwbaarder resultaat dan de hele set in één prompt.
5. Laat de vijf bestaande schermen ongemoeid — zie “Scope” bovenaan. Als Claude Code voorstelt ze “gelijk te trekken”, wijs dat af.
