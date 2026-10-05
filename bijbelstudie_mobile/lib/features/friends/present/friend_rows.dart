import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/permission_moment.dart'
    show maybeAskAfterFriendAction;
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/friend_models.dart';
import '../data/friends_repository.dart';
import 'friend_block_action.dart';
import 'friend_post_card.dart';
import 'friend_profile_screen.dart' show openFriendProfile;
import 'friend_tap_target.dart';
import 'friends_providers.dart';

/// One person in the kring: name, their streak, and the plan day they are on -
/// the three things that make reading together feel like company rather than a
/// list of accounts.
///
/// Removing asks first, and is quiet rather than hidden: a kring you cannot
/// leave is a kring nobody joins. Blocking sits in the same menu, one step
/// further: it asks too, and says that it holds both ways.
class FriendRow extends ConsumerStatefulWidget {
  const FriendRow({super.key, required this.friend});

  final FriendSummary friend;

  @override
  ConsumerState<FriendRow> createState() => _FriendRowState();
}

class _FriendRowState extends ConsumerState<FriendRow> {
  bool _busy = false;

  Future<void> _remove() async {
    final name = widget.friend.name.isEmpty ? 'deze vriend' : widget.friend.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uit je kring halen?'),
        content: Text('$name ziet jouw berichten dan niet meer, en jij die van hen niet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final ok = await ref.read(friendsRepositoryProvider).removeFriend(widget.friend.userId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(friendsKringProvider);
      ref.invalidate(friendsFeedProvider);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dat lukte niet. Probeer het zo nog eens.')),
      );
    }
  }

  /// Harder than removing, and said so before it happens.
  Future<void> _block() async {
    setState(() => _busy = true);
    await confirmAndBlockFriend(
      context,
      ref,
      userId: widget.friend.userId,
      name: widget.friend.name,
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final friend = widget.friend;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        children: [
          // The face and the two lines open `/vriendenkring/<id>`; the menu
          // beside them keeps its own taps.
          Expanded(
            child: FriendTapTarget(
              onTap: () => openFriendProfile(context, friend.userId),
              child: Row(
                children: [
                  FriendAvatar(name: friend.name, image: friend.image, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          friend.name.isEmpty ? 'Een vriend' : friend.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyStrong.copyWith(
                            fontSize: 14,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                friend.planLabel ?? 'Leest mee',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.caption.copyWith(fontSize: 12.5),
                              ),
                            ),
                            if (friend.streak > 0) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.local_fire_department,
                                size: 13,
                                color: AppTheme.flame,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${friend.streak}',
                                style: AppTheme.caption.copyWith(fontSize: 12.5),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            enabled: !_busy,
            icon: Icon(Icons.more_horiz, size: 20, color: AppTheme.inkMuted),
            tooltip: 'Meer',
            onSelected: (value) {
              if (value == 'remove') _remove();
              if (value == 'block') _block();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'remove',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.person_remove_outlined, size: 20),
                  title: Text('Uit je kring halen'),
                ),
              ),
              PopupMenuItem(
                value: 'block',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.block_outlined, size: 20),
                  title: Text('Blokkeren'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One person the reader blocked, with the way back.
///
/// Lifting a block does not restore the vriendschap - blocking deleted the
/// pair document - so the confirmation says that before it happens, rather
/// than leaving the reader to discover it.
class BlockedUserRow extends ConsumerStatefulWidget {
  const BlockedUserRow({super.key, required this.user});

  final BlockedUser user;

  @override
  ConsumerState<BlockedUserRow> createState() => _BlockedUserRowState();
}

class _BlockedUserRowState extends ConsumerState<BlockedUserRow> {
  bool _busy = false;

  Future<void> _unblock() async {
    final who = widget.user.name.trim().isEmpty ? 'Deze persoon' : widget.user.name.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Blokkering opheffen?'),
        content: Text(
          '$who kan je daarna weer vinden en een verzoek sturen. Jullie worden '
          'niet automatisch weer vrienden: dat vraagt een nieuw verzoek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Opheffen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final result = await ref.read(friendsRepositoryProvider).unblockFriend(widget.user.userId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) ref.invalidate(friendsSettingsProvider);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final user = widget.user;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          FriendAvatar(name: user.name, image: user.image, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              user.name.isEmpty ? 'Iemand' : user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodyStrong.copyWith(fontSize: 14, color: scheme.onSurface),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _busy ? null : _unblock,
            child: const Text('Opheffen'),
          ),
        ],
      ),
    );
  }
}

/// A pending verzoek. Incoming gets "Accepteren" and a quiet "Weigeren";
/// outgoing gets "Intrekken" - there is nothing to decide on your own request.
class FriendRequestRow extends ConsumerStatefulWidget {
  const FriendRequestRow({super.key, required this.request, required this.incoming});

  final FriendRequestView request;
  final bool incoming;

  @override
  ConsumerState<FriendRequestRow> createState() => _FriendRequestRowState();
}

class _FriendRequestRowState extends ConsumerState<FriendRequestRow> {
  bool _busy = false;

  Future<void> _act(String action) async {
    setState(() => _busy = true);
    final ok = await ref
        .read(friendsRepositoryProvider)
        .respondToRequest(widget.request.id, action);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(friendsRequestsProvider);
      ref.invalidate(friendsKringProvider);
      if (action == 'accept') {
        ref.invalidate(friendsFeedProvider);
        // The earned moment for the social notifications: somebody is in the
        // kring now, so "wil je het weten als er iets gebeurt" has an answer
        // worth giving. A no-op after the first time, and never at launch.
        await maybeAskAfterFriendAction(context, ref);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dat lukte niet. Probeer het zo nog eens.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final user = widget.request.user;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          // Who is asking is worth looking at before answering, so the name
          // opens their profile here too.
          Expanded(
            child: FriendTapTarget(
              onTap: () => openFriendProfile(context, user.userId),
              child: Row(
                children: [
                  FriendAvatar(name: user.name, image: user.image, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name.isEmpty ? 'Iemand' : user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyStrong.copyWith(
                            fontSize: 14,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.incoming ? 'Wil vrienden worden' : 'Verzoek verstuurd',
                          style: AppTheme.caption.copyWith(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (widget.incoming) ...[
            BibleYearStyleButton(
              label: 'Accepteren',
              onPressed: _busy ? null : () => _act('accept'),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: _busy ? null : () => _act('decline'),
              child: const Text('Weigeren'),
            ),
          ] else
            TextButton(
              onPressed: _busy ? null : () => _act('cancel'),
              child: const Text('Intrekken'),
            ),
        ],
      ),
    );
  }
}

/// The small filled pill the request row uses. [SiteButton] is full-width by
/// default and 48 high; inside a row this has to be the compact one.
class BibleYearStyleButton extends StatelessWidget {
  const BibleYearStyleButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return SiteButton(label: label, onPressed: onPressed, expand: false, height: 40);
  }
}
