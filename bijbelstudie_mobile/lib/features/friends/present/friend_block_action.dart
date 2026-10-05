import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/friends_repository.dart';
import 'friends_providers.dart';

/// Asks whether to block [name], and blocks them when the answer is yes.
///
/// Shared by the friend row and the post's `...` sheet so the sentence is the
/// same wherever it is asked. Returns true when the server confirmed.
///
/// The copy says what the server actually does, because blocking is the one
/// kring action that cannot be walked back from the app: `blockUser` unfriends
/// first and then blocks, and the block holds in both directions - across the
/// feed, verzoeken and contact matching - while there is no unblock route yet.
Future<bool> confirmAndBlockFriend(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String name,
}) async {
  if (userId.isEmpty) return false;
  final who = name.trim().isEmpty ? 'Deze persoon' : name.trim();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Blokkeren?'),
      content: Text(
        '$who gaat uit je kring. Jullie zien elkaars berichten en verzoeken '
        'niet meer, aan beide kanten, en jullie vinden elkaar ook niet meer '
        'via contacten. Dit kun je in de app nog niet zelf terugdraaien.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Annuleren'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Blokkeren'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final ok = await ref.read(friendsRepositoryProvider).blockFriend(userId);
  if (!context.mounted) return ok;

  if (ok) {
    ref.invalidate(friendsKringProvider);
    ref.invalidate(friendsRequestsProvider);
    // The blocked list lives on the settings response, so it has to be refetched
    // for "Geblokkeerd" to show the person that just went in it.
    ref.invalidate(friendsSettingsProvider);
    await ref.read(friendsFeedProvider.notifier).refresh();
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$who is geblokkeerd.')),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dat lukte niet. Probeer het zo nog eens.')),
    );
  }
  return ok;
}
