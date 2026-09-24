import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/catalog.dart';
import '../../domain/tree_state.dart';
import '../levensboom_avatar.dart';
import '../tree_view.dart';

/// Space between tiles, both ways.
const double _gap = 10;

/// Caption padding under the picture.
const EdgeInsets _captionPadding = EdgeInsets.fromLTRB(10, 8, 10, 10);

/// The picture's height as a share of the tile's width: a portrait for
/// species and rings, a landscape for scenes and animals.
const double _squarePicture = 0.74;
const double _widePicture = 0.6;

TextStyle get _nameStyle => AppTheme.bodyStrong.copyWith(fontSize: 13);

TextStyle get _blurbStyle =>
    AppTheme.caption.copyWith(color: AppTheme.inkFaint, fontSize: 10.5, height: 1.25);

/// Columns and row height for a tile grid [width] wide.
///
/// The row is the picture plus the caption measured at the reader's text size,
/// so a larger text setting makes the tiles taller instead of pushing the
/// caption out of them. A three-across grid drops to two when a tile would be
/// too narrow to hold a name at that text size (a 320 dp phone, or text at
/// 130 %).
({int columns, double extent}) studioGridLayout({
  required double width,
  required bool square,
  required TextScaler textScaler,
}) {
  final scale = textScaler.scale(14) / 14;
  var columns = square ? 3 : 2;
  double tileWidth(int n) => (width - _gap * (n - 1)) / n;
  final minWidth = (square ? 96.0 : 100.0) * scale;
  while (columns > 1 && tileWidth(columns) < minWidth) {
    columns -= 1;
  }

  double measure(String text, TextStyle style, int lines) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: lines,
      textScaler: textScaler,
      textDirection: TextDirection.ltr,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  final caption = _captionPadding.vertical +
      measure('Ag', _nameStyle, 1) +
      2 +
      measure('Ag\nAg', _blurbStyle, 2);
  final picture = tileWidth(columns) * (square ? _squarePicture : _widePicture);
  // Whole pixels, rounded up: a fraction short is still an overflow.
  return (columns: columns, extent: (picture + caption).ceilToDouble() + 1);
}

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
    final textScaler = MediaQuery.textScalerOf(context);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final layout = studioGridLayout(
          width: constraints.crossAxisExtent,
          square: square,
          textScaler: textScaler,
        );
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: layout.columns,
            mainAxisSpacing: _gap,
            crossAxisSpacing: _gap,
            mainAxisExtent: layout.extent,
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
      },
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
    final stroke = selected ? 2.0 : 1.0;
    final radius = BorderRadius.circular(AppTheme.radiusLg);

    // The border is the Material's own outline, painted over the content, and
    // the content sits inside it - inset by the stroke and clipped to the
    // inner radius. The picture used to be clipped to the *outer* edge and
    // painted over a border drawn underneath it, which erased the outline
    // along the top and round both top corners of every tile.
    return Semantics(
      button: true,
      selected: selected,
      label: locked ? '${item.name}, vergrendeld: ${unlockLabel(item.unlock)}' : item.name,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: outline, width: stroke),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(stroke),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg - stroke),
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
                        if (locked) _LockPill(unlock: item.unlock),
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
                            child: _Badge(
                              text: 'NIEUW',
                              color: AppTheme.teal,
                              background: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                              ),
                            ),
                          ),
                        // A locked Pro item says "Pro" on its (gold) lock pill;
                        // the corner badge is for the ones the reader has.
                        if (pro && !locked)
                          const Positioned(
                            right: 6,
                            bottom: 6,
                            child: _Badge(
                              text: 'PRO',
                              color: Colors.white,
                              background: BoxDecoration(
                                gradient: LinearGradient(colors: [kGoldRingLight, kGoldRing]),
                                borderRadius: BorderRadius.all(Radius.circular(AppTheme.radiusPill)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: _captionPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _nameStyle,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.blurb,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _blurbStyle,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a locked tile takes, centred on its picture. It wraps onto a second
/// line rather than running past the tile ("Reeks van 30 dagen" on a narrow
/// tile), and a Pro rule wears the gold.
class _LockPill extends StatelessWidget {
  const _LockPill({required this.unlock});

  final Unlock unlock;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final pro = unlock is ProUnlock;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: pro ? null : Colors.black.withValues(alpha: 0.55),
            gradient: pro ? const LinearGradient(colors: [kGoldRingLight, kGoldRing]) : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 11, color: Colors.white),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  unlockLabel(unlock),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTheme.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, required this.background});

  final String text;
  final Color color;
  final BoxDecoration background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: background,
      child: Text(
        text,
        maxLines: 1,
        style: AppTheme.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 9.5,
          letterSpacing: 0.6,
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
      return ColoredBox(
        color: AppTheme.paperSunken,
        // Sized to the box it gets: a fixed 56 px ring was squashed into an
        // oval and cut off once large text left the picture less room.
        child: LayoutBuilder(
          builder: (context, box) {
            final diameter = math.max(0.0, math.min(56.0, box.biggest.shortestSide - 16));
            return Center(
              child: SizedBox.square(
                dimension: diameter,
                child: CircularProgressIndicator(
                  value: 0.7,
                  strokeWidth: math.max(2.0, diameter * 6 / 56),
                  strokeCap: StrokeCap.round,
                  backgroundColor: gold ? kGoldRing.withValues(alpha: 0.18) : AppTheme.rule,
                  color: gold ? kGoldRing : AppTheme.teal,
                ),
              ),
            );
          },
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
      // The reader's floor, so a floored account's tiles show the tree at the
      // size it has everywhere else.
      floor: tree.floor,
      health: tree.health,
      species: draw.species,
      scene: draw.scene,
      animal: draw.animal,
      framing: species ? TreeFraming.portrait : TreeFraming.scene,
      still: true,
    );
  }
}
