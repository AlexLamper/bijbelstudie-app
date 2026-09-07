import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../domain/traits.dart';
import '../domain/tree_state.dart';
import 'levensboom_providers.dart';
import 'tree_view.dart';

/// `/profiel/boom` — the tree, what it is made of, and what makes it grow.
///
/// The mirror of the website's `/profiel/boom`, down to the Psalm 1:3 header
/// and the XP table, which is read from the server rather than written out here
/// so the two lists cannot drift from what is actually awarded.
class LevensboomScreen extends ConsumerWidget {
  const LevensboomScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final treeAsync = ref.watch(treeStateProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Mijn boom')),
      body: treeAsync.when(
        loading: () => const _Skeleton(),
        error: (_, __) => AppEmptyState(
          icon: Icons.wifi_off_outlined,
          title: 'Je boom kon niet worden geladen',
          description: 'Controleer je verbinding en probeer het opnieuw.',
          action: SiteOutlineButton(
            label: 'Opnieuw proberen',
            expand: false,
            onPressed: () => ref.read(treeStateProvider.notifier).refresh(),
          ),
        ),
        data: (tree) => RefreshIndicator(
          onRefresh: () => ref.read(treeStateProvider.notifier).refresh(),
          child: _Body(tree: tree),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.tree});

  final TreeState tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        if (tree.disabled)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Je boom staat uit', style: AppTheme.metaLabel),
                const SizedBox(height: 6),
                Text(
                  'Je XP, niveau en badges lopen gewoon door — alleen de boom '
                  'wordt niet getoond.',
                  style: AppTheme.bodyMuted,
                ),
                const SizedBox(height: 14),
                SiteButton(
                  label: 'Boom weer tonen',
                  onPressed: () => ref
                      .read(treeStateProvider.notifier)
                      .setPrefs(disabled: false),
                ),
              ],
            ),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            child: SizedBox(
              height: 320,
              child: TreeView(
                seed: tree.seed,
                level: tree.level,
                frac: tree.progress,
                health: tree.health,
                reducedMotion: tree.reducedMotion,
              ),
            ),
          ),

        const SizedBox(height: 16),
        // Psalm 1:3 — the header of the screen, and the reason the metaphor is
        // a tree and not a score.
        Text(
          '"Want hij zal zijn als een boom, geplant aan waterbeken, die zijn '
          'vrucht geeft op zijn tijd." — Psalm 1:3',
          style: AppTheme.bodyMuted.copyWith(fontStyle: FontStyle.italic),
        ),

        const SizedBox(height: 22),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text('Niveau ${tree.level}', style: AppTheme.metaLabel),
                  ),
                  Text(
                    'nog ${tree.xpToNextLevel} XP',
                    style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SiteProgressBar(value: tree.progress),
              const SizedBox(height: 8),
              Text(
                '${tree.xp} XP totaal',
                style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
              ),
              if (tree.wilting) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.flameTint,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: Text(
                    'Je boom hangt er wat slap bij — je hebt '
                    '${tree.daysSinceActive} dagen niet gelezen. Eén sessie en '
                    'hij staat er weer fris bij.',
                    style: AppTheme.caption.copyWith(color: AppTheme.inkSoft),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 28),
        SectionHeader(
          title: 'Vruchten van de Geest',
          description: kFruitReference,
        ),
        const SizedBox(height: 12),
        _FruitGrid(level: tree.level),

        const SizedBox(height: 28),
        const SectionHeader(title: 'Hoe je boom groeit'),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            children: [
              for (final trait in kTraitOrder)
                _TraitRow(
                  label: kTraitLabels[trait]!,
                  level: kTraitLevels[trait]!,
                  unlocked: tree.level >= kTraitLevels[trait]!,
                ),
            ],
          ),
        ),

        const SizedBox(height: 28),
        const SectionHeader(title: 'Wat levert XP op?'),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in tree.xpTable)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(child: Text(row.label, style: AppTheme.bodyMuted)),
                      Text(
                        '+${row.value}',
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.teal,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'Je boom heeft de vorm die bij jouw account hoort en groeit door '
                'lezen, studeren, aantekeningen maken en dagelijks terugkomen. '
                'Blijf je een tijd weg, dan hangt hij er slap bij — hij gaat '
                'nooit dood en herstelt na één sessie.',
                style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),
        const SectionHeader(title: 'Instellingen'),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Boom tonen'),
          subtitle: const Text('Je XP, niveau en badges lopen door'),
          value: !tree.disabled,
          onChanged: (value) =>
              ref.read(treeStateProvider.notifier).setPrefs(disabled: !value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Minder beweging'),
          subtitle: const Text('Geen wiegen, deeltjes of groei-animatie'),
          value: tree.reducedMotion,
          onChanged: (value) =>
              ref.read(treeStateProvider.notifier).setPrefs(reducedMotion: value),
        ),
      ],
    );
  }
}

class _FruitGrid extends StatelessWidget {
  const _FruitGrid({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final fruit in allFruits())
          _FruitChip(fruit: fruit, unlocked: level >= fruit.level),
      ],
    );
  }
}

class _FruitChip extends StatelessWidget {
  const _FruitChip({required this.fruit, required this.unlocked});

  final SpiritFruit fruit;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: unlocked ? AppTheme.tealTint : null,
        border: Border.all(
          color: unlocked ? AppTheme.teal.withValues(alpha: 0.4) : AppTheme.rule,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fruit.name,
            style: AppTheme.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: unlocked ? AppTheme.teal : AppTheme.inkMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            unlocked ? 'Behaald' : 'Niveau ${fruit.level}',
            style: AppTheme.caption.copyWith(fontSize: 10, color: AppTheme.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _TraitRow extends StatelessWidget {
  const _TraitRow({
    required this.label,
    required this.level,
    required this.unlocked,
  });

  final String label;
  final int level;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: unlocked
                  ? AppTheme.bodyMuted.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    )
                  : AppTheme.bodyMuted,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            unlocked ? 'Behaald' : 'Niveau $level',
            style: AppTheme.caption.copyWith(
              color: unlocked ? AppTheme.teal : AppTheme.inkFaint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: const [
        Skeleton(height: 320, radius: 16),
        SizedBox(height: 18),
        SkeletonText(lines: 2, lineHeight: 11),
        SizedBox(height: 22),
        SkeletonCard(height: 110, child: SizedBox.shrink()),
        SizedBox(height: 22),
        SkeletonCard(height: 160, child: SizedBox.shrink()),
      ],
    );
  }
}
