import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../premium/present/paywall_route.dart';
import '../data/notes_repository.dart';
import 'notes_providers.dart';

/// The one presentation of a refused write: the server's own Dutch message,
/// plus a Pro offer when the refusal was the free note limit - where "probeer
/// het opnieuw" would only be refused again.
///
/// [messenger] and [router] are passed in rather than looked up, because the
/// caller often has to capture them before the sheet or dialog that triggered
/// the write has closed.
void showSyncRejection(
  ScaffoldMessengerState? messenger,
  GoRouter? router,
  SyncRejectedException rejection,
) {
  messenger?.showSnackBar(
    SnackBar(
      content: Text(rejection.message),
      action: rejection.proRequired && router != null
          ? SnackBarAction(
              label: 'Bekijk Pro',
              onPressed: () => openPaywallWith(router, gate: PaywallGate.notes),
            )
          : null,
    ),
  );
}

/// Shows a refusal that came back from an offline-queue flush, once.
///
/// Call from `build`. Belongs on the screens a note is written from and read
/// back on - the reader and Notities - because a flush of the offline queue
/// lands whenever the connection returns, long after the tap that queued the
/// write, with nobody awaiting it (see [syncRejectionProvider]).
///
/// The notice is consumed as it is shown, so moving between those screens does
/// not repeat it, and the notes list is refetched: the refused note is already
/// out of the queue, and dropping it from the list in the same breath as the
/// explanation is the whole point - it used to disappear on its own, later,
/// with nothing said.
void listenForSyncRejections(BuildContext context, WidgetRef ref) {
  ref.listen(syncRejectionProvider, (_, rejection) {
    if (rejection == null) return;
    ref.read(syncRejectionProvider.notifier).clear();
    ref.invalidate(notesListProvider);
    showSyncRejection(
      ScaffoldMessenger.maybeOf(context),
      GoRouter.maybeOf(context),
      rejection,
    );
  });
}
