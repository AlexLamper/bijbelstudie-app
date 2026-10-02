import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible_year/present/bible_year_providers.dart';
import '../../bible_year/present/plan_today_compact_card.dart';
import '../data/dashboard_models.dart';
import '../data/resume_models.dart';
import 'continue_study_card.dart';
import 'resume_providers.dart';

/// The Start tab's one main card, above the tekst van de dag.
///
/// Exactly one of two things, never both (designs 28a / 28b):
/// * a reading plan runs and today is not finished -> the plan card;
/// * no plan, or today already done, and a study or chapter is in progress ->
///   "Waar je gebleven was";
/// * neither -> nothing at all, so the verse card moves up.
///
/// Both are deliberately compact: the tekst van de dag has to be fully in view
/// without scrolling, so at large text sizes the plan card drops its chip row
/// rather than letting the verse fall under the fold.
class HomeMainCard extends ConsumerStatefulWidget {
  const HomeMainCard({super.key, required this.data, this.bottomSpacing = 14});

  final DashboardData data;

  /// The gap below the card, carried here so the slot collapses completely
  /// when there is no main card to show.
  final double bottomSpacing;

  @override
  ConsumerState<HomeMainCard> createState() => _HomeMainCardState();
}

class _HomeMainCardState extends ConsumerState<HomeMainCard>
    with BibleYearRefreshOnMount {
  /// `/dashboard` said there is no plan and nothing has built the plan state
  /// yet: do not ask `/bible-year` at all.
  bool get _skipPlan =>
      widget.data.bibleYearActive == false && !ref.exists(bibleYearProvider);

  @override
  bool get bibleYearRefreshOnMount => !_skipPlan;

  @override
  bool get bibleYearKnownActive => widget.data.bibleYearActive == true;

  /// The chips are the first thing to go when the reader's text is large.
  bool get _showChips => MediaQuery.textScalerOf(context).scale(14) <= 18.2;

  Widget _spaced(Widget child) => Padding(
    padding: EdgeInsets.only(bottom: widget.bottomSpacing),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    if (!_skipPlan) {
      final async = ref.watch(bibleYearProvider);
      final state = async.value;
      final today = state?.today;
      final enrollment = state?.enrollment;

      if (state != null && state.isActive && today != null && enrollment != null) {
        final view = PlanTodayView(
          today: today,
          enrollment: enrollment,
          calendar: ref.watch(planCalendarProvider).value,
        );
        if (!today.todayDone && !view.dayDone) {
          return _spaced(PlanTodayCompactCard(view: view, showChips: _showChips));
        }
      } else if (state == null &&
          async.isLoading &&
          widget.data.bibleYearActive == true) {
        // A plan runs, so hold its space rather than flashing the resume card
        // and swapping it out a moment later.
        return _spaced(const Skeleton(height: 118, radius: AppTheme.radiusLg));
      }
    }

    // No plan card: the resume card, unless there is nothing to resume - a new
    // account gets no main card at all rather than a "begin" placeholder.
    final resume = watchResume(
      ref,
      server: widget.data.resume,
      lastRead: widget.data.lastRead,
      readChapters: widget.data.readChapters,
    );
    if (resume.primary.kind == ResumeKind.start) return const SizedBox.shrink();

    return _spaced(
      ContinueStudyCard(
        compact: true,
        resume: widget.data.resume,
        lastRead: widget.data.lastRead,
        readChapters: widget.data.readChapters,
      ),
    );
  }
}
