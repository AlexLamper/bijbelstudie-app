import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/provider_cache.dart';
import '../data/levensboom_repository.dart';
import '../domain/tree_state.dart';

/// The tree's state, and the bus every XP-earning screen pushes into.
///
/// There is no realtime infrastructure anywhere in this product - every call is
/// request/response - so the pattern is the one the streak flow already uses:
/// the server owns the arithmetic and returns the `GrantResult`, the client
/// applies it immediately so the bar moves and leaves unfurl without a second
/// round trip, and the next fetch reconciles. Both sides run the same level
/// curve, so they agree.

class TreeStateNotifier extends AsyncNotifier<TreeState> {
  @override
  Future<TreeState> build() async {
    ref.cacheFor();
    final repository = ref.watch(levensboomRepositoryProvider);

    // Show the cached tree while the request is in flight, so the Profiel tab
    // never opens on an empty sky.
    final cached = await repository.cached();
    if (cached != null && state is AsyncLoading) {
      state = AsyncData(cached);
    }

    return repository.fetch();
  }

  Future<void> refresh() async {
    final repository = ref.read(levensboomRepositoryProvider);
    try {
      state = AsyncData(await repository.fetch());
    } catch (_) {
      // Keep whatever is on screen. A failed refresh must never blank the tree.
    }
  }

  /// Applies an XP grant returned by an action endpoint.
  void applyGrant(XpGrant grant) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.applyGrant(grant));
  }

  /// Called when the celebration for [level] has been shown.
  Future<void> markSeen(int level) async {
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(lastSeenLevel: level));
    }
    try {
      await ref.read(levensboomRepositoryProvider).markSeen(level: level);
    } catch (_) {
      // Worst case it celebrates once more on the next cold start.
    }
  }

  Future<void> setPrefs({bool? reducedMotion, bool? disabled}) async {
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        current.copyWith(reducedMotion: reducedMotion, disabled: disabled),
      );
    }
    try {
      await ref
          .read(levensboomRepositoryProvider)
          .markSeen(reducedMotion: reducedMotion, disabled: disabled);
    } catch (_) {
      // Cosmetic; the next toggle retries the write.
    }
  }
}

final treeStateProvider = AsyncNotifierProvider<TreeStateNotifier, TreeState>(
  TreeStateNotifier.new,
);

/// The one-shot animation bus.
///
/// A screen that has just earned XP pushes the grant here; the tree animates it
/// if it happens to be mounted, and the celebration route reads [pendingLevelUp]
/// either way. Nothing is persisted - a level-up that is missed because no tree
/// was on screen is picked up from `lastSeenLevel` on the next fetch.
class TreeAnimationEvent {
  const TreeAnimationEvent({required this.grant, required this.at});

  final XpGrant grant;
  final DateTime at;
}

class TreeAnimationBus extends Notifier<TreeAnimationEvent?> {
  @override
  TreeAnimationEvent? build() => null;

  void push(Object? rawXp) {
    final grant = XpGrant.fromJson(rawXp);
    if (grant == null) return;
    ref.read(treeStateProvider.notifier).applyGrant(grant);
    state = TreeAnimationEvent(grant: grant, at: DateTime.now());
  }

  /// Consumed by whichever widget rendered it, so it fires exactly once.
  void clear() => state = null;
}

final treeAnimationEventProvider =
    NotifierProvider<TreeAnimationBus, TreeAnimationEvent?>(TreeAnimationBus.new);

/// The level whose celebration is owed, or null. Covers both routes in: an
/// XP call that levelled up just now, and a level-up earned on another device.
final pendingLevelUpProvider = Provider.autoDispose<int?>((ref) {
  final tree = ref.watch(treeStateProvider).value;
  if (tree == null || tree.disabled) return null;
  return tree.shouldCelebrate ? tree.level : null;
});
