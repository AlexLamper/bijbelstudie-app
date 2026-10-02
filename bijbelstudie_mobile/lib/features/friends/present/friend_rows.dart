import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/friend_models.dart';
import '../data/friends_repository.dart';
import 'friend_post_card.dart';
import 'friends_providers.dart';

/// One person in the kring: name, their streak, and the plan day they are on -
/// the three things that make reading together feel like company rather than a
/// list of accounts.
///
/// Removing asks first, and is quiet rather than hidden: a kring you cannot
/// leave is a kring nobody joins.
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

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final friend = widget.friend;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
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
                  style: AppTheme.bodyStrong.copyWith(fontSize: 14, color: scheme.onSurface),
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
                      Icon(Icons.local_fire_department, size: 13, color: AppTheme.flame),
                      const SizedBox(width: 2),
                      Text('${friend.streak}', style: AppTheme.caption.copyWith(fontSize: 12.5)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _busy ? null : _remove,
            icon: const Icon(Icons.person_remove_outlined, size: 20),
            color: AppTheme.inkMuted,
            tooltip: 'Uit je kring halen',
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
      if (action == 'accept') ref.invalidate(friendsFeedProvider);
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
                  style: AppTheme.bodyStrong.copyWith(fontSize: 14, color: scheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.incoming ? 'Wil vrienden worden' : 'Verzoek verstuurd',
                  style: AppTheme.caption.copyWith(fontSize: 12.5),
                ),
              ],
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
