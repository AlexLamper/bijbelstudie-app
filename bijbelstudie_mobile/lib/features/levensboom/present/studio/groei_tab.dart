import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../domain/growth.dart';
import '../../domain/growth_copy.dart';
import '../../domain/stages.dart';
import '../../domain/tree_state.dart';
import '../tree_analytics.dart';
import 'groei_thumbnails.dart';

/// The Groei tab: the step ladder (LEVENSBOOM_GROWTH_PLAN.md §9.4). The mirror
/// of the website's `GroeiTab.tsx`.
///
/// A header with where the tree is ("Jonge boom · stap 9 van 20") and a bar to
/// the next step, then five phase sections with one row per step: this
/// reader's own tree at that step, the level at which this account stands on
/// it, what arrives there, and whether it is behind, current or ahead. The
/// next step is a silhouette, the ones after it a "?", so there is still
/// something to come back for.
///
/// A sliver, not a box: the rows are built lazily as they scroll in, and each
/// thumbnail is a cached image (`groei_thumbnails.dart`), because twenty trees
/// in a list is the heaviest thing on this screen on a low-end Android.
///
/// Thumbnails draw the tree at each step (`TreeAt`, with the account's floor),
/// the current row at the reader's own position, and the level at which the
/// account stands on that step for traits and fruit - as the website's ladder.
class GroeiTab extends ConsumerStatefulWidget {
  const GroeiTab({super.key, required this.tree});

  final TreeState tree;

  @override
  ConsumerState<GroeiTab> createState() => _GroeiTabState();
}

class _GroeiTabState extends ConsumerState<GroeiTab> {
  @override
  void initState() {
    super.initState();
    // Once per opening of the tab (§13).
    trackTree(ref, AnalyticsEvents.treeGroeiOpened, {
      'step': '${widget.tree.step}',
      'level': '${widget.tree.level}',
    });
  }

  @override
  Widget build(BuildContext context) {
    final tree = widget.tree;
    final floor = tree.floor;
    final step = tree.step;
    final items = <WidgetBuilder>[
      (_) => _Header(tree: tree),
      (_) => _XpDetails(tree: tree),
      for (var p = 0; p < kStages.length; p++) ...[
        (_) => _PhaseHeader(
          stage: kStages[p],
          first: p == 0,
          current: tree.phase.index == p,
          reached: step >= kStages[p].from,
        ),
        if (kStages[p].to != null)
          for (var n = kStages[p].from; n <= kStages[p].to!; n++)
            (_) => _StepRow(tree: tree, n: n, floor: floor),
        if (kStages[p].to == null) (_) => _MaturingSection(tree: tree),
      ],
    ];

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => items[index](context),
        childCount: items.length,
      ),
    );
  }
}

/// "Jonge boom · stap 9 van 20", the bar to the next step, and - for an
/// account with a head start - the one line that explains why the step runs
/// ahead of the level.
class _Header extends StatelessWidget {
  const _Header({required this.tree});

  final TreeState tree;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          growthPill(tree.phase.name, tree.step),
          style: AppTheme.displaySmall.copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
        const SizedBox(height: 10),
        SiteProgressBar(value: tree.stepProgress),
        const SizedBox(height: 6),
        Text(
          xpToNextStepLabel(tree.step, tree.xpToNextStep),
          style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
        ),
        if (showsFlooredExplainer(tree.floor, tree.step)) ...[
          const SizedBox(height: 10),
          Text(flooredExplainer, style: AppTheme.caption.copyWith(color: AppTheme.inkMuted)),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

/// A phase's name, its steps and its blurb, above its rows.
class _PhaseHeader extends StatelessWidget {
  const _PhaseHeader({
    required this.stage,
    required this.first,
    required this.current,
    required this.reached,
  });

  final StageDef stage;
  final bool first;
  final bool current;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: first ? 26 : 18, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        stage.name,
                        style: AppTheme.bodyStrong.copyWith(
                          color: reached ? scheme.onSurface : AppTheme.inkMuted,
                        ),
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
              Text(
                phaseRange(stage.from, stage.to),
                style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(stage.blurb, style: AppTheme.caption.copyWith(color: AppTheme.inkFaint)),
        ],
      ),
    );
  }
}

/// One step: the thumbnail, "Stap n", the level, what arrives, the status.
class _StepRow extends StatelessWidget {
  const _StepRow({required this.tree, required this.n, required this.floor});

  final TreeState tree;
  final int n;
  final GrowthFloor? floor;

  static const double _thumb = 44;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final step = tree.step;
    final reached = n < step;
    final current = n == step;
    final ahead = n > step;
    final level = levelForStep(n, floor);

    // What arrives on this row: every level from the one that puts the tree
    // on step n up to the one before step n + 1, so a head start that folds
    // several levels into one step (or several steps into one level) still
    // lists everything exactly once.
    final untilLevel = levelForStep(n + 1, floor);
    final arrivals = [
      for (var l = level; l < untilLevel; l++) ...arrivalsAtLevel(l),
    ];

    final Widget thumb;
    if (n <= step) {
      thumb = GroeiThumbnail(
        seed: tree.seed,
        level: level,
        step: n,
        // The current row shows the tree where it stands now, like the website.
        position: current ? tree.position : null,
        floor: floor,
        species: tree.avatar.species,
        scene: tree.avatar.scene,
        size: _thumb,
      );
    } else if (n == step + 1) {
      thumb = GroeiThumbnail(
        seed: tree.seed,
        level: level,
        step: n,
        floor: floor,
        species: tree.avatar.species,
        scene: tree.avatar.scene,
        size: _thumb,
        silhouette: true,
      );
    } else {
      thumb = const GroeiThumbnailUnknown(size: _thumb);
    }

    final status = reached
        ? ladderReached
        : current
        ? ladderCurrent(tree.stepProgress)
        : ladderAhead(level);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: current
          ? BoxDecoration(
              color: AppTheme.tealTint,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            )
          : null,
      child: Row(
        children: [
          thumb,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      ladderStep(n),
                      style: AppTheme.bodyStrong.copyWith(
                        color: ahead ? AppTheme.inkMuted : scheme.onSurface,
                      ),
                    ),
                    // Ahead, the status already names the level.
                    if (!ahead) ...[
                      const SizedBox(width: 8),
                      Text(
                        ladderLevel(level),
                        style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
                      ),
                    ],
                  ],
                ),
                if (arrivals.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    arrivals.join(' · '),
                    style: AppTheme.caption.copyWith(
                      color: ahead ? AppTheme.inkFaint : AppTheme.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            status,
            style: AppTheme.caption.copyWith(
              color: ahead ? AppTheme.inkFaint : AppTheme.teal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Past step 20: the jaarringen, and what maturing still brings.
class _MaturingSection extends StatelessWidget {
  const _MaturingSection({required this.tree});

  final TreeState tree;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final floor = tree.floor;
    final from = levelForStep(stepsTotal + 1, floor);
    final next = maturingNextLine(tree.step, floor);

    // Fruit, traits and catalog items that still arrive past step 20. The
    // arrival table ends well before level 40.
    final lines = <({String label, int level})>[
      for (var l = from; l <= 40; l++)
        for (final label in arrivalsAtLevel(l)) (label: label, level: l),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tree.rings > 0)
          Text(
            ringsLabel(tree.rings),
            style: AppTheme.bodyStrong.copyWith(color: scheme.onSurface),
          ),
        if (next != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(next, style: AppTheme.caption.copyWith(color: AppTheme.inkMuted)),
          ),
        for (final line in lines)
          _Line(label: line.label, at: line.level, level: tree.level),
      ],
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
    AppTheme.dependOn(context);
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
            done ? ladderReached : ladderAhead(at),
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

/// Under the header: "Wat levert XP op?", the health line, and Psalm 1:3.
class _XpDetails extends StatelessWidget {
  const _XpDetails({required this.tree});

  final TreeState tree;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  '${tree.xp} XP totaal. Blijf je een tijd weg, dan hangt je boom er slap bij - '
                  'hij gaat nooit dood en herstelt na één sessie.',
                  style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '"Want hij zal zijn als een boom, geplant aan waterbeken, die zijn vrucht '
            'geeft op zijn tijd." - Psalm 1:3',
            style: AppTheme.caption.copyWith(color: AppTheme.inkFaint, fontStyle: FontStyle.italic),
          ),
        ],
    );
  }
}
