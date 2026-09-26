import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/notification_scheduler.dart';
import '../../../core/notifications/permission_moment.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../settings/data/notification_prefs.dart';
import '../data/bible_year_models.dart';
import '../data/bible_year_repository.dart';
import 'bible_year_progress.dart';
import 'bible_year_providers.dart';
import 'bible_year_start_flow.dart';
import 'bible_year_today_card.dart';

/// `/studies/bijbel-in-een-jaar` - the app's counterpart of the website's
/// `BibleYearHome`: the start flow when no plan runs, today + the coming days
/// + progress while one does, and the finish with "Opnieuw beginnen" once the
/// whole Bible is read.
class BibleYearScreen extends ConsumerStatefulWidget {
  const BibleYearScreen({super.key, this.initialPlan});

  /// Preselected in the start flow (`?plan=jaar-2` from the Studies tab).
  final BibleYearPlanKey? initialPlan;

  @override
  ConsumerState<BibleYearScreen> createState() => _BibleYearScreenState();
}

class _BibleYearScreenState extends ConsumerState<BibleYearScreen> with BibleYearRefreshOnMount {
  bool _restarting = false;

  /// The shared notification prefs (DAILY_HABIT_PLAN.md §4): the plan rides
  /// the morning slot ("Ochtend"). A time chosen here is the morning time and
  /// switches the plan's content on; "Geen herinnering" ([minutes] null)
  /// switches the plan's content off and leaves every other notification
  /// alone. A reminder without OS permission goes through the permission
  /// sheet, like every other ask.
  Future<void> _saveReminder(int? minutes) async {
    // Read before the first await: the start flow's answer can land after
    // this screen has moved on.
    final prefs = ref.read(notificationPrefsProvider.notifier);
    final rescheduler = ref.read(notificationReschedulerProvider);
    await prefs.loaded;
    if (minutes == null) {
      await prefs.setContent(DailyContentKind.plan, false);
      rescheduler.requestReschedule(contentChanged: false);
      return;
    }
    await prefs.setMorningMinutes(minutes);
    await prefs.setContent(DailyContentKind.plan, true);
    await prefs.enableIfUnset();
    if (mounted) {
      // Reschedules itself when it changes anything.
      await maybeAskForNotifications(context, ref, PermissionMoment.planReminder);
    }
    rescheduler.requestReschedule(contentChanged: false);
  }

  Future<String?> _submit(BibleYearStartBody body, int? reminder, {required bool again}) async {
    final controller = ref.read(bibleYearProvider.notifier);
    final error = again ? await controller.restart(body) : await controller.start(body);
    if (error != null) return error;
    if (mounted) setState(() => _restarting = false);
    await _saveReminder(reminder);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final async = ref.watch(bibleYearProvider);

    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _AppBar(),
            Expanded(
              child: RefreshIndicator(
                color: AppTheme.teal,
                onRefresh: () => ref.read(bibleYearProvider.notifier).refresh(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  children: _body(async),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(AsyncValue<BibleYearState> async) {
    final data = async.value;
    if (data == null) {
      if (async.hasError) {
        final error = async.error;
        if (error is BibleYearException && error.isUnauthorized) {
          return [
            _MessageCard(
              message: 'Log opnieuw in om je leesplan te zien.',
              actionLabel: 'Inloggen',
              onAction: () => context.go('/login'),
            ),
          ];
        }
        return [
          _MessageCard(
            message: error is BibleYearException ? error.message : 'Je leesplan kon niet worden geladen.',
            actionLabel: 'Opnieuw proberen',
            onAction: () => ref.invalidate(bibleYearProvider),
          ),
        ];
      }
      return [
        Semantics(label: 'Leesplan laden', child: const SkeletonCardColumn(count: 2)),
      ];
    }

    final enrollment = data.enrollment;
    final active = enrollment != null && enrollment.isActive ? enrollment : null;

    if (enrollment != null && enrollment.isCompleted && !_restarting) {
      return [
        BibleYearCompleteCard(
          enrollment: enrollment,
          onRestart: () => setState(() => _restarting = true),
        ),
      ];
    }

    final today = data.today;
    if (active == null || today == null) {
      final again = enrollment?.isCompleted == true;
      return [
        if (!again) ...[
          Text(
            'Lees de hele Bijbel in een jaar of in twee jaar. Elke dag een stuk van ongeveer dezelfde lengte, en je ziet steeds hoe ver je bent.',
            style: AppTheme.bodyMuted.copyWith(fontSize: 14.5, height: 1.7, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 16),
        ],
        BibleYearStartFlow(
          catalogue: data.catalogue,
          tracks: data.tracks,
          initialPlan: widget.initialPlan,
          heading: again ? 'Opnieuw beginnen' : 'Begin met Bijbel in een jaar',
          onCancel: again ? () => setState(() => _restarting = false) : null,
          onSubmit: (body, reminder) => _submit(body, reminder, again: again),
        ),
      ];
    }

    final schedule = ref
        .watch(
          bibleYearScheduleProvider((
            plan: active.planKey,
            track: active.track,
            version: active.scheduleVersion,
          )),
        )
        .value;
    final controller = ref.read(bibleYearProvider.notifier);

    return [
      BibleYearTodayCard(
        today: today,
        startDate: active.startDate,
        schedule: schedule,
        onMarkRefs: controller.markRefs,
        onMarkDay: controller.markDay,
        onShift: controller.shift,
        onOpenChapter: (chapter) => openBibleYearChapter(context, ref, chapter),
      ),
      if (schedule != null) ...[
        const SizedBox(height: 16),
        BibleYearScheduleOverview(
          schedule: schedule,
          fromDay: today.dayNumber < 0 ? 0 : today.dayNumber,
          startDate: active.startDate,
          shiftDays: active.shiftDays,
        ),
      ],
      const SizedBox(height: 16),
      BibleYearProgressCard(
        enrollment: active,
        catalogue: data.catalogue,
        tracks: data.tracks,
        onStop: controller.stop,
      ),
    ];
  }
}

class _AppBar extends StatelessWidget {
  const _AppBar();

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.rule)),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Terug',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.canPop() ? context.pop() : context.go('/studies'),
              child: SizedBox(
                width: 36,
                height: 44,
                child: Icon(Icons.arrow_back_ios_new, size: 20, color: AppTheme.inkSoft),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'Bijbel in een jaar',
                style: AppTheme.displayTitle.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.actionLabel, required this.onAction});

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: AppTheme.bodyMuted.copyWith(fontSize: 14.5, color: AppTheme.inkSoft)),
          const SizedBox(height: 12),
          SiteOutlineButton(label: actionLabel, expand: false, height: 40, onPressed: onAction),
        ],
      ),
    );
  }
}
