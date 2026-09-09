import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../dashboard/present/dashboard_providers.dart';
import '../domain/profile_stats.dart';
import 'badge_medallion.dart';
import 'profile_stats_provider.dart';

/// Every badge, earned and underway, at full size.
///
/// The card on Profiel shows the first handful; this is the whole cabinet. Two
/// shelves - what hangs on the wall and what is still being earned - each a
/// grid of medallions, so the empty places are as visible as the filled ones.
/// Tapping one opens its description and progress in a sheet.
class BadgesScreen extends ConsumerWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(profileStatsProvider);
    final badges = ref.watch(profileBadgesProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Badges')),
      body: statsAsync.when(
        loading: () => const _BadgesSkeleton(),
        error: (_, __) => AppEmptyState(
          icon: Icons.wifi_off_outlined,
          title: 'Badges niet geladen',
          description: 'Controleer je verbinding en probeer het opnieuw.',
          action: SiteOutlineButton(
            label: 'Opnieuw proberen',
            expand: false,
            // The badges are measured against `/dashboard`; that is the
            // request to repeat.
            onPressed: () => ref.invalidate(dashboardProvider),
          ),
        ),
        data: (_) => _BadgesGrid(badges: badges),
      ),
    );
  }
}

/// Column sizing shared by the grid and its skeleton: three across on a phone,
/// more on a tablet, every tile the same height so the rows line up.
const SliverGridDelegate _gridDelegate =
    SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 136,
      mainAxisExtent: 180,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
    );

class _BadgesGrid extends StatelessWidget {
  const _BadgesGrid({required this.badges});

  final List<BadgeProgress> badges;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final earned = badges.where((badge) => badge.unlocked).toList();
    final pending = badges.where((badge) => !badge.unlocked).toList();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverToBoxAdapter(
            child: _Summary(earned: earned.length, total: badges.length),
          ),
        ),
        _shelf(
          title: 'Behaald',
          badges: earned,
          empty:
              'Nog geen badge behaald. Elke gelezen dag, elk geopend boek en '
              'elke notitie telt mee.',
        ),
        _shelf(
          title: 'Nog te behalen',
          badges: pending,
          empty: 'Alles behaald. Nieuwe badges volgen.',
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
      ],
    );
  }

  /// One shelf: a section header, then the grid - or, with nothing on it, a
  /// single line saying so, since an empty shelf is still worth a look.
  Widget _shelf({
    required String title,
    required List<BadgeProgress> badges,
    required String empty,
  }) {
    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
          sliver: SliverToBoxAdapter(
            child: SectionHeader(
              title: title,
              description: badges.length == 1
                  ? '1 badge'
                  : '${badges.length} badges',
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: badges.isEmpty
              ? SliverToBoxAdapter(
                  child: AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Text(empty, style: AppTheme.bodyMuted),
                  ),
                )
              : SliverGrid(
                  gridDelegate: _gridDelegate,
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _BadgeGridTile(badge: badges[index]),
                    childCount: badges.length,
                  ),
                ),
        ),
      ],
    );
  }
}

/// The tally and the nearest badge still to come, above the shelves.
class _Summary extends ConsumerWidget {
  const _Summary({required this.earned, required this.total});

  final int earned;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref
        .watch(profileBadgesProvider)
        .where((badge) => !badge.unlocked);
    // [BadgeCatalog.resolve] orders the unearned ones nearest-first.
    final next = pending.isEmpty ? null : pending.first;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$earned',
                style: AppTheme.statNumber.copyWith(fontSize: 28),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('van $total behaald', style: AppTheme.bodyMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SiteProgressBar(value: total == 0 ? 0 : earned / total, height: 6),
          const SizedBox(height: 10),
          Text(
            next == null
                ? 'Alles behaald.'
                : 'Volgende: ${next.definition.label} '
                      '(${next.value}/${next.definition.target})',
            style: AppTheme.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// One tile on a shelf: the medallion, the count that unlocks it, its name,
/// and - while it runs - the progress line.
class _BadgeGridTile extends StatelessWidget {
  const _BadgeGridTile({required this.badge});

  final BadgeProgress badge;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final earned = badge.unlocked;
    final tone = badge.definition.tone;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
      // Earned tiles carry a thin wash of their own tone so the shelf reads
      // at a glance, without tinting the whole card and making the grid busy.
      borderColor: earned ? tone.color.withValues(alpha: 0.3) : null,
      onTap: () => showBadgeDetailSheet(context, badge),
      child: Column(
        children: [
          BadgeMedallion(badge: badge, size: 60),
          const SizedBox(height: 10),
          BadgeTargetPill(badge: badge),
          const SizedBox(height: 8),
          Text(
            badge.definition.label,
            style: AppTheme.bodyStrong.copyWith(
              fontSize: 12.5,
              height: 1.3,
              color: earned ? AppTheme.ink : AppTheme.inkMuted,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          if (earned)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 12, color: AppTheme.positive),
                const SizedBox(width: 4),
                Text(
                  'Behaald',
                  style: AppTheme.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.positive,
                  ),
                ),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: SiteProgressBar(
                value: badge.fraction,
                height: 4,
                color: tone.color,
              ),
            ),
        ],
      ),
    );
  }
}

class _BadgesSkeleton extends StatelessWidget {
  const _BadgesSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        const SkeletonCard(
          height: 104,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton(height: 24, width: 140),
              SizedBox(height: 14),
              Skeleton(height: 6, radius: 999),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Skeleton(height: 16, width: 120),
        const SizedBox(height: 12),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: _gridDelegate,
          children: [
            for (var i = 0; i < 6; i++)
              const SkeletonCard(
                padding: EdgeInsets.fromLTRB(8, 14, 8, 12),
                child: Column(
                  children: [
                    Skeleton.circle(60),
                    SizedBox(height: 10),
                    Skeleton(height: 22, width: 36, radius: 999),
                    SizedBox(height: 12),
                    Skeleton(height: 12, width: 64),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
