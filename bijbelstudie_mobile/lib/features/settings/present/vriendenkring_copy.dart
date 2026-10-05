/// The Dutch copy of the Vriendenkring section in Instellingen, in one place.
///
/// Word for word the website's `components/settings/vriendenkringCopy.ts`, and
/// it has to stay that way: these sentences are the product's privacy promise -
/// what is findable, what gets published, what stays private - and two clients
/// that word that promise differently are two different promises. The website
/// keeps the same file for the same reason, with a test on it.
///
/// On the three auto-share switches. Only `milestones` is read by the server
/// today (`postMilestone` in `lib/friends/service.ts`); `createPost` - the
/// share actions on the tekst van de dag and on a note - checks nothing,
/// because those are always an explicit choice. So `verses` and `notes` are
/// permission given in advance for automatic sharing that does not exist yet,
/// and [autoShareFootnote] says exactly that rather than letting two switches
/// imply a behaviour that is not there. Notes in particular: nothing but a
/// note the reader shared by hand ever reaches the kring, with either switch
/// in either position.
library;

const vriendenkringSectionTitle = 'Vriendenkring';
const vriendenkringSectionSubtitle =
    'Wie je kan vinden, en wat er in je kring terechtkomt';

const discoverableLabel = 'Vindbaar voor je contacten';
const discoverableHint =
    'Hiermee kan iemand die je telefoonnummer of e-mailadres al heeft je in BijbelStudie '
    'vinden en je een vriendschapsverzoek sturen. Staat dit uit, dan vindt niemand je zo; '
    'via een uitnodigingslink of een code kun je altijd vrienden worden.';

const autoShareMilestonesLabel = 'Mijlpalen';
const autoShareMilestonesHint =
    'Rond je een dag van je leesplan af, maak je een studie af, haal je een badge of lees '
    'je 7, 30 of 100 dagen op rij? Dan komt dat als bericht in je kring. Dit is het enige '
    'wat vanzelf geplaatst wordt.';

const autoShareVersesLabel = 'Tekst van de dag';
const autoShareVersesHint =
    'Je toestemming om de tekst van de dag namens jou in je kring te plaatsen: de '
    'verwijzing en de tekst zelf, nooit wat je erbij bewaart of onderstreept.';

const autoShareNotesLabel = 'Notities';
const autoShareNotesHint =
    'Je toestemming om een notitie namens jou in je kring te plaatsen. Je notitieboek '
    'blijft privé: alleen een notitie die je zelf deelt komt ooit in je kring, en wat je '
    'kring dan ziet is een kopie - pas je de notitie later aan, dan verandert dat bericht '
    'niet mee.';

const autoShareFootnote =
    'Vandaag plaatst alleen Mijlpalen vanzelf iets in je kring. Een tekst van de dag of '
    'een notitie komt er alleen in als je er zelf "Deel met je vrienden" bij kiest, ook '
    'met deze schakelaars aan.';

const forgetContactsLabel = 'Vergeet mijn contactgegevens';
const forgetContactsHint =
    'De app bewaart een versleutelde afdruk van je telefoonnummer en e-mailadres, zodat '
    'mensen die je al kennen je kunnen vinden. Hiermee gooi je die weg. Je vriendschappen '
    'blijven; alleen vinden via contacten werkt daarna niet meer tot je het in de app '
    'opnieuw aanzet.';
const forgetContactsAction = 'Vergeten';
const forgetContactsConfirmTitle = 'Je contactgegevens vergeten?';
const forgetContactsConfirmBody =
    'We verwijderen de versleutelde afdruk van je telefoonnummer en e-mailadres. Je '
    'vrienden en je berichten blijven staan. Mensen die je nummer hebben, vinden je '
    'hierna niet meer in BijbelStudie.';
const forgetContactsConfirmAction = 'Ja, vergeet ze';
const forgetContactsDone = 'Je contactgegevens zijn verwijderd.';
