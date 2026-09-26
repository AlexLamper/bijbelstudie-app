import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../dashboard/data/resume_link.dart';
import '../data/bible_year_models.dart';
import '../domain/bible_year_display.dart';
import 'bible_year_providers.dart';

/// The "Bijbel in een jaar" block at the top of the Studies tab, as on the
/// website's /studies. Not started (or signed out): two option cards, 1 jaar
/// and 2 jaar, into the plan screen with that duration preselected. Started: a
/// compact "Vandaag" row into the same screen.
class BibleYearStudiesBlock extends ConsumerStatefulWidget {
  const BibleYearStudiesBlock({super.key});

  @override
  ConsumerState<BibleYearStudiesBlock> createState() => _BibleYearStudiesBlockState();
}

class _BibleYearStudiesBlockState extends ConsumerState<BibleYearStudiesBlock>
    with BibleYearRefreshOnMount {
  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final async = ref.watch(bibleYearProvider);
    final data = async.value;

    if (data == null && async.isLoading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Skeleton(height: 76, radius: AppTheme.radiusLg),
      );
    }

    final today = data?.today;
    if (data != null && data.isActive && today != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: BibleYearTodayRow(
          today: today,
          onTap: () => context.push(bibleYearPath),
        ),
      );
    }

    final plans = data?.catalogue.isNotEmpty == true ? data!.catalogue : kDefaultBibleYearCatalogue;
    final completed = data?.enrollment?.isCompleted == true;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 10,
            children: [
              Text('Bijbel in een jaar', style: AppTheme.bodyStrong.copyWith(fontSize: 13.5)),
              Text(
                completed ? 'Je hebt de hele Bijbel gelezen' : 'De hele Bijbel, elke dag een stuk',
                style: AppTheme.caption.copyWith(fontSize: 12.5, color: AppTheme.inkFaint),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < plans.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _PlanOption(plan: plans[i])),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanOption extends StatelessWidget {
  const _PlanOption({required this.plan});

  final BibleYearCatalogueEntry plan;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onTap: () => context.push('$bibleYearPath?plan=${plan.planKey.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('De Bijbel in ${plan.label}', style: AppTheme.displayBase),
          const SizedBox(height: 2),
          Text(
            '${plan.totalDays} dagen · ongeveer ${plan.minutesPerDay} min per dag',
            style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Start', style: AppTheme.pillLabel.copyWith(fontSize: 13, color: AppTheme.tealStrong)),
              Icon(Icons.chevron_right, size: 16, color: AppTheme.tealStrong),
            ],
          ),
        ],
      ),
    );
  }
}

/// The compact "Vandaag" row: a ring with the share of the Bible, the day,
/// and today's portions (or the gentle behind line, or "Vandaag gelezen").
class BibleYearTodayRow extends StatelessWidget {
  const BibleYearTodayRow({super.key, required this.today, required this.onTap});

  final BibleYearToday today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final behind = behindLabel(today.behindDays);
    final subtitle = today.todayDone
        ? null
        : behind ?? today.portions.map((p) => p.label).join(' · ');
    final pct = today.percentBible.isFinite ? today.percentBible.clamp(0.0, 100.0) : 0.0;
    final day = today.dayNumber > 0
        ? dayOfPlanLabel(today.dayNumber, today.totalDays)
        : 'begint binnenkort';

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onTap: onTap,
      child: Row(
        children: [
          SizedBox.square(
            dimension: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.square(
                  dimension: 44,
                  child: CircularProgressIndicator(
                    value: pct / 100,
                    strokeWidth: 4,
                    backgroundColor: AppTheme.rule,
                    valueColor: AlwaysStoppedAnimation(AppTheme.teal),
                  ),
                ),
                Text(
                  formatPercent(pct),
                  style: AppTheme.overline.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    color: AppTheme.tealStrong,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bijbel in een jaar · $day',
                  style: AppTheme.displayBase,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (today.todayDone)
                  Row(
                    children: [
                      Icon(Icons.check, size: 13, color: AppTheme.teal),
                      const SizedBox(width: 4),
                      Text('Vandaag gelezen', style: AppTheme.caption.copyWith(color: AppTheme.inkFaint)),
                    ],
                  )
                else
                  Text(
                    subtitle ?? '',
                    style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            today.todayDone ? 'Bekijk' : 'Lezen',
            style: AppTheme.pillLabel.copyWith(fontSize: 13, color: AppTheme.tealStrong),
          ),
          Icon(Icons.chevron_right, size: 16, color: AppTheme.tealStrong),
        ],
      ),
    );
  }
}
