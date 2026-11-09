import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../referral/data/referral_repository.dart';
import '../../data/friend_models.dart';
import '../friend_post_card.dart' show FriendAvatar;
import '../friend_suggestions_section.dart' show FriendSuggestionRow;
import '../friends_providers.dart';
import 'contact_invites.dart';

/// "Nodig uit": about ten people from the reader's address book who do not use
/// BijbelStudie yet, a search field for anyone else in it, and per row an
/// "Uitnodigen" that opens WhatsApp (or SMS, or the share sheet) with the
/// reader's own invite link filled in.
///
/// The rows are built on this phone from the address book in memory
/// ([contactInvitesProvider]); the server never sees a name or a number, and
/// the message is sent by the reader from their own app. A row that was
/// invited says "Uitgenodigd" from then on, remembered on this phone only.
///
/// Never blank: with nobody to list - an address book with no mobile numbers,
/// or contacts that cannot be read right now - it still offers the link.
class ContactInviteSection extends ConsumerStatefulWidget {
  const ContactInviteSection({super.key, this.showHeader = true});

  final bool showHeader;

  @override
  ConsumerState<ContactInviteSection> createState() => _ContactInviteSectionState();
}

class _ContactInviteSectionState extends ConsumerState<ContactInviteSection> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // After a restart the book is not in memory yet; read it if the reader
    // already connected their contacts. Never shows a dialog.
    Future.microtask(() => ref.read(contactInvitesProvider.notifier).loadIfConnected());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _shareLink() async {
    final overview = ref.read(referralOverviewProvider).value;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    await Share.share(inviteLine(overview?.shareText), sharePositionOrigin: origin);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final all = ref.watch(inviteCandidatesProvider);
    final invited = ref.watch(contactInvitesProvider.select((state) => state.invitedEntryIds));
    final overview = ref.watch(referralOverviewProvider).value;
    final rows = _query.trim().isEmpty ? suggestedInvitees(all) : searchInvitees(all, _query);

    final description = overview?.youEarn == true
        ? 'Zij hebben BijbelStudie nog niet. Maakt iemand via jouw link een account, dan krijgen jullie allebei een week Pro.'
        : 'Zij hebben BijbelStudie nog niet. Wie via jouw link een account maakt, krijgt een week Pro.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader) ...[
          SectionHeader(title: 'Nodig uit', description: description),
          const SizedBox(height: 12),
        ],
        if (all.isNotEmpty) ...[
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Zoek in je contacten',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Wissen',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (rows.isNotEmpty)
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: AppTheme.rule),
                  ContactInviteRow(
                    candidate: rows[i],
                    invited: invited.contains(rows[i].entryId),
                  ),
                ],
              ],
            ),
          )
        else if (_query.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Niemand gevonden met "${_query.trim()}".',
              style: AppTheme.caption.copyWith(fontSize: 13),
            ),
          )
        else
          Text(
            'We vonden geen contacten met een mobiel nummer om uit te nodigen. Je kunt je link '
            'ook zelf delen.',
            style: AppTheme.caption.copyWith(fontSize: 13),
          ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _shareLink,
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text('Je link delen'),
          ),
        ),
      ],
    );
  }
}

/// One contact without the app, and the one thing to do with it.
class ContactInviteRow extends ConsumerStatefulWidget {
  const ContactInviteRow({super.key, required this.candidate, this.invited = false});

  final InviteCandidate candidate;
  final bool invited;

  @override
  ConsumerState<ContactInviteRow> createState() => _ContactInviteRowState();
}

class _ContactInviteRowState extends ConsumerState<ContactInviteRow> {
  bool _busy = false;

  Future<void> _invite() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final overview = ref.read(referralOverviewProvider).value;
    final channel = await ref
        .read(contactInvitesProvider.notifier)
        .invite(widget.candidate, shareText: overview?.shareText, origin: origin);
    if (!mounted) return;
    setState(() => _busy = false);
    if (channel == InviteChannel.none) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Dat lukte niet. Deel je link met de knop hieronder.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final candidate = widget.candidate;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          FriendAvatar(name: candidate.displayName, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              candidate.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodyStrong.copyWith(fontSize: 14, color: scheme.onSurface),
            ),
          ),
          const SizedBox(width: 8),
          if (widget.invited)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, size: 16, color: AppTheme.teal),
                  const SizedBox(width: 4),
                  Text(
                    'Uitgenodigd',
                    style: AppTheme.caption.copyWith(fontSize: 12.5, color: AppTheme.teal),
                  ),
                ],
              ),
            )
          else
            SiteOutlineButton(
              label: 'Uitnodigen',
              expand: false,
              height: 38,
              onPressed: _busy ? null : _invite,
            ),
        ],
      ),
    );
  }
}

/// "Mensen die je misschien kent" as the contacts screens show it: friends of
/// friends, with how many friends are shared, minus the people already listed
/// under "In je contacten". Renders nothing when there are none - a new reader
/// with no kring has no second circle yet, and saying so helps nobody.
class SecondCircleSection extends ConsumerWidget {
  const SecondCircleSection({super.key, this.exclude = const {}});

  /// User ids already shown above.
  final Set<String> exclude;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final suggestions =
        ref.watch(friendSuggestionsProvider).value?.suggestions ?? const <FriendSummary>[];
    final people = [
      for (final person in suggestions)
        if (!exclude.contains(person.userId) && !person.inContacts && person.mutualLabel != null)
          person,
    ];
    if (people.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Mensen die je misschien kent',
            description: 'Via de mensen in je kring.',
          ),
          const SizedBox(height: 10),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < people.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: AppTheme.rule),
                  FriendSuggestionRow(person: people[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
