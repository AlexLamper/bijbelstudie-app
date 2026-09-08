import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/catalog.dart';
import '../../domain/stages.dart';
import '../../domain/traits.dart';
import '../../domain/tree_state.dart';

/// The Groei tab: where the tree is on its way, and what each stage brings.
///
/// A timeline rather than a stack of cards - the stages are the story, the
/// fruit and traits hang off the stage they arrive in, and the level-gated
/// catalog items sit at their level so "nog 340 XP" has a face. The mirror of
/// the website's `GroeiTab.tsx`.
class GroeiTab extends StatelessWidget {
  const GroeiTab({super.key, required this.tree});

  final TreeState tree;

  @override
  Widget build(BuildContext context) {
    final level = tree.level;
    final fruits = allFruits();
    final gated = kCatalog.where((item) => item.unlock is LevelUnlock).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < kStages.length; i++) ...[
          _StageRow(
            stage: kStages[i],
            next: i + 1 < kStages.length ? kStages[i + 1] : null,
            last: i == kStages.length - 1,
            level: level,
            fruits: fruits,
            gated: gated,
          ),
        ],
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: AppTheme.rule),
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            shape: const Border(),
            title: Text('Wat levert XP op?', style: AppTheme.bodyStrong),
            children: [
              for (final row in tree.xpTable)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(row.label, style: AppTheme.bodyMuted)),
                      Text(
                        '+${row.value}',
                        style: AppTheme.caption.copyWith(color: AppTheme.teal, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                '${tree.xp} XP totaal. Blijf je een tijd weg, dan hangt je boom er slap bij — '
                'hij gaat nooit dood en herstelt na één sessie.',
                style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '"Want hij zal zijn als een boom, geplant aan waterbeken, die zijn vrucht '
          'geeft op zijn tijd." — Psalm 1:3',
          style: AppTheme.caption.copyWith(color: AppTheme.inkFaint, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stage,
    required this.next,
    required this.last,
    required this.level,
    required this.fruits,
    required this.gated,
  });

  final StageDef stage;
  final StageDef? next;
  final bool last;
  final int level;
  final List<SpiritFruit> fruits;
  final List<CatalogItem> gated;

  bool _inBand(int at) => at >= stage.from && (next == null || at < next!.from);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final to = next == null ? null : next!.from - 1;
    final reached = level >= stage.from;
    final current = reached && (to == null || level <= to);
    final bandTraits = kTraitOrder.where((t) => t != TreeTrait.fruit && _inBand(kTraitLevels[t]!)).toList();
    final bandFruits = fruits.where((f) => _inBand(f.level)).toList();
    final bandItems = gated.where((item) => _inBand((item.unlock as LevelUnlock).level)).toList();
    final range = to == null
        ? 'niveau ${stage.from}+'
        : stage.from == to
        ? 'niveau ${stage.from}'
        : 'niveau ${stage.from}–$to';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: current ? AppTheme.teal : scheme.surface,
                    border: Border.all(color: reached ? AppTheme.teal : AppTheme.ruleStrong, width: 2),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 1.5, color: AppTheme.rule, margin: const EdgeInsets.symmetric(vertical: 4)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              stage.name,
                              style: AppTheme.bodyStrong.copyWith(
                                color: reached ? scheme.onSurface : AppTheme.inkMuted,
                              ),
                            ),
                            if (current) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.teal,
                                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                                ),
                                child: Text(
                                  'NU',
                                  style: AppTheme.caption.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 9.5,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(range, style: AppTheme.caption.copyWith(color: AppTheme.inkFaint)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(stage.blurb, style: AppTheme.caption.copyWith(color: AppTheme.inkFaint)),
                  if (bandTraits.isNotEmpty || bandFruits.isNotEmpty || bandItems.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final trait in bandTraits)
                      _Line(at: kTraitLevels[trait]!, level: level, label: kTraitLabels[trait]!),
                    for (final fruit in bandFruits)
                      _Line(at: fruit.level, level: level, label: 'Vrucht: ${fruit.name.toLowerCase()}'),
                    for (final item in bandItems)
                      _Line(
                        at: (item.unlock as LevelUnlock).level,
                        level: level,
                        label: '${item.name} (${unlockLabel(item.unlock).toLowerCase()})',
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.at, required this.level, required this.label});

  final int at;
  final int level;
  final String label;

  @override
  Widget build(BuildContext context) {
    final done = level >= at;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.caption.copyWith(
                color: done ? Theme.of(context).colorScheme.onSurface : AppTheme.inkMuted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            done ? 'Behaald' : 'Niveau $at',
            style: AppTheme.caption.copyWith(
              color: done ? AppTheme.teal : AppTheme.inkFaint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
