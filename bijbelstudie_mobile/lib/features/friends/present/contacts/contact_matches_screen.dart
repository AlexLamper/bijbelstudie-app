import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../data/friend_models.dart';
import '../friend_post_card.dart' show FriendAvatar;
import 'contact_discovery_providers.dart';

/// "Vrienden gevonden" - the result of one matching run, one row per account,
/// each with its own "Uitnodigen".
///
/// Nothing is sent on arriving here (`VRIENDENKRING_PLAN.md` principle 3): a
/// verzoek goes out on a tap, one row at a time, and the row says so
/// afterwards. The names and pictures come from the server's answer, never
/// from the address book - the address book's names are not even read.
///
/// Only reachable through [ContactsDisclosureScreen]; it renders whatever
/// `contactDiscoveryProvider` holds and starts nothing itself.
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

      case ContactDiscoveryStage.permissionDenied:
        return AppEmptyState(
          title: 'Geen toegang tot contacten',
          description:
              'Zonder toegang kunnen we niet zien wie de app al gebruikt. De '
              'Vriendenkring werkt ook met een uitnodigingslink of code.',
          icon: Icons.lock_outline,
          action: SiteButton(
            label: 'Opnieuw proberen',
            expand: false,
            onPressed: controller.startMatch,
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
            label: 'Instellingen openen',
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
          action: SiteButton(
            label: 'Opnieuw proberen',
            expand: false,
            onPressed: controller.startMatch,
          ),
        );

      case ContactDiscoveryStage.matched:
        if (state.found.isEmpty) {
          return const AppEmptyState(
            title: 'Nog niemand gevonden',
            description:
                'Niemand uit je contacten gebruikt BijbelStudie al, of ze willen niet '
                'gevonden worden. Je kunt iemand uitnodigen met een link of code.',
            icon: Icons.person_search_outlined,
          );
        }
        return _MatchList(found: state.found, invited: state.invited);
    }
  }
}

class _MatchList extends StatelessWidget {
  const _MatchList({required this.found, required this.invited});

  final List<FriendSummary> found;
  final Set<String> invited;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final count = found.length;
    final lead = count == 1
        ? 'Eén van je contacten gebruikt BijbelStudie al.'
        : '$count van je contacten gebruiken BijbelStudie al.';

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: count + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lead, style: AppTheme.bodyLead),
                const SizedBox(height: 4),
                Text(
                  'Nodig uit wie je wilt. Er is nog niets verstuurd.',
                  style: AppTheme.caption,
                ),
              ],
            ),
          );
        }
        final match = found[index - 1];
        return ContactMatchRow(
          match: match,
          alreadyInvited: invited.contains(match.userId),
        );
      },
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
