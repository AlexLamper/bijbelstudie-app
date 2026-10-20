# App Store listing: Custom Product Pages en Product Page Optimization

Wat die twee secties in App Store Connect zijn, wat er al klaarstaat, en wat je
zelf moet aanklikken. Alles wat hier als regel van Apple staat, komt uit de
documentatie onderaan. Waar iets een vuistregel is en geen regel van Apple, zeg
ik dat erbij.

---

## 1. Wat je nu ziet in App Store Connect

Je hebt drie dingen naast elkaar, en ze doen iets anders.

**De standaardpagina.** De productpagina die iedereen ziet die BijbelStudie
opzoekt of aantikt. Die hoort bij de app-versie: naam, subtitle, icoon,
screenshots, app previews, promotional text, beschrijving, keywords. Dit is je
basis en hier begint alle winst.

**Custom Product Pages (0 of 70).** Extra productpagina's naast de
standaardpagina. Je mag er tot 70 publiceren per app. Elke pagina krijgt een
eigen URL en je kunt daarop andere screenshots, andere app previews en een
andere promotional text zetten. Wat je *niet* per pagina kunt wijzigen: de naam
van de app, de subtitle, het icoon en de beschrijving. Die komen altijd van de
standaardpagina. Je gebruikt zo'n pagina om een specifiek publiek op een
specifieke belofte te laten landen.

Belangrijk: een custom product page komt standaard **niet** in de normale
zoekresultaten. Mensen zien hem alleen via zijn eigen link, of als je er
keywords aan toewijst (die keywords komen uit je laatst goedgekeurde
app-versie). Zonder link en zonder keywords ziet iedereen gewoon de
standaardpagina.

**Product Page Optimization / Create Test.** Een A/B-test op je
**standaardpagina**. Je maakt tot drie varianten ("treatments"), Apple stuurt
een deel van je bezoekers daarnaartoe en meet welke versie beter converteert.
Je test hier dus geen teksten en geen custom product pages, maar beeld: icoon,
screenshots, app previews en de nieuwe creative assets.

De drie samen: de standaardpagina is je fundament, Product Page Optimization
vertelt je welk beeld daar het beste werkt, en Custom Product Pages laten je
per doelgroep een eigen variant tonen aan mensen die je zelf aanlevert.

**Het ene feit dat het meeste uitmaakt:** van je screenshots verschijnen
volgens Apple de eerste een tot drie afbeeldingen in de zoekresultaten, en bij
portret-screenshots zijn dat er drie. Die eerste drie doen het werk. Iemand die
jouw app in een lijstje ziet staan, beslist daarop of hij doorklikt. Alles
achter screenshot 3 wordt door de meeste mensen nooit gezien.

---

## 2. Wat is er al

De standaardpagina staat en is goedgekeurd. De screenshotsets zelf staan
lokaal in `store-assets/app-store-aso/`. Die map is gitignored, dus hij staat
niet op GitHub en bestaat alleen op jouw machine. Maak er een back-up van.

Afmetingen die erin zitten, per toestelklasse:

| Toestel | Pixels |
| --- | --- |
| iPhone 6.9" | 1320 x 2868 |
| iPhone 6.5" | 1284 x 2778 |
| iPad 13" | 2064 x 2752 |

Alle drie zijn portret. Dat is bewust: portret levert drie afbeeldingen in de
zoekresultaten op in plaats van een.

Apple staat tot 10 screenshots per pagina toe en tot drie app previews per
taal per toestelmaat.

---

## 3. Header and Search Results: de nieuwe creative assets

Sinds begin oktober 2026 staat er op de versiepagina, onder **Product Page
Information**, een tab naast **App Previews and Screenshots** die **Header and
Search Results** heet. Dat zijn Apple's nieuwe "creative assets". Ze zijn
**optioneel**: laat je ze leeg, dan verschijnen je app previews en screenshots
precies zoals nu. En ze worden alleen getoond op **iOS 27 / iPadOS 27 en
nieuwer**. Dit is dus een extra laag, geen vervanging.

Twee plaatsen:

- **Header**: een breed beeld of een video bovenaan je productpagina.
- **Search Results**: het beeld of de video op het kaartje van je app in de
  zoekresultaten.

Een enkele **universal** asset kan beide plaatsen vullen. Wil je ze apart
sturen, dan upload je per plaats een eigen asset. Afbeeldingen mogen **geen
alfakanaal en geen transparantie** bevatten.

### Afmetingen

| Plaats | Verhouding | Pixels | Bestandstype |
| --- | --- | --- | --- |
| Header, afbeelding | 21:9 | 3840 x 1646 | .jpeg / .jpg / .png |
| Header, afbeelding | 16:9 | 5244 x 2950 | alleen .png |
| Search Results, afbeelding | 3:2 | min 1920 x 1280, max 3840 x 2560 | .jpeg / .jpg / .png |
| Search Results, afbeelding | 16:9 | 5244 x 2950 | alleen .png |
| Header, video | 21:9 | 3840 x 1646 | .mov / .m4v / .mp4 |
| Search Results, video | 3:2 | min 1920 x 1280, max 3840 x 2560 | .mov / .m4v / .mp4 |

Video: 30 of 60 fps, 5 tot 30 seconden. In de zoekresultaten staat video
standaard op stil en kan de kijker het geluid daar niet aanzetten; op de
productpagina kan hij het wel aanzetten. Video loopt in beide plaatsen in een
lus.

### Wat Apple inhoudelijk toestaat

- Een duidelijk idee per asset, geen volle plaat.
- Houd de belangrijke elementen, en vooral tekst, goed leesbaar.
- Zet het middelpunt in het midden, anders wordt het weggesneden.
- Korte zinnen die het beeld versterken, niet beschrijven.
- Vertaal de tekst per taal.
- Geen prijzen, geen kortingen, geen website-URL's, geen copyrightteken.
- Geen claims die je niet kunt aantonen.
- Geen logo's van of verwijzingen naar andere platformen of stores.
- Geen Apple-onderscheidingen zoals Editor's Choice of Apple Design Award.

### Welke variant waar

Er worden drie varianten gerenderd naar `store-assets/app-store-creative/`, elk
in alle drie de maten (`universal-16x9-5244x2950.png`,
`header-21x9-3840x1646.png`, `search-3x2-3840x2560.png`). Proefbladen staan in
`store-assets/app-store-creative/_proof/`.

| Map | Kop | Beeld | Wanneer |
| --- | --- | --- | --- |
| `a-begrijpen/` | "Begrijpen wat er staat" | de gesplitste lezer | eerst, als universal asset voor beide plaatsen |
| `b-grondtekst/` | "Lees mee in het Hebreeuws" | voor de verdieper | later, als testvariant |
| `c-stille-tijd/` | "Een kwartier per dag" | lichte achtergrond, dagelijks ritme | later, als testvariant |

Volgorde: upload `a-begrijpen/universal-16x9-5244x2950.png` als universal asset
voor Header en Search Results. Bekijk het resultaat met de **Preview**-knop,
die je de asset laat zien op de productpagina en op het zoekkaartje, voor
iPhone en iPad, in beide schermstanden, in alle talen en in Dark Mode. Laat
`b-grondtekst/` en `c-stille-tijd/` liggen tot de eerste screenshot-test klaar
is (zie paragraaf 5).

### Dit is een aparte upload

De creative assets staan los van je portret-screenshots. De sets in
`store-assets/app-store-aso/` blijven verplicht en blijven wat de meeste mensen
zien: alles onder iOS 27, en overal waar geen creative asset staat. Eerst de
screenshots goed, dan de creative assets erbovenop.

### Asset Library en de standalone submission

Dezelfde assets kun je ook uploaden vanuit **Asset Library**, en vanuit Custom
Product Pages, Product Page Optimization en In-App Events. Asset Library is
nieuw: een centrale plek om creative assets, screenshots en app previews te
uploaden en te ordenen, en om assets vooraf ter goedkeuring aan te bieden zodat
ze klaarstaan voor een campagne.

Een asset kan mee in een gewone versie-indiening, of als **standalone
submission** vanuit Asset Library. Die laatste vraagt **geen nieuwe build**:
hij wordt beoordeeld tegen de laatste versie van je app. Je hoeft dus niet te
wachten op een release om beeld te wisselen.

---

## 4. Custom Product Pages: het plan

Drie pagina's, elk met een eigen screenshotmap en een eigen eerste belofte.
Drie is genoeg: elke pagina moet je onderhouden en vertalen, en pagina's zonder
verkeer ernaartoe leveren niets op.

| Pagina | Publiek | Map | Tekens | Linken vanaf |
| --- | --- | --- | --- | --- |
| `cpp-beginners` | leest wel, maar loopt vast en weet niet waar te beginnen | `store-assets/app-store-aso/cpp-beginners/` | 156 / 170 | posts en advertenties over beginnen met Bijbellezen en over de studies |
| `cpp-grondtekst` | de verdieper die de grondtekst en de klassieke commentaren wil | `store-assets/app-store-aso/cpp-grondtekst/` | 159 / 170 | alles over Hebreeuws en Grieks en over commentaren |
| `cpp-stille-tijd` | zoekt een dagelijkse gewoonte | `store-assets/app-store-aso/cpp-stille-tijd/` | 144 / 170 | alles over stille tijd, de tekst van de dag en de streak met je boom |

De promotional text per pagina, om letterlijk te plakken. De harde grens van
Apple is 170 tekens.

**cpp-beginners** (156 tekens):

> Weet je niet waar je moet beginnen? Lees een hoofdstuk met de uitleg
> ernaast, of doe een studie van 15 minuten in 6 stappen. Stap voor stap door
> Gods Woord.

**cpp-grondtekst** (159 tekens):

> De grondtekst naast je hoofdstuk: Hebreeuws en Grieks met transliteratie en
> Strong-nummers, plus Matthew Henry, Calvijn en Dachsel. Voor wie verder wil
> kijken.

**cpp-stille-tijd** (144 tekens):

> Elke dag een moment rust bij Gods Woord. Lees een hoofdstuk met uitleg,
> schrijf je notitie, en zie je boom groeien. Stille tijd die je volhoudt.

Let bij het opbouwen van de screenshots op dit: de eerste twee of drie
screenshots moeten precies de belofte van die pagina laten zien. Op
`cpp-grondtekst` begin je dus met de grondtekst en niet met de leesweergave,
anders had je de pagina niet nodig.

Een paar regels van Apple die je hier moet weten:

- Elke pagina moet **goedgekeurd** zijn voordat iemand hem kan zien. Dat kan
  los van een app-update.
- Pas je een goedgekeurde pagina aan, dan blijft de oude live tot de
  aanpassing is goedgekeurd, en dan gaat hij automatisch over. De unieke URL
  verandert daarbij niet.
- Custom Product Pages werken op iOS 15 / iPadOS 15 en nieuwer. Een deep link
  naar een plek in de app erbij vraagt iOS 18 of nieuwer.
- Je kunt deze URL's gebruiken in e-mail, op social media en als bestemming in
  **Apple Ads**: daar kun je advertentievarianten maken die elk naar een eigen
  custom product page leiden.
- In App Analytics zie je per pagina de impressions, downloads, redownloads en
  conversie, en kun je elke pagina vergelijken met de standaardpagina.

---

## 5. Product Page Optimization: de eerste test

### Wat er wordt opgezet

Een test op de standaardpagina, met de huidige pagina als controle (Apple noemt
dat de baseline) en twee treatments die **alleen de eerste drie screenshots**
veranderen. Al het andere blijft gelijk. Een treatment begint standaard als een
kopie van de standaardpagina, en wat je niet aanpast komt gewoon van die
pagina. Zo isoleer je precies een ding: de hook.

| Variant | Hook | Map |
| --- | --- | --- |
| Controle | de huidige screenshots | `store-assets/app-store-aso/` |
| Treatment B | begint met de grondtekst, voor de diepte | `store-assets/app-store-aso/ppo/treatment-b/` |
| Treatment C | begint met het dagelijkse ritme, voor de gewoonte | `store-assets/app-store-aso/ppo/treatment-c/` |

### Hoe lang en waar je kijkt

Een test loopt **90 dagen**, of tot je hem zelf stopt. Resultaten staan in
**App Analytics**, onder **Acquisition** bij **Product Pages**, in de sectie
Product Page Optimization. Ze verschijnen pas nadat er minstens vijf eerste
downloads aan de test zijn toegerekend, en ze werken dagelijks bij.

Wat je daar ziet per variant: Unique Impressions, Conversion Rate, Improvement
ten opzichte van de baseline, een Confidence-percentage, en de Bayesiaanse
schattingen (Estimated Conversion Rate, Estimated Relative Lift, Credible
Interval). Daarnaast een status: Collecting Data, Performing Better, Performing
Worse of Likely to be Inconclusive.

### Wat een bruikbaar resultaat is

Alleen dit: een treatment met de status **Performing Better** bij minstens
**90% confidence**. Dan pas je die treatment toe op de standaardpagina, en
daarna test je het volgende element tegen die verbeterde versie. Apple zegt er
expliciet bij: stop een test niet vroeg omdat het de goede kant op lijkt te
gaan. Grotere verschillen bereiken significantie sneller dan kleine.

Verschillen van een paar procent zonder confidence zijn ruis. Daar doe je niets
mee.

### Als het verkeer te laag is

Dit is het realistische scenario. Met weinig impressions duurt een test lang
voordat er iets significant is, en de status kan op **Likely to be
Inconclusive** springen: dan verwacht Apple dat er binnen 90 dagen niet genoeg
data komt. Apple's eigen advies in dat geval: test een grotere verandering, zet
de test opnieuw op in een drukkere periode, of verleng de looptijd. Bij het
aanmaken van de test staat er een **Estimate Your Test Duration** waar je ziet
wat jouw verkeer aankan; schat die duur voor je begint.

Wat dat voor jou betekent, als vuistregel en niet als regel van Apple: komt de
geschatte duur ver boven de 90 dagen, zet dan **een** treatment op in plaats
van twee (dan krijgt die variant het dubbele verkeer) en maak het verschil met
de controle groot. Twee varianten die op elkaar lijken kosten je een kwartaal
en leveren niets op. Zet de traffic proportion ook niet te laag.

### De volgende test

Daarna, niet nu: de creative assets uit paragraaf 3 tegen elkaar. Variant
`b-grondtekst` en `c-stille-tijd` als treatments, met `a-begrijpen` als
controle. Dat is een nette tweede test omdat het beeld dan het enige is dat
verschilt. Maar eerst de screenshots, want die zien ook alle toestellen onder
iOS 27.

### Regels van Apple die hier gelden

- Maximaal **drie treatments** per test, en meer treatments maakt de test
  langer.
- Je kunt **icoon, screenshots en app previews** testen. Voor een icoontest
  moeten alle iconen al in de **binary** van de gepubliceerde versie zitten
  (1024 x 1024, asset catalog, gebouwd met Xcode 13 of nieuwer). Daarom laten
  we het icoon nu met rust: dat kan niet zonder nieuwe build.
- Zit er een ander icoon in een treatment, dan zien de mensen in die groep dat
  icoon op de App Store **en op hun toestel** als ze de app al hebben staan.
  Dat is een reden om er voorzichtig mee te zijn.
- **Traffic proportion** is het percentage bezoekers dat een treatment krijgt
  in plaats van de originele pagina. Dat percentage wordt gelijk over de
  treatments verdeeld: bij drie treatments en 30% krijgt elke treatment 10%
  van het totaal.
- Alle talen van je app staan standaard aan. Ziet iemand een taal die je
  uitsluit, dan valt die persoon buiten de test.
- Metadata in je treatments moet goedgekeurd zijn, en dat kan **zonder** een
  nieuwe app-versie. Verander je alleen de volgorde van bestaande screenshots,
  of alleen het icoon, dan hoeft er niets opnieuw ingediend te worden.
- **Een Product Page Optimization-test kan niet op een custom product page.**
  Dit staat zo in de documentatie van Apple. Tests gaan altijd over je
  standaardpagina.
- Je kunt tests op verschillende elementen naast elkaar laten lopen, maar niet
  op overlappende elementen, want dan weet je niet wat het deed.

**Niet bevestigd bij Apple:** of een lopende test en gepubliceerde custom
product pages elkaar in de weg zitten. Wat Apple wel zegt, is dat een test niet
*op* een custom product page kan. Dat de drie pagina's uit paragraaf 4 live
mogen staan terwijl de test op de standaardpagina loopt, heb ik in Apple's
documentatie niet expliciet terug kunnen vinden. Zet de pagina's dus eerst
live, kijk of App Store Connect klaagt bij het aanmaken van de test, en
vertrouw hier niet op mijn aanname.

---

## 6. Wat je precies klikt

### a. Een custom product page maken

1. App Store Connect, **Apps**, kies BijbelStudie.
2. In de zijbalk links: **Custom Product Pages**.
3. **Create Custom Product Page**, of het plusje als er al pagina's staan.
4. Vul bij de referentienaam `cpp-beginners` in. Die naam is alleen voor jou en
   voor App Analytics.
5. Kies **blank page** om leeg te beginnen, of kies een bestaande pagina om die
   te kopieren.
6. **Create**. De unieke URL wordt meteen gegenereerd.
7. Open de pagina, kies de taal (Nederlands) en vul in:
   - **Promotional text**: de tekst uit paragraaf 4, maximaal 170 tekens.
   - **App Previews and Screenshots**: sleep de bestanden uit
     `store-assets/app-store-aso/cpp-beginners/` erin, per toestelmaat (6.9",
     6.5", iPad 13"). Of gebruik **Browse Assets** voor al goedgekeurd beeld
     uit **Asset Library**.
   - Eventueel **Header and Search Results** voor deze pagina.
8. Wil je dat de pagina ook in de zoekresultaten verschijnt, dan wijs je er
   **keywords** aan toe. Gebruik per pagina een eigen combinatie, en niet
   dezelfde woorden op twee pagina's.
9. **Save**, dan de pagina ter review indienen. Dit kan los van een app-update.
   Na goedkeuring zet je hem op visible.
10. Herhaal voor `cpp-grondtekst` en `cpp-stille-tijd`.

Je hebt hiervoor de rol Account Holder, Admin, App Manager of Marketing, en de
app moet in minstens een land de status Ready for Distribution hebben. Beide
heb je.

### b. De unieke URL kopieren

1. **Custom Product Pages**, klik de pagina aan.
2. De URL staat op de pagina zelf. Kopieer hem.
3. Het is je normale App Store-link met een extra parameter voor de
   product-page-id erachter. Bewaar de drie URL's ergens bij de hand, bij deze
   doc of in je notities, en zet erachter waar je ze gebruikt.
4. Die URL blijft hetzelfde als je de pagina later aanpast.

### c. De PPO-test aanmaken en de treatments vullen

1. App Store Connect, **Apps**, kies BijbelStudie.
2. Zijbalk: **Product Page Optimization**.
3. **Create Test** (of het plusje als er al tests staan).
4. Referentienaam: bijvoorbeeld `screenshots-hook-1`. Onder die naam vind je de
   test terug in App Analytics.
5. **Number of treatments**: 2.
6. **Traffic proportion**: kies het percentage bezoekers dat een treatment
   krijgt. Bij 2 treatments en 30% krijgt elke treatment 15%.
7. **Localizations**: laat Nederlands aanstaan.
8. Klap **Estimate Your Test Duration** open, kies de verbetering die je zou
   willen zien, en lees af hoe lang dat met jouw verkeer duurt. Schrikt dat
   getal je af, ga dan terug naar stap 5 en maak er een treatment van.
9. **Create Test**.
10. Per treatment: **Edit Name** om hem `grondtekst-hook` en `ritme-hook` te
    noemen. Die namen zijn alleen voor jou.
11. Open treatment B, tab **App Previews and Screenshots**, en upload de
    bestanden uit `store-assets/app-store-aso/ppo/treatment-b/`. Doe hetzelfde
    voor treatment C met `ppo/treatment-c/`. Wat je per toestelmaat niet
    aanpast, blijft het beeld van de standaardpagina.
12. De tab **App Icon** laat je leeg. Die verschijnt alleen als je binary meer
    dan een icoon bevat.
13. Dien de metadata ter review in, en start de test zodra alles is
    goedgekeurd.

### d. Een creative asset uploaden

1. App Store Connect, **Apps**, kies BijbelStudie, en open de versiepagina.
2. Onder **Product Page Information**: tab **Header and Search Results**.
3. Klik **Header** of **Search Results**.
4. Sleep de asset erin, of klik **Browse Assets** voor iets uit **Asset
   Library**. Begin met `a-begrijpen/universal-16x9-5244x2950.png` als
   universal asset voor beide plaatsen.
5. **Save**.
6. Klik **Preview** en loop de weergaves langs: productpagina en zoekkaartje,
   iPhone en iPad, beide schermstanden, Dark Mode.
7. Geen nieuwe build nodig? Dien hem dan in als **standalone submission**
   vanuit **Asset Library**. Hij wordt beoordeeld tegen de laatste versie van
   de app.

---

## 7. Tekstvelden die ook meetellen

Beeld doet het meeste werk, maar de tekstvelden bepalen of je gevonden wordt.
Dit zijn de velden en wat ze doen:

- **App name**: tot 30 tekens. Wordt meegenomen in zoeken.
- **Subtitle**: tot 30 tekens, staat onder de naam. Wordt meegenomen in zoeken.
  Je kunt hem wijzigen bij een nieuwe versie.
- **Keywords**: 100 tekens in totaal, komma's zonder spaties ertussen. Niet
  zichtbaar voor gebruikers. Dit veld bepaalt mede waar je in de
  zoekresultaten staat.
- **Promotional text**: tot 170 tekens, staat boven de beschrijving. Je kunt
  hem **op elk moment aanpassen zonder nieuwe versie**. Apple zegt er expliciet
  bij dat dit veld de zoekpositie niet beinvloedt, dus stop er geen keywords
  in; schrijf er iets wat mensen overhaalt.
- **Description**: wat mensen lezen als ze doorklikken. Apple zegt letterlijk
  dat je geen onnodige keywords in de beschrijving moet zetten om hoger in de
  zoekresultaten te komen, want daar werkt het niet. De beschrijving is geen
  bron voor zoekwoorden. Schrijf hem dus voor mensen.

Twee regels van Apple die je tekens sparen: wat al in de **app name** en de
**subtitle** staat, hoef je niet in het keywordveld te herhalen, want dat is al
doorzoekbaar. En laat uit het keywordveld weg: meervouden van woorden die je al
enkelvoud hebt staan, categorienamen, het woord "app", dubbele woorden en
speciale tekens. Die leveren niets op en kosten tekens.

### Concreet voorstel

**Subtitle** (28 van 30 tekens):

> Bijbel met uitleg en context

**Keywords** (92 van 100 tekens):

> studiebijbel,statenvertaling,grondtekst,commentaar,stille tijd,dagtekst,Hebreeuws,Grieks,NBG

Waarom zo: "bijbel", "uitleg" en "context" zitten al in de naam en de subtitle,
dus die staan er niet nog eens bij, en "bijbelstudie" zit in de naam. Het woord
"app" laat ik eruit op advies van Apple; zoekopdrachten als "bijbel app" komen
voort uit combinaties van je woorden, en "app" zelf krijgt geen extra gewicht.
"bijbel met uitleg" hoef je ook niet los op te nemen: die woorden staan alle
drie al in de subtitle. Wat overblijft, zijn de termen die je publiek intikt en
die nog nergens anders staan.

**Promotional text** (154 van 170 tekens):

> Lees de Bijbel met uitleg, context en de grondtekst ernaast. Alle studies
> zijn gratis, elke dag een tekst, en je notities blijven bij het hoofdstuk
> staan.

Dit veld kun je zonder release wisselen, dus gebruik het ook zo: bij een nieuwe
vertaling, een nieuw commentaar of rond een periode als de Veertigdagentijd zet
je er iets passends in.

---

## 8. Volgorde van aanpak

**Eerst, dit kan vandaag.** Subtitle, keywordveld en promotional text uit
paragraaf 7 invoeren. De promotional text gaat direct in; subtitle en keywords
gaan mee met je volgende versie. Dit kost een kwartier en werkt op iedereen die
je pagina vindt.

**Tweede.** De drie custom product pages aanmaken, indienen, en de URL's
vastleggen. Daarna de URL's ook gebruiken: elke post, mail of advertentie over
beginnen met Bijbellezen gaat naar `cpp-beginners`, elk stuk over de grondtekst
naar `cpp-grondtekst`, alles over stille tijd naar `cpp-stille-tijd`. Zonder
links ernaartoe doen deze pagina's niets, want ze staan niet in de
zoekresultaten.

**Derde.** De creative asset `a-begrijpen` als universal asset uploaden en als
standalone submission indienen. Optioneel, alleen zichtbaar op iOS 27 en
nieuwer, en er hangt geen build aan.

**Vierde.** De PPO-test met de twee screenshot-treatments opzetten, maar kijk
eerst naar **Estimate Your Test Duration**. Is dat getal onwerkbaar, zet dan
een test met een treatment op. Laat hem lopen en kijk er maandelijks naar, niet
dagelijks.

**Laat met rust tot er data is.** Het icoon: een icoontest vraagt alle
varianten in de binary, en een icoon dat op iemands beginscherm verandert is
een groot ingrijpen voor een kleine winst. De creative assets `b-grondtekst` en
`c-stille-tijd`: die zijn de tweede test, niet de eerste. En een vierde of
vijfde custom product page: eerst moeten deze drie verkeer krijgen. Meer
pagina's zonder links ernaartoe is werk zonder opbrengst.

---

## Bronnen

De pagina's van Apple waar de regels hierboven uit komen.

- https://developer.apple.com/help/app-store-connect/create-custom-product-pages/configure-multiple-product-page-versions/
- https://developer.apple.com/app-store/custom-product-pages/
- https://developer.apple.com/help/app-store-connect/create-product-page-optimization-tests/create-a-test/
- https://developer.apple.com/help/app-store-connect/create-product-page-optimization-tests/configure-test-treatments/
- https://developer.apple.com/app-store/product-page-optimization/
- https://developer.apple.com/help/app-store-connect-analytics/acquisition/product-page-optimization
- https://developer.apple.com/app-store/product-page/
- https://developer.apple.com/app-store/asset-best-practices/
- https://developer.apple.com/help/app-store-connect/reference/app-information/
