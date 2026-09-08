import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/catalog.dart';
import '../../domain/tree_state.dart';
import '../levensboom_avatar.dart';
import '../tree_view.dart';

/// One tile per catalog item, drawn as the reader's own tree wearing that item,
/// so a species tile shows *their* lean and a scene tile *their* canopy on that
/// backdrop. Lock state and rule come from the served `unlocked` set; the
/// client never decides.
class StudioTileGrid extends StatelessWidget {
  const StudioTileGrid({
    super.key,
    required this.kind,
    required this.tree,
    required this.previewId,
    required this.onPick,
  });

  final ItemKind kind;
  final TreeState tree;
  final String? previewId;
  final ValueChanged<CatalogItem> onPick;

  @override
  Widget build(BuildContext context) {
    final items = itemsOfKind(kind);
    final selectedId = tree.chosen.idFor(kind);
    final square = kind == ItemKind.species || kind == ItemKind.ring;
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: square ? 3 : 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: square ? 0.72 : 0.98,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = items[index];
          return StudioTile(
            item: item,
            tree: tree,
            selected: selectedId == item.id,
            previewing: previewId == item.id,
            locked: !tree.unlocked.contains(item.key),
            isNew: item.unlock is! FreeUnlock &&
                tree.unlocked.contains(item.key) &&
                !tree.seenItems.contains(item.key),
            onTap: () => onPick(item),
          );
        },
        childCount: items.length,
      ),
    );
  }
}

class StudioTile extends StatelessWidget {
  const StudioTile({
    super.key,
    required this.item,
    required this.tree,
    required this.selected,
    required this.previewing,
    required this.locked,
    required this.isNew,
    required this.onTap,
  });

  final CatalogItem item;
  final TreeState tree;
  final bool selected;
  final bool previewing;
  final bool locked;
  final bool isNew;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pro = item.unlock is ProUnlock;
    final outline = selected
        ? AppTheme.teal
        : previewing
        ? AppTheme.teal.withValues(alpha: 0.5)
        : AppTheme.rule;

    return Semantics(
      button: true,
      selected: selected,
      label: locked ? '${item.name}, vergrendeld: ${unlockLabel(item.unlock)}' : item.name,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              border: Border.all(color: outline, width: selected ? 2 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        opacity: locked ? 0.7 : 1,
                        child: _Thumb(item: item, tree: tree),
                      ),
                      if (locked)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.lock_outline, size: 11, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  unlockLabel(item.unlock),
                                  style: AppTheme.caption.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (selected && !locked)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(color: AppTheme.teal, shape: BoxShape.circle),
                            child: const Icon(Icons.check, size: 14, color: Colors.white),
                          ),
                        ),
                      if (isNew && !selected)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                            ),
                            child: Text(
                              'NIEUW',
                              style: AppTheme.caption.copyWith(
                                color: AppTheme.teal,
                                fontWeight: FontWeight.w800,
                                fontSize: 9.5,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ),
                      if (pro)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [kGoldRingLight, kGoldRing]),
                              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                            ),
                            child: Text(
                              'PRO',
                              style: AppTheme.caption.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 9.5,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodyStrong.copyWith(fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.blurb,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.caption.copyWith(color: AppTheme.inkFaint, fontSize: 10.5, height: 1.25),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The picture on a tile: the reader's tree wearing the item, or a ring swatch.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.item, required this.tree});

  final CatalogItem item;
  final TreeState tree;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    if (item.kind == ItemKind.ring) {
      final gold = item.id == 'goud';
      return Container(
        color: AppTheme.paperSunken,
        alignment: Alignment.center,
        child: SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(
            value: 0.7,
            strokeWidth: 6,
            strokeCap: StrokeCap.round,
            backgroundColor: gold ? kGoldRing.withValues(alpha: 0.18) : AppTheme.rule,
            color: gold ? kGoldRing : AppTheme.teal,
          ),
        ),
      );
    }

    // A kiem looks the same in every species, so species tiles show the tree a
    // few levels on; scene and animal tiles show it as it is today.
    final draw = tree.avatar.withItem(item.kind, item.id);
    final species = item.kind == ItemKind.species;
    return TreeView(
      seed: tree.seed,
      level: species && tree.level < 6 ? 6 : tree.level,
      frac: tree.progress,
      health: tree.health,
      species: draw.species,
      scene: draw.scene,
      animal: draw.animal,
      framing: species ? TreeFraming.portrait : TreeFraming.scene,
      still: true,
    );
  }
}
