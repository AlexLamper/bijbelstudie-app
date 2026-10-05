import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/friends/data/friend_models.dart';
import '../../features/friends/data/friends_repository.dart';
import '../theme/app_theme.dart';

// Sharing *into* the vriendenkring, by hand.
//
// Two share actions now sit side by side on the verse card and in the note
// row's menu, and they do opposite things: the system sheet hands the verse
// out of the app, this one posts a copy in the reader's own kring. The
// wording in both places says which, because an icon cannot.
//
// VRIENDENKRING_PLAN.md §8 is the rule this file exists to keep: a tekst van
// de dag or a notitie reaches the kring *only* through an explicit tap, and
// what it posts is a copy - the body as it reads right now - never a
// reference. Editing the note afterwards leaves the post alone, which is why
// nothing here sends anything but text, a reference and [sourceId].
//
// It lives in core/ui rather than in a feature because the two callers are in
// different features (dashboard and notes) and the kring's own feature owns
// the feed, not the places that post to it.

/// What the reader chose when their kring turned out to be empty.
enum _EmptyKringChoice { invite, shareAnyway }

/// Posts [body] in the reader's vriendenkring and says how it went.
///
/// Returns true only when the server took the post. The confirmation and the
/// failure both come from [FriendShareResult.message], which is the server's
/// own Dutch line where there is one, so the app does not invent a second
/// vocabulary for the same answers.
///
/// [sourceId] is the server's idempotency handle (the verse's date, the note's
/// id) and is also how a later delete finds the post again. It identifies the
/// thing shared; it does not make the post a view of it.
Future<bool> shareIntoKring(
  BuildContext context,
  WidgetRef ref, {
  required FriendPostKind kind,
  required String body,
  String? reference,
  String? sourceId,
}) async {
  final repo = ref.read(friendsRepositoryProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);

  // A kring with nobody in it is worth saying out loud before posting: the
  // reader would otherwise get "Gedeeld met je vriendenkring" for a message
  // no one can read. Asked only when the kring really did come back empty; a
  // failed or slow answer is not an excuse to block the share.
  if (await _kringIsKnownEmpty(repo)) {
    if (!context.mounted) return false;
    final choice = await _askEmptyKring(context);
    if (choice == _EmptyKringChoice.invite) {
      if (context.mounted) context.go('/vriendenkring');
      return false;
    }
    if (choice != _EmptyKringChoice.shareAnyway) return false;
  }

  final result = await repo.sharePost(
    kind: kind,
    body: body,
    reference: reference,
    sourceId: sourceId,
  );
  messenger?.showSnackBar(
    SnackBar(
      content: Text(result.message),
      behavior: SnackBarBehavior.floating,
    ),
  );
  return result.ok;
}

/// Whether the kring is certainly empty. Unknown reads as "not empty", so a
/// network hiccup never turns into a dialog about the reader's friendships.
Future<bool> _kringIsKnownEmpty(FriendsRepository repo) async {
  try {
    return (await repo.getKring()).friends.isEmpty;
  } catch (_) {
    return false;
  }
}

Future<_EmptyKringChoice?> _askEmptyKring(BuildContext context) {
  return showDialog<_EmptyKringChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Je kring is nog leeg'),
      content: const Text(
        'Je hebt nog geen vrienden in je kring, dus dit bericht leest nu niemand. '
        'Nodig eerst iemand uit, of plaats het toch: dan staat het er zodra je '
        'eerste vriend erbij komt.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Annuleren'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_EmptyKringChoice.shareAnyway),
          child: const Text('Toch plaatsen'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_EmptyKringChoice.invite),
          style: TextButton.styleFrom(foregroundColor: AppTheme.teal),
          child: const Text('Vrienden uitnodigen'),
        ),
      ],
    ),
  );
}
