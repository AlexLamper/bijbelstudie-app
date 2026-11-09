import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../settings/present/vriendenkring_settings_provider.dart';
import '../../data/friend_models.dart';
import '../friend_post_card.dart' show FriendAvatar;
import '../friends_screen.dart' show InviteFriendsCard;
import 'connect_contacts_button.dart';
import 'contact_discovery_providers.dart';
import 'contact_invite_section.dart';
import 'contact_invites.dart';
import 'own_number_card.dart';

/// "Vind je vrienden" - what connecting the contacts turns up, in three
/// sections, the way the owner chose it ("alleen voorgestelde mensen", not the
/// whole address book):
///
/// 1. **In je contacten** - contacts who use BijbelStudie and are findable,
///    each with "Toevoegen" (a vriendschapsverzoek, on a tap).
/// 2. **Mensen die je misschien kent** - friends of friends, with how many
///    friends are shared (`GET /friends/suggestions`).
/// 3. **Nodig uit** - about ten contacts without the app, plus a search field,
///    each with "Uitnodigen" through WhatsApp, SMS or the share sheet.
///
/// Nothing is sent on arriving here (`VRIENDENKRING_PLAN.md` principle 3). The
/// names in "Nodig uit" come from the address book on this phone and are never
/// uploaded; the names in the first two sections come from the server.
///
/// **It is never blank.** That is the bug this screen used to have on iPhone:
/// matching only ever finds people who made themselves findable, which almost
/// nobody had, so a perfectly working run ended on "niemand gevonden" and
/// nothing else. Now every stage - including the refusals and failures, which
/// each still say what happened - ends with a way to reach people: the invite
/// list when the address book could be read, the link and code otherwise.
class ContactMatchesScreen extends ConsumerWidget {
  const ContactMatchesScreen({super.key});

  static const routePath = '/vriendenkring/contacten/gevonden';
  static const routeName = 'vriendenkring-contacten-gevonden';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final state = ref.watch(contactDiscoveryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Vind je vrienden')),
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
      case ContactDiscoveryStage.working:
        return const _Working();

      // Nothing ran yet, or a caller skipped the disclosure (the gate held).
      // Either way: the card that carries the disclosure, then the link.
      case ContactDiscoveryStage.idle:
      case ContactDiscoveryStage.needsDisclosure:
        return _WithFallback(
          children: [
            ConnectContactsButton(onPressed: controller.acceptDisclosureAndStart),
          ],
        );

      // Switched off server-side. Not a fault, so not an error card.
      case ContactDiscoveryStage.unavailable:
        return const _WithFallback(
          children: [
            AppEmptyState(
              title: 'Dit kan nu niet',
              description:
                  'Zoeken via contacten is op dit moment niet beschikbaar. Je kunt wel '
                  'iemand uitnodigen met een link of code.',
              icon: Icons.contacts_outlined,
            ),
          ],
        );

      // Refused, and askable again - which is what Android means by it. On
      // iPhone a single "Sta niet toe" is already permanent, so Settings is
      // offered beside the retry rather than instead of it.
      case ContactDiscoveryStage.permissionDenied:
        return _WithFallback(
          children: [
            AppEmptyState(
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
            ),
          ],
        );

      case ContactDiscoveryStage.permissionBlocked:
        return _WithFallback(
          children: [
            AppEmptyState(
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
            ),
          ],
        );

      case ContactDiscoveryStage.emptyAddressBook:
        return const _WithFallback(
          children: [
            AppEmptyState(
              title: 'Niets om te vergelijken',
              description:
                  'In je contacten staan geen telefoonnummers of e-mailadressen die we '
                  'kunnen vergelijken.',
              icon: Icons.contact_page_outlined,
            ),
          ],
        );

      // The book may well have been read before the run failed (a rate limit,
      // a server hiccup), and then "Nodig uit" still works - it never needed
      // the server.
      case ContactDiscoveryStage.failed:
        final haveBook = ref.watch(inviteCandidatesProvider).isNotEmpty;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            AppEmptyState(
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
            ),
            const SizedBox(height: 20),
            if (haveBook) const ContactInviteSection() else const InviteFriendsCard(),
          ],
        );

      case ContactDiscoveryStage.matched:
        return _MatchList(found: state.found, invited: state.invited);
    }
  }
}

/// A stage's own message, then the link-and-code card, so no stage is a dead
/// end.
class _WithFallback extends StatelessWidget {
  const _WithFallback({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        ...children,
        const SizedBox(height: 20),
        Text(
          'Of nodig iemand uit met je link of code.',
          style: AppTheme.caption.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 10),
        const InviteFriendsCard(),
      ],
    );
  }
}

class _Working extends StatelessWidget {
  const _Working();

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLoader(),
          const SizedBox(height: 14),
          Text('We kijken wie je kent...', style: AppTheme.caption.copyWith(fontSize: 13)),
        ],
      ),
    );
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

/// The three sections, in order.
class _MatchList extends ConsumerWidget {
  const _MatchList({required this.found, required this.invited});

  final List<FriendSummary> found;
  final Set<String> invited;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final count = found.length;
    final alertsOn = ref.watch(vriendenkringSettingsProvider).value?.contactJoinAlerts ?? true;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Text(
          count == 0
              ? 'Er is nog niets verstuurd. Kies zelf wie je toevoegt of uitnodigt.'
              : 'Er is nog niets verstuurd. Voeg toe wie je wilt.',
          style: AppTheme.caption.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 16),
        SectionHeader(
          title: 'In je contacten',
          description: count == 0
              ? null
              : (count == 1
                    ? 'Eén van je contacten gebruikt BijbelStudie al.'
                    : '$count van je contacten gebruiken BijbelStudie al.'),
        ),
        const SizedBox(height: 10),
        if (count == 0)
          AppCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Text(
              alertsOn
                  ? 'Nog niemand uit je contacten gevonden. Komt er iemand bij die vindbaar '
                        'is, dan krijg je een melding.'
                  : 'Nog niemand uit je contacten gevonden. Alleen mensen die vindbaar zijn, '
                        'zie je hier.',
              style: AppTheme.caption.copyWith(fontSize: 13, height: 1.45),
            ),
          )
        else
          for (final match in found) ...[
            ContactMatchRow(match: match, alreadyInvited: invited.contains(match.userId)),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 12),
        // Matters most when nothing was found: the people in this address
        // book can only find this reader back once a number is registered.
        const OwnNumberCard(),
        SecondCircleSection(exclude: {for (final person in found) person.userId}),
        const SizedBox(height: 28),
        const ContactInviteSection(),
      ],
    );
  }
}

/// One found account, with the one action it offers: "Toevoegen", which sends
/// a vriendschapsverzoek. Never called "Uitnodigen" - that word belongs to the
/// contacts without the app, further down.
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
                  'Verzoek verstuurd',
                  style: AppTheme.caption.copyWith(fontSize: 12.5, color: AppTheme.teal),
                ),
              ],
            )
          else
            SiteButton(
              label: 'Toevoegen',
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
