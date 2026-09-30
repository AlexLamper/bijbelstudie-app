import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/present/auth_controller.dart' show sessionAccountProvider;

/// How long a network-backed provider keeps its value after the last listener
/// leaves. Long enough that switching tabs and coming back is instant, short
/// enough that a tab left open for a while still refetches on the next visit.
const Duration kProviderCacheWindow = Duration(minutes: 5);

extension ProviderCache on Ref {
  /// Keeps an `autoDispose` provider alive for [duration] after its last
  /// listener goes away.
  ///
  /// Without this every tab switch disposes the provider, so returning to the
  /// Start or Profiel tab throws away data the app already had and shows a
  /// skeleton while it is fetched again. Mutations still call
  /// `ref.invalidate(...)`, which drops the cached value immediately, so the
  /// window never serves data the app knows to be stale.
  ///
  /// It is also what scopes these caches to the signed-in account: when a
  /// different account signs in, the link is released and the provider
  /// invalidated. One nobody is watching is disposed outright - a rebuild
  /// would carry the previous reader's value along as `AsyncLoading.value`,
  /// which the screens render - and one still watched refetches.
  void cacheFor([Duration duration = kProviderCacheWindow]) {
    final link = keepAlive();
    Timer? timer;

    listen(sessionAccountProvider, (_, _) {
      timer?.cancel();
      link.close();
      invalidateSelf();
    });

    onCancel(() {
      timer?.cancel();
      timer = Timer(duration, link.close);
    });
    onResume(() {
      timer?.cancel();
      timer = null;
    });
    onDispose(() => timer?.cancel());
  }
}
