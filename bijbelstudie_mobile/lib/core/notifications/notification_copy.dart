import 'notification_service.dart' show NotifType, RenderedVariant;

/// One un-personalised line. Tokens are `{study} {lesson} {streak} {name}
/// {book} {done} {target} {n} {verse} {reference}` (`RETENTION_PLAN.md` §5).
class VariantTemplate {
  const VariantTemplate(this.id, this.title, this.body);

  final String id;
  final String title;
  final String body;

  bool get isTokenFree => !title.contains('{') && !body.contains('{');
}

/// Fills `{tokens}`; a template that needs a token we do not have falls back to
/// the first token-free line in the same pool (§5). Never returns a string with
/// an unresolved `{token}` in it.
RenderedVariant renderVariant(
  NotifType type,
  VariantTemplate template,
  Map<String, String?> tokens,
) {
  final pool = notificationCopy[type] ?? const [];

  String? fill(String input) {
    var out = input;
    final needed = RegExp(r'\{(\w+)\}')
        .allMatches(input)
        .map((m) => m.group(1)!)
        .toSet();
    for (final key in needed) {
      final value = tokens[key];
      if (value == null || value.trim().isEmpty) return null; // missing token
      out = out.replaceAll('{$key}', value.trim());
    }
    return out;
  }

  final title = fill(template.title);
  final body = fill(template.body);
  if (title != null && body != null) {
    return RenderedVariant(variantId: template.id, title: title, body: body);
  }

  final safe = pool.firstWhere(
    (t) => t.isTokenFree,
    orElse: () => const VariantTemplate('fallback', 'Even tijd voor het Woord',
        'Een paar minuten is genoeg.'),
  );
  return RenderedVariant(variantId: safe.id, title: safe.title, body: safe.body);
}

/// Picks a template from [type]'s pool by [rotation] (day index / week number),
/// so consecutive days never repeat, then renders it.
RenderedVariant pickVariant(
  NotifType type, {
  required int rotation,
  required Map<String, String?> tokens,
  bool weeklyGoalMet = false,
}) {
  var pool = notificationCopy[type] ?? const [];
  if (type == NotifType.weeklyGoal) {
    // The pool holds "behind" lines first (1..4) then "met" lines (5..8).
    pool = weeklyGoalMet ? pool.sublist(4) : pool.sublist(0, 4);
  }
  if (pool.isEmpty) {
    return const RenderedVariant(
        variantId: 'empty', title: 'Even tijd voor het Woord', body: 'Een paar minuten is genoeg.');
  }
  final template = pool[rotation.abs() % pool.length];
  return renderVariant(type, template, tokens);
}

/// Bundled Dutch fallback pools (`RETENTION_PLAN.md` §5). The server copy batch
/// (`GET /api/v1/notifications/copy?type=...`) overrides a type when present.
const Map<NotifType, List<VariantTemplate>> notificationCopy = {
  NotifType.studyReminder: [
    VariantTemplate('sr1', 'Even tijd voor {study}',
        'Les {lesson} ligt klaar. Een paar minuten is genoeg.'),
    VariantTemplate('sr2', 'Je moment met het Woord',
        'Vandaag: {lesson}. Neem de tijd die je hebt.'),
    VariantTemplate('sr3', 'Verder in {study}',
        'Waar je gebleven was, wacht rustig op je. Geen haast.'),
    VariantTemplate('sr4', 'Eén les, even stil',
        '{lesson} vraagt niet veel — alleen jou, een ogenblik.'),
    VariantTemplate('sr5', 'Klaar wanneer jij dat bent',
        '{study} staat voor je open bij {lesson}.'),
    VariantTemplate('sr6', 'Vandaag samen verder',
        'Les {lesson} van {study}. Begin waar het je uitkomt.'),
    VariantTemplate('sr7', 'Je studieplan zegt: vandaag',
        '{lesson} wacht. Vijf minuten telt ook mee.'),
    VariantTemplate('sr8', 'Stil worden bij het Woord',
        'Les {lesson}. Lees zo ver als je komt.'),
  ],
  NotifType.streakAtRisk: [
    VariantTemplate('ar1', 'Je bent {streak} dagen bezig',
        'Nog even vandaag en de reeks blijft heel. Eén korte les is genoeg.'),
    VariantTemplate('ar2', 'Nog tijd voor vandaag',
        '{streak} dagen achter elkaar — mooi volgehouden. Een paar minuten houdt het vast.'),
    VariantTemplate('ar3', 'Een kort moment nog?',
        'Je {streak}-daagse reeks wacht op de les van vandaag.'),
    VariantTemplate('ar4', 'Vandaag nog niet langs geweest',
        'Geen probleem. Eén les en je {streak} dagen staan weer.'),
    VariantTemplate('ar5', 'Bijna rond voor vandaag',
        '{streak} dagen. Een laatste stille minuut maakt het af.'),
    VariantTemplate('ar6', 'Voor het slapengaan',
        'Nog een les vandaag houdt je reeks van {streak} dagen heel.'),
    VariantTemplate('ar7', 'Je was goed op weg',
        '{streak} dagen op rij. Vandaag hoeft maar kort te zijn.'),
    VariantTemplate('ar8', 'Een klein zetje',
        'Eén les vanavond en je blijft in je ritme van {streak} dagen.'),
  ],
  NotifType.streakLost: [
    VariantTemplate('sl1', 'Welkom terug',
        'Een dag overslaan gebeurt. Je {study} ligt er nog precies zo bij.'),
    VariantTemplate('sl2', 'Gewoon weer beginnen',
        'Geen streep door alles — pak {lesson} op waar je was.'),
    VariantTemplate('sl3', 'De draad weer oppakken',
        'Je hoeft niets in te halen. Eén les vandaag is een prima start.'),
    VariantTemplate('sl4', 'Elke morgen nieuw',
        "'Zijn barmhartigheden zijn elke morgen nieuw.' Begin rustig opnieuw."),
    VariantTemplate('sl5', 'Je plek is bewaard',
        'Alles wat je deed staat er nog. Kom er even bij zitten.'),
    VariantTemplate('sl6', 'Een nieuwe reeks begint met één dag',
        'Vandaag kan die dag zijn. {lesson} wacht.'),
    VariantTemplate('sl7', 'Niets verloren',
        'Je voortgang blijft. Alleen de reeks begint opnieuw — dat mag.'),
    VariantTemplate('sl8', 'Terug in het ritme',
        'Klein beginnen werkt het best. Open {study} even.'),
  ],
  NotifType.lessonHalfway: [
    VariantTemplate('lh1', 'Je was halverwege {lesson}',
        'Nog een paar stappen en de les is af. Verder waar je stopte?'),
    VariantTemplate('lh2', '{lesson} staat nog open',
        'Je begon eraan — de rest wacht rustig op je.'),
    VariantTemplate('lh3', 'Nog even afmaken?',
        'Je liet {lesson} halverwege liggen. Het duurt niet lang meer.'),
    VariantTemplate('lh4', 'Halverwege is een goed startpunt',
        'Open {lesson} weer; je hoeft niet opnieuw te beginnen.'),
    VariantTemplate('lh5', 'Je gedachten bij {lesson}',
        'De reflectie die je begon, staat er nog. Maak het af wanneer het uitkomt.'),
    VariantTemplate('lh6', 'Een paar minuten scheelt het',
        '{lesson} in {study} is bijna klaar.'),
    VariantTemplate('lh7', 'Verder waar je was',
        '{lesson} wacht op de laatste stappen.'),
    VariantTemplate('lh8', 'Nog niet afgerond',
        'Geen haast — maar {lesson} ligt klaar om af te maken.'),
  ],
  NotifType.weeklyGoal: [
    // Behind (1..4).
    VariantTemplate('wg1', 'Nog {n} lessen deze week',
        'Je doel is {target}. Er is nog tijd genoeg.'),
    VariantTemplate('wg2', 'Halverwege de week',
        'Nog {n} te gaan voor je weekdoel. Eén vandaag helpt al.'),
    VariantTemplate('wg3', 'Je weekritme',
        '{done} van {target} gedaan. Een korte les brengt je dichterbij.'),
    VariantTemplate('wg4', 'Rustig op schema blijven',
        'Nog {n} lessen tot zondag. Geen druk, wel een herinnering.'),
    // Met (5..8).
    VariantTemplate('wg5', 'Weekdoel gehaald',
        '{target} lessen deze week. Mooi volgehouden.'),
    VariantTemplate('wg6', 'Deze week zit erop',
        'Je doel van {target} is rond. Alles daarboven is meegenomen.'),
    VariantTemplate('wg7', 'Ritme vastgehouden',
        '{done} lessen deze week — precies wat je jezelf voornam.'),
    VariantTemplate('wg8', 'Goed bezig deze week',
        'Je weekdoel staat. Rust nu gerust even.'),
  ],
  NotifType.milestone: [
    VariantTemplate('ms1', '{streak} dagen op rij',
        'Een mooie gewoonte aan het worden. Blijf zoals je bezig bent.'),
    VariantTemplate('ms2', 'Een week volgehouden',
        '7 dagen met het Woord. Iets om even bij stil te staan.'),
    VariantTemplate('ms3', '14 dagen',
        "Twee weken trouw. 'Laten wij niet moede worden in het goeddoen.'"),
    VariantTemplate('ms4', '30 dagen',
        'Een maand lang elke dag even stil. Knap gedaan, {name}.'),
    VariantTemplate('ms5', '{study} afgerond',
        'Je hebt de laatste les gedaan. Neem de tijd om terug te kijken.'),
    VariantTemplate('ms6', '{book} uitgelezen',
        '{book} helemaal doorgelezen. Op naar het volgende boek.'),
    VariantTemplate('ms7', '100 dagen',
        'Honderd dagen. Wat klein begon, is nu een vast deel van je dag.'),
    VariantTemplate('ms8', 'Nieuw zegel verdiend',
        'Er staat een nieuwe mijlpaal op je profiel.'),
  ],
  NotifType.dormant: [
    VariantTemplate('dm1', 'Een paar dagen niet langs geweest',
        'Je {study} ligt klaar bij {lesson}. Kom gerust weer even.'),
    VariantTemplate('dm2', 'Het is een weekje stil',
        'Geen zorgen — je voortgang staat er nog. Eén les om er weer in te komen.'),
    VariantTemplate('dm3', 'Je plek is bewaard',
        '{study} wacht precies waar je was, wanneer het jou uitkomt.'),
    VariantTemplate('dm4', 'Al een tijdje geleden',
        'Even een korte groet. Het Woord staat nog steeds voor je open.'),
    VariantTemplate('dm5', 'Terugkomen mag altijd',
        'Begin klein: één hoofdstuk, één stil moment.'),
    VariantTemplate('dm6', 'Een maand voorbij',
        'Je bent nog steeds welkom. {study} begint waar jij wilt.'),
    VariantTemplate('dm7', 'Nog steeds hier',
        'Geen inhaalrace, geen druk. Alleen een open Bijbel wanneer je wilt.'),
    VariantTemplate('dm8', 'De deur staat open',
        "'Komt herwaarts tot Mij.' Wanneer je zover bent."),
  ],
  NotifType.dailyVerse: [
    VariantTemplate('dv1', 'Het woord voor vandaag', '{verse} — {reference}'),
    VariantTemplate('dv2', 'Even meenemen vandaag', '{verse}'),
    VariantTemplate('dv3', 'Vers van de dag', '{reference}: {verse}'),
    VariantTemplate('dv4', 'Een gedachte om mee te dragen', '{verse} ({reference})'),
    VariantTemplate('dv5', 'Voor onderweg', '{verse} — {reference}'),
    VariantTemplate('dv6', 'Stil bij dit vers', '{reference}: {verse}'),
    VariantTemplate('dv7', 'Vandaag', '{verse}'),
    VariantTemplate('dv8', 'Uit de Schrift', '{verse} — {reference}'),
  ],
};
