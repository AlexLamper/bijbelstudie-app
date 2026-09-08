import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'levensboom_providers.dart';
import 'tree_view.dart';

/// The Profiel tab's icon: the reader's own tree at 24 px.
///
/// The same identity in the tab bar as in the header, on Profiel and on the
/// website's navbar. A still frame - the tab bar is on screen for the whole
/// session, and a 24 px sway would only heat the phone. The person icon stands
/// in while the state loads, and when the reader has switched the tree off.
class LevensboomTabIcon extends ConsumerWidget {
  const LevensboomTabIcon({super.key, required this.active, this.size = 24});

  final bool active;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(treeStateProvider).value;
    if (tree == null || tree.disabled || tree.seed.isEmpty) {
      return Icon(
        active ? Icons.person : Icons.person_outline,
        size: 21,
        color: active ? AppTheme.teal : AppTheme.inkMuted,
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? AppTheme.teal : AppTheme.rule,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: ClipOval(
            child: TreeView(
              seed: tree.seed,
              level: tree.level,
              frac: tree.progress,
              health: tree.health,
              species: tree.avatar.species,
              scene: tree.avatar.scene,
              animal: tree.avatar.animal,
              framing: TreeFraming.portrait,
              still: true,
            ),
          ),
        ),
      ),
    );
  }
}
