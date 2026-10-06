import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../progress_tree/domain/verse_scene.dart';
import '../../../progress_tree/present/progress_tree_providers.dart';
import '../../../progress_tree/present/tree_view.dart';
import 'daily_verse_photo.dart';

/// The "Tekst van de dag" card's background.
///
/// The reader's own progress tree when there is one to show - the same
/// [TreeView] "Mijn voortgang" draws, seed and all, so the tree behind the
/// verse is never a stock illustration. The day's photo ([DailyVersePhoto])
/// is the fallback: `Boom verbergen`, no seed yet, or
/// [treeStateProvider] simply hasn't answered.
///
/// Watches `.select((s) => s.value)` rather than `.when(loading: ...)` on
/// purpose. The dashboard has to paint on its first frame, before the tree
/// request has had a chance to land - a loading placeholder here would be the
/// exact startup jank this card must not introduce. Null (loading, no
/// account, or a failed fetch) simply keeps today's photo, and the
/// switch to the tree happens invisibly, whenever the state arrives, on
/// whatever rebuild follows.
class DailyVerseBackdrop extends ConsumerWidget {
  const DailyVerseBackdrop({
    super.key,
    required this.scene,
    this.still = false,
  });

  final VerseScene scene;

  /// One static frame and no ticker - the off-screen share image.
  final bool still;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(treeStateProvider.select((state) => state.value));

    if (tree == null || tree.disabled || tree.seed.isEmpty) {
      return DailyVersePhoto(dayKey: scene.key);
    }

    return TreeView(
      seed: tree.seed,
      level: tree.level,
      frac: tree.progress,
      floor: tree.floor,
      health: tree.health,
      species: tree.avatar.species,
      scene: tree.avatar.scene,
      animal: tree.avatar.animal,
      // TreeView also checks MediaQuery itself, but the account-level "minder
      // beweging" pref has no MediaQuery flag to ride along with, so it has
      // to be threaded through explicitly.
      reducedMotion: tree.reducedMotion,
      still: still,
    );
  }
}
