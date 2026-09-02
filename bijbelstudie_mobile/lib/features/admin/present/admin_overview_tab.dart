import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../domain/admin_entities.dart';
import 'admin_common.dart';
import 'admin_providers.dart';
import 'admin_user_sheet.dart';

/// The overview tab — everything `/admin` renders in the browser, stacked for
/// a phone: the headline figures, the two growth charts, content counts,
/// billing health, revenue, the newest signups and the short funnel.
class AdminOverviewTab extends ConsumerWidget {
  const AdminOverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatsProvider);

    return RefreshIndicator(
      color: AppTheme.teal,
      onRefresh: () async {
        ref.invalidate(adminStatsProvider);
        ref.invalidate(adminInsightsProvider(30));
        ref.invalidate(adminUsersProvider);
        await ref.read(adminStatsProvider.future);
      },
      child: stats.when(
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: const [
            SkeletonCard(height: 96, child: SkeletonText(lines: 2)),
            SizedBox(height: 12),
            SkeletonCard(height: 96, child: SkeletonText(lines: 2)),
            SizedBox(height: 12),
            SkeletonCard(height: 180, child: SkeletonText(lines: 4)),
            SizedBox(height: 12),
            SkeletonCard(height: 180, child: SkeletonText(lines: 4)),
          ],
        ),
        error: (error, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          children: [
            AdminErrorState(
              error: error,
              onRetry: () => ref.invalidate(adminStatsProvider),
            ),
          ],
        ),
        data: (data) => _Overview(stats: data),
      ),
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview({required this.stats});

  final AdminStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = stats.users;
    final billing = stats.billing;
    final revenue = stats.revenue;
    final content = stats.content;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        if (stats.degraded.isNotEmpty) ...[
          _DegradedBanner(labels: stats.degraded),
          const SizedBox(height: 16),
        ],

        // Headline figures.
        Row(
          children: [
            Expanded(
              child: AdminMetricTile(
                label: 'Totaal gebruikers',
                value: adminNumber(users.total),
                delta: users.newLast7d == null
                    ? null
                    : '+${adminNumber(users.newLast7d)} deze week',
                icon: Icons.people_outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AdminMetricTile(
                label: 'Betalende abonnees',
                value: adminNumber(users.paying),
                delta: '${adminPercent(users.premiumPercent)} conversie',
                icon: Icons.verified_outlined,
                tint: AppTheme.flame,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: AdminMetricTile(
                label: 'MRR (geschat)',
                value: adminEuro(revenue.mrrEur),
                delta: '${adminEuro(revenue.arrEur)} ARR',
                icon: Icons.euro_outlined,
                tint: AppTheme.positive,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AdminMetricTile(
                label: 'Actieve streaks',
                value: adminNumber(users.activeStreak),
                delta: '${adminNumber(users.admins)} beheerders',
                icon: Icons.local_fire_department_outlined,
                tint: AppTheme.ai,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),
        const SectionHeader(
          title: 'Groei',
          description: 'Per dag, laatste 30 dagen',
          icon: Icons.trending_up,
        ),
        const SizedBox(height: 12),
        const _OverviewCharts(),

        const SizedBox(height: 20),
        const SectionHeader(
          title: 'Content & engagement',
          icon: Icons.menu_book_outlined,
        ),
        const SizedBox(height: 12),
        AppCard(
          radius: AppTheme.radiusMd,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            children: [
              AdminStatRow(
                label: 'Notities',
                value: adminNumber(content.notes),
              ),
              AdminStatRow(
                label: 'Notities deze week',
                value: adminNumber(content.notesLast7d),
              ),
              AdminStatRow(
                label: 'Leessessies',
                value: adminNumber(content.readingSessions),
              ),
              AdminStatRow(
                label: 'Sessies deze week',
                value: adminNumber(content.sessionsLast7d),
              ),
              AdminStatRow(
                label: 'Studiegroepen',
                value: adminNumber(content.groups),
              ),
              AdminStatRow(
                label: 'Leesplannen',
                value: adminNumber(content.plans),
                showRule: false,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        const SectionHeader(
          title: 'Abonnementen',
          description: 'Wie betaalt er, en waar hapert het',
          icon: Icons.credit_card_outlined,
        ),
        const SizedBox(height: 12),
        AppCard(
          radius: AppTheme.radiusMd,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            children: [
              AdminStatRow(
                label: 'Stripe-abonnees',
                value: adminNumber(users.stripeSubscribers),
              ),
              AdminStatRow(
                label: 'Store-abonnees',
                value: adminNumber(users.storeSubscribers),
              ),
              AdminStatRow(
                label: 'Maandabonnementen',
                value: adminNumber(billing.monthlySubscribers),
              ),
              AdminStatRow(
                label: 'Jaarabonnementen',
                value: adminNumber(billing.annualSubscribers),
              ),
              AdminStatRow(
                label: 'Interval onbekend',
                value: adminNumber(billing.unknownInterval),
                emphasis: (billing.unknownInterval ?? 0) > 0,
              ),
              AdminStatRow(
                label: 'Gratis Pro-toegang',
                value: adminNumber(users.comped),
              ),
              AdminStatRow(
                label: 'Betaalproblemen',
                value: adminNumber(billing.withBillingIssue),
                emphasis: (billing.withBillingIssue ?? 0) > 0,
              ),
              AdminStatRow(
                label: 'Zegt op na deze periode',
                value: adminNumber(billing.cancelAtPeriodEnd),
              ),
              AdminStatRow(
                label: 'Gepauzeerd',
                value: adminNumber(billing.paused),
              ),
              AdminStatRow(
                label: 'Betaald zonder Pro',
                value: adminNumber(billing.possiblyMissedWebhooks),
                emphasis: (billing.possiblyMissedWebhooks ?? 0) > 0,
                showRule: false,
              ),
            ],
          ),
        ),
        if (billing.byStatus != null && billing.byStatus!.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppCard(
            radius: AppTheme.radiusMd,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stripe-status', style: AppTheme.bodyStrong),
                const SizedBox(height: 6),
                for (final entry in billing.byStatus!.entries.toList())
                  AdminStatRow(
                    label: _statusLabels[entry.key] ?? entry.key,
                    value: adminNumber(entry.value),
                    emphasis:
                        entry.value > 0 &&
                        const {'past_due', 'unpaid', 'incomplete'}
                            .contains(entry.key),
                    showRule: entry.key != billing.byStatus!.keys.last,
                  ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),
        const SectionHeader(
          title: 'Omzet',
          description: 'Afgeleid van de actieve abonnementen',
          icon: Icons.payments_outlined,
        ),
        const SizedBox(height: 12),
        AppCard(
          radius: AppTheme.radiusMd,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            children: [
              AdminStatRow(label: 'MRR', value: adminEuro(revenue.mrrEur)),
              AdminStatRow(label: 'ARR', value: adminEuro(revenue.arrEur)),
              AdminStatRow(
                label: 'Maandprijs',
                value: adminEuro(revenue.priceEur),
              ),
              AdminStatRow(
                label: 'Jaarprijs',
                value: adminEuro(revenue.annualPriceEur),
                showRule: false,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        const _RecentSignups(),

        const SizedBox(height: 20),
        const SectionHeader(title: 'Vandaag', icon: Icons.today_outlined),
        const SizedBox(height: 12),
        AppCard(
          radius: AppTheme.radiusMd,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            children: [
              AdminStatRow(
                label: 'Nieuwe aanmeldingen (24 uur)',
                value: adminNumber(users.newLast24h),
              ),
              AdminStatRow(
                label: 'Nieuw in 7 dagen',
                value: adminNumber(users.newLast7d),
              ),
              AdminStatRow(
                label: 'Nieuw in 30 dagen',
                value: adminNumber(users.newLast30d),
              ),
              AdminStatRow(
                label: 'Notities deze week',
                value: adminNumber(content.notesLast7d),
              ),
              AdminStatRow(
                label: 'Sessies deze week',
                value: adminNumber(content.sessionsLast7d),
                showRule: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Dutch names for the Stripe subscription statuses.
const _statusLabels = <String, String>{
  'active': 'Actief',
  'trialing': 'Proefperiode',
  'past_due': 'Betaling te laat',
  'unpaid': 'Onbetaald',
  'canceled': 'Opgezegd',
  'paused': 'Gepauzeerd',
  'incomplete': 'Niet afgerond',
  'incomplete_expired': 'Niet afgerond (verlopen)',
};

/// The two charts the website's overview shows, off the 30-day insights call.
class _OverviewCharts extends ConsumerWidget {
  const _OverviewCharts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(adminInsightsProvider(30));

    return insights.when(
      loading: () => const Column(
        children: [
          SkeletonCard(height: 150, child: SkeletonText(lines: 3)),
          SizedBox(height: 12),
          SkeletonCard(height: 150, child: SkeletonText(lines: 3)),
        ],
      ),
      error: (error, _) => AppCard(
        radius: AppTheme.radiusMd,
        child: Text(
          error is Exception
              ? 'Grafieken konden niet worden geladen.'
              : 'Grafieken konden niet worden geladen.',
          style: AppTheme.bodyMuted,
        ),
      ),
      data: (data) => Column(
        children: [
          AdminSeriesChart(
            title: 'Nieuwe gebruikers',
            series: data.signups,
            icon: Icons.person_add_alt,
          ),
          const SizedBox(height: 12),
          AdminSeriesChart(
            title: 'Leessessies',
            series: data.readingSessions,
            tint: AppTheme.ai,
            icon: Icons.auto_stories_outlined,
          ),
        ],
      ),
    );
  }
}

/// The five newest accounts, tappable straight through to the same detail
/// sheet the users tab opens.
class _RecentSignups extends ConsumerWidget {
  const _RecentSignups();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(adminUsersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Recente aanmeldingen',
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 12),
        users.when(
          loading: () => const SkeletonCard(child: SkeletonText(lines: 4)),
          error: (error, _) => AppCard(
            radius: AppTheme.radiusMd,
            child: Text(
              'Gebruikers konden niet worden geladen.',
              style: AppTheme.bodyMuted,
            ),
          ),
          data: (list) {
            if (list.isEmpty) {
              return AppCard(
                radius: AppTheme.radiusMd,
                child: Text('Nog geen gebruikers.', style: AppTheme.bodyMuted),
              );
            }
            final recent = list.take(5).toList();
            return AppCard(
              radius: AppTheme.radiusMd,
              padding: EdgeInsets.zero,
              clip: true,
              child: Column(
                children: [
                  for (final account in recent)
                    AdminAccountRow(
                      account: account,
                      trailing: adminRelative(account.createdAt),
                      showRule: account != recent.last,
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// The "one or more figures are unknown" banner. The website shows the same
/// list; a dash on a card means the number below is in here.
class _DegradedBanner extends StatelessWidget {
  const _DegradedBanner({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: AppTheme.radiusMd,
      color: AppTheme.flameTint,
      borderColor: AppTheme.flame.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_outlined, size: 16, color: AppTheme.flame),
              const SizedBox(width: 8),
              Text('Niet alles kon worden gelezen', style: AppTheme.bodyStrong),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Deze cijfers staan op een streepje: ${labels.join(', ')}.',
            style: AppTheme.bodyMuted,
          ),
        ],
      ),
    );
  }
}
