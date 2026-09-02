import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../domain/admin_entities.dart';
import 'admin_common.dart';
import 'admin_providers.dart';

/// The insights tab — the website's `/admin/insights` page stacked for a
/// phone: a range picker, the traffic split, every day-series as a bar chart,
/// the most-viewed pages and clicked targets, and the study funnel.
class AdminInsightsTab extends ConsumerStatefulWidget {
  const AdminInsightsTab({super.key});

  @override
  ConsumerState<AdminInsightsTab> createState() => _AdminInsightsTabState();
}

class _AdminInsightsTabState extends ConsumerState<AdminInsightsTab> {
  /// The server clamps to 7...365; these are the three the website offers.
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final insights = ref.watch(adminInsightsProvider(_days));

    return RefreshIndicator(
      color: AppTheme.teal,
      onRefresh: () async {
        ref.invalidate(adminInsightsProvider(_days));
        await ref.read(adminInsightsProvider(_days).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _RangePicker(
            days: _days,
            onChanged: (value) => setState(() => _days = value),
          ),
          const SizedBox(height: 16),
          ...insights.when(
            loading: () => const [
              SkeletonCard(height: 120, child: SkeletonText(lines: 3)),
              SizedBox(height: 12),
              SkeletonCard(height: 180, child: SkeletonText(lines: 4)),
              SizedBox(height: 12),
              SkeletonCard(height: 180, child: SkeletonText(lines: 4)),
            ],
            error: (error, _) => [
              AdminErrorState(
                error: error,
                onRetry: () => ref.invalidate(adminInsightsProvider(_days)),
              ),
            ],
            data: (data) => _sections(data),
          ),
        ],
      ),
    );
  }

  List<Widget> _sections(AdminInsights data) {
    return [
      const SectionHeader(eyebrow: 'Bereik', title: 'Verkeer'),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: AdminMetricTile(
              label: 'Unieke bezoekers',
              value: adminNumber(data.traffic.uniqueVisitors),
              icon: Icons.groups_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AdminMetricTile(
              label: 'Paginaweergaven',
              value: adminNumber(data.traffic.totalViews),
              icon: Icons.visibility_outlined,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: AdminMetricTile(
              label: 'Ingelogd',
              value: adminNumber(data.traffic.loggedInViews),
              icon: Icons.person_outline,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AdminMetricTile(
              label: 'Uitgelogd',
              value: adminNumber(data.traffic.loggedOutViews),
              icon: Icons.person_off_outlined,
              tint: AppTheme.inkMuted,
            ),
          ),
        ],
      ),

      const SizedBox(height: 22),
      const SectionHeader(eyebrow: 'Verloop', title: 'Per dag'),
      const SizedBox(height: 10),
      AdminSeriesChart(
        title: 'Aanmeldingen',
        series: data.signups,
        icon: Icons.person_add_alt,
      ),
      const SizedBox(height: 12),
      AdminSeriesChart(
        title: 'Paginaweergaven',
        series: data.pageViews,
        icon: Icons.visibility_outlined,
      ),
      const SizedBox(height: 12),
      AdminSeriesChart(
        title: 'Leessessies',
        series: data.readingSessions,
        icon: Icons.menu_book_outlined,
      ),
      const SizedBox(height: 12),
      AdminSeriesChart(
        title: 'Notities',
        series: data.notes,
        icon: Icons.edit_note_outlined,
      ),
      const SizedBox(height: 12),
      AdminSeriesChart(
        title: 'Lessen afgerond',
        series: data.lessonsCompleted,
        icon: Icons.task_alt,
      ),
      const SizedBox(height: 12),
      AdminSeriesChart(
        title: 'Nieuwe abonnees',
        series: data.newSubscribers,
        icon: Icons.workspace_premium_outlined,
      ),
      const SizedBox(height: 12),
      AdminSeriesChart(
        title: 'Opzeggingen',
        series: data.cancellations,
        icon: Icons.trending_down,
        tint: AppTheme.inkMuted,
      ),

      const SizedBox(height: 22),
      const SectionHeader(eyebrow: 'Populair', title: 'Meest bekeken'),
      const SizedBox(height: 10),
      if (data.topPages.isEmpty)
        const _EmptyCard(text: 'Nog geen paginaweergaven in deze periode.')
      else
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < data.topPages.length; i++)
                AdminStatRow(
                  label: data.topPages[i].label,
                  value:
                      '${adminNumber(data.topPages[i].views)} × · '
                      '${adminNumber(data.topPages[i].visitors)} bezoekers',
                  showRule: i < data.topPages.length - 1,
                ),
            ],
          ),
        ),

      const SizedBox(height: 16),
      const SectionHeader(eyebrow: 'Interactie', title: 'Meest geklikt'),
      const SizedBox(height: 10),
      if (data.topClicks.isEmpty)
        const _EmptyCard(text: 'Nog geen kliks geregistreerd in deze periode.')
      else
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < data.topClicks.length; i++)
                AdminStatRow(
                  label: data.topClicks[i].target,
                  value: adminNumber(data.topClicks[i].count),
                  showRule: i < data.topClicks.length - 1,
                ),
            ],
          ),
        ),

      const SizedBox(height: 22),
      const SectionHeader(eyebrow: 'Bijbelstudies', title: 'Voortgang'),
      const SizedBox(height: 10),
      AppCard(
        child: Column(
          children: [
            AdminStatRow(
              label: 'Actieve deelnames',
              value: adminNumber(data.study.enrollmentsActive),
            ),
            AdminStatRow(
              label: 'Afgeronde deelnames',
              value: adminNumber(data.study.enrollmentsCompleted),
            ),
            AdminStatRow(
              label: 'Totaal deelnames',
              value: adminNumber(data.study.enrollmentsTotal),
            ),
            AdminStatRow(
              label: 'Actieve deelnemers',
              value: adminNumber(data.study.activeStudents),
            ),
            AdminStatRow(
              label: 'Reflecties geschreven',
              value: adminNumber(data.study.reflectionsWritten),
            ),
            AdminStatRow(
              label: 'Quizpogingen',
              value: adminNumber(data.study.quizAttempts),
            ),
            AdminStatRow(
              label: 'Quizzen nagekeken',
              value: adminNumber(data.study.quizzesGraded),
            ),
            AdminStatRow(
              label: 'Quizscore',
              // Null when nothing is graded yet — an em dash, not 0%.
              value: data.study.quizAccuracy == null
                  ? '—'
                  : adminPercent(data.study.quizAccuracy!.toDouble()),
              showRule: false,
            ),
          ],
        ),
      ),

      if (data.study.perStudy.isNotEmpty) ...[
        const SizedBox(height: 16),
        const SectionHeader(eyebrow: 'Per studie', title: 'Trechter'),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < data.study.perStudy.length; i++)
                AdminStatRow(
                  label: data.study.perStudy[i].title,
                  value:
                      '${adminNumber(data.study.perStudy[i].completed)} / '
                      '${adminNumber(data.study.perStudy[i].enrollments)}',
                  showRule: i < data.study.perStudy.length - 1,
                ),
            ],
          ),
        ),
      ],
    ];
  }
}

class _RangePicker extends StatelessWidget {
  const _RangePicker({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 7, label: Text('7 dagen')),
        ButtonSegment(value: 30, label: Text('30 dagen')),
        ButtonSegment(value: 90, label: Text('90 dagen')),
      ],
      selected: {days},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Text(
        text,
        style: AppTheme.caption.copyWith(color: AppTheme.inkMuted),
      ),
    );
  }
}
