import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../data/friend_models.dart';
import '../friend_post_card.dart' show FriendAvatar;
import '../friend_suggestions_section.dart' show FriendSuggestionRow;
import '../friends_providers.dart';
import 'contact_discovery_providers.dart';
import 'own_number_card.dart';

/// "Vrienden gevonden" - the result of one matching run, one row per account,
/// each with its own "Uitnodigen", and under it the people who are one step
/// further away: contacten van contacten.
///
/// Nothing is sent on arriving here (`VRIENDENKRING_PLAN.md` principle 3): a
/// verzoek goes out on a tap, one row at a time, and the row says so
/// afterwards. The names and pictures come from the server's answer, never
/// from the address book - the address book's names are not even read.
///
/// Reached straight from "Verbind Contacten", which carries the disclosure; it
/// renders whatever `contactDiscoveryProvider` holds and starts nothing itself.
/// Every way a run can fail has its own words here, and the ones only the
/// Settings app can fix offer that route - an empty list for a refused
/// permission is how this looked broken on iPhone and said nothing.
class ContactMatchesScreen extends ConsumerWidget {
  const ContactMatchesScreen({super.key});

  static const routePath = '/vriendenkring/contacten/gevonden';
  static const routeName = 'vriendenkring-contacten-gevonden';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final state = ref.watch(contactDiscoveryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Vrienden gevonden')),
      body: SafeArea(child: _Body(state: state)),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state});

  final ContactDiscoveryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(contactDiscoveryProvider.notifier);

    switch (state.stage) {
      case ContactDiscoveryStage.idle:
      case ContactDiscoveryStage.working:
        return const Padding(
          padding: EdgeInsets.all(40),
          child: AppLoader(),
        );

      // The disclosure has not been passed, so nothing was asked and nothing
      // read. Reaching this means a caller skipped the screen; the gate held.
      case ContactDiscoveryStage.needsDisclosure:
        return const AppEmptyState(
          title: 'Eerst even uitleggen',
          description:
              'We vertellen je eerst wat we lezen en versturen, voordat we iets vragen. '
              'Ga terug en begin opnieuw.',
          icon: Icons.info_outline,
        );

      // Switched off server-side. Not a fault, so not an error card.
      case ContactDiscoveryStage.unavailable:
        return const AppEmptyState(
          title: 'Dit kan nu niet',
          description:
              'Zoeken via contacten is op dit moment niet beschikbaar. Je kunt wel '
              'iemand uitnodigen met een link of code.',
          icon: Icons.contacts_outlined,
        );

      // Refused, and askable again - which is what Android means by it. On
      // iPhone a single "Sta niet toe" is already permanent, so Settings is
      // offered beside the retry rather than instead of it.
      case ContactDiscoveryStage.permissionDenied:
        return AppEmptyState(
          title: 'Geen toegang tot contacten',
          description:
              'Zonder toegang kunnen we niet zien wie de app al gebruikt. Op een '
              'iPhone kun je dit alleen weer aanzetten in de instellingen. De '
              'Vriendenkring werkt ook met een uitnodigingslink of code.',
          icon: Icons.lock_outline,
          action: _TwoWaysOut(
            retry: controller.startMatch,
            settings: controller.openSystemSettings,
          ),
        );

      case ContactDiscoveryStage.permissionBlocked:
        return AppEmptyState(
          title: 'Toegang staat uit',
          description:
              'Contacten staat voor BijbelStudie uit in de instellingen van je '
              'telefoon. Je kunt het daar weer aanzetten.',
          icon: Icons.settings_outlined,
          action: SiteButton(
            label: 'Open instellingen',
            expand: false,
            onPressed: controller.openSystemSettings,
          ),
        );

      case ContactDiscoveryStage.emptyAddressBook:
        return const AppEmptyState(
          title: 'Niets om te vergelijken',
          description:
              'In je contacten staan geen telefoonnummers of e-mailadressen die we '
              'kunnen vergelijken.',
          icon: Icons.contact_page_outlined,
        );

      case ContactDiscoveryStage.failed:
        return AppEmptyState(
          title: 'Dat lukte niet',
          description: state.message ?? 'Probeer het zo nog eens.',
          icon: Icons.error_outline,
          action: state.offerSettings
              ? _TwoWaysOut(
                  retry: controller.startMatch,
                  settings: controller.openSystemSettings,
                )
              : SiteButton(
                  label: 'Opnieuw proberen',
                  expand: false,
                  onPressed: controller.startMatch,
                ),
        );

      case ContactDiscoveryStage.matched:
        return _MatchList(found: state.found, invited: state.invited);
    }
  }
}

/// "Opnieuw proberen" and "Open instellingen", side by side.
///
/// Both, not one: Android can still show the dialog again, iPhone cannot, and
/// the screen does not know which phone it is on (nor should it guess - a
/// reader who revoked access in Settings is in the same state on both).
class _TwoWaysOut extends StatelessWidget {
  const _TwoWaysOut({required this.retry, required this.settings});

  final VoidCallback retry;
  final VoidCallback settings;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SiteButton(label: 'Opnieuw proberen', expand: false, onPressed: retry),
        const SizedBox(height: 6),
        TextButton(onPressed: settings, child: const Text('Open instellingen')),
      ],
    );
  }
}

/// The direct matches, then the second circle under them.
///
/// Two sections rather than one list, because the two answers to "how do I
/// know this person?" are different and a row that cannot say which is a row
/// nobody taps. The first is "in je contacten" and comes from the match run;
/// the second is friends-of-friends and comes from `GET /friends/suggestions`,
/// which already carries `mutualCount` per row - no graph is built here.
class _MatchList extends ConsumerWidget {
  const _MatchList({required this.found, required this.invited});

  final List<FriendSummary> found;
  final Set<String> invited;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final count = found.length;
    final lead = count == 0
        ? 'Nog niemand uit je contacten gevonden.'
        : (count == 1
              ? 'Eén van je contacten gebruikt BijbelStudie al.'
              : '$count van je contacten gebruiken BijbelStudie al.');

    // `.value` on purpose: loading and a failure both read as "no second
    // circle yet". This screen is about the contacts; the suggestions are a
    // bonus and must not be able to turn it into an error.
    final suggestions =
        ref.watch(friendSuggestionsProvider).value?.suggestions ?? const <FriendSummary>[];
    final directIds = {for (final person in found) person.userId};
    // Only the ones that are there *through somebody*: a row with no friends
    // in common has nothing to put under its name, and a contact match
    // already had its turn above.
    final secondDegree = [
      for (final person in suggestions)
        if (!directIds.contains(person.userId) && person.mutualLabel != null) person,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Text(lead, style: AppTheme.bodyLead),
        const SizedBox(height: 4),
        Text(
          count == 0
              ? 'Zodra iemand uit je contacten erbij komt, zie je diegene hier.'
              : 'Nodig uit wie je wilt. Er is nog niets verstuurd.',
          style: AppTheme.caption,
        ),
        const SizedBox(height: 12),
        // Matters most when nothing was found: an empty result usually means
        // "zij hebben nog niet verbonden", and the way to be found when they
        // do is to have a number registered now.
        const OwnNumberCard(),
        const SizedBox(height: 8),
        for (final match in found) ...[
          ContactMatchRow(
            match: match,
            alreadyInvited: invited.contains(match.userId),
          ),
          const SizedBox(height: 8),
        ],
        if (count == 0 && secondDegree.isEmpty)
          const AppEmptyState(
            title: 'Nog niemand gevonden',
            description:
                'Niemand uit je contacten gebruikt BijbelStudie al, of ze willen niet '
                'gevonden worden. Je kunt ook iemand uitnodigen met een link of code.',
            icon: Icons.person_search_outlined,
          ),
        if (secondDegree.isNotEmpty) ...[
          const SizedBox(height: 12),
          const SectionHeader(
            title: 'Contacten van contacten',
            description: 'Via de mensen in je kring.',
          ),
          const SizedBox(height: 10),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < secondDegree.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: AppTheme.rule),
                  FriendSuggestionRow(person: secondDegree[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One found account, with the one action it offers.
class ContactMatchRow extends ConsumerStatefulWidget {
  const ContactMatchRow({super.key, required this.match, this.alreadyInvited = false});

  final FriendSummary match;
  final bool alreadyInvited;

  @override
  ConsumerState<ContactMatchRow> createState() => _ContactMatchRowState();
}

class _ContactMatchRowState extends ConsumerState<ContactMatchRow> {
  bool _busy = false;

  Future<void> _invite() async {
    setState(() => _busy = true);
    final result = await ref
        .read(contactDiscoveryProvider.notifier)
        .inviteMatch(widget.match);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final match = widget.match;
    final name = match.name.isEmpty ? 'Iemand uit je contacten' : match.name;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          FriendAvatar(name: match.name, image: match.image, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyStrong.copyWith(fontSize: 14, color: scheme.onSurface),
                ),
                if (match.mutualLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    match.mutualLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (widget.alreadyInvited)
            Row(
              children: [
                Icon(Icons.check, size: 16, color: AppTheme.teal),
                const SizedBox(width: 4),
                Text(
                  'Uitgenodigd',
                  style: AppTheme.caption.copyWith(fontSize: 12.5, color: AppTheme.teal),
                ),
              ],
            )
          else
            SiteButton(
              label: 'Uitnodigen',
              expand: false,
              height: 38,
              loading: _busy,
              onPressed: _invite,
            ),
        ],
      ),
    );
  }
}
