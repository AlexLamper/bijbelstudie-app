import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/notification_scheduler.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../levensboom/domain/catalog.dart';
import '../../levensboom/domain/tree_state.dart';
import '../../levensboom/present/levensboom_avatar.dart';
import '../../levensboom/present/levensboom_providers.dart';
import '../../levensboom/present/mini_tree.dart';
import '../data/dashboard_models.dart';
import 'continue_study_card.dart';

/// The detail panel behind the header streak/week-goal ring
/// (`HomeStreakIndicator`). Explains, in plain Dutch, what the ring is
/// counting, what today's actual value is, which of the last 7 days were
/// done, how a freeze/grace day works, and how the goal itself is set — a
/// daily streak or a "3x per week" week goal, depending on the reader's own
/// study cadence.
///
/// All the numbers shown here come from the caller (`HomeStreakIndicator`,
/// which already reads `retentionStoreProvider` and the dashboard's weekly
/// data). The one thing the sheet reads on its own is `treeStateProvider`,
/// for the same reason the header does: the mark at the top is the reader's
/// own tree, and "beste reeks" lives on that state.
Future<void> showStreakDetailSheet(
  BuildContext context, {
  required CadenceInfo cadence,
  required int streak,
  required int freezes,
  required int completionsThisWeek,
  required List<WeekDay> weekDays,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _StreakDetailSheet(
      cadence: cadence,
      streak: streak,
      freezes: freezes,
      completionsThisWeek: completionsThisWeek,
      weekDays: weekDays,
    ),
  );
}

const _kWeekdayLabels = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];

/// The header mark is 48; the sheet shows the same object a step larger.
const double _kHeroSize = 64;

String _dayWord(int n) => n == 1 ? 'dag' : 'dagen';
String _lessonWord(int n) => n == 1 ? 'les' : 'lessen';

class _StreakDetailSheet extends ConsumerWidget {
  const _StreakDetailSheet({
    required this.cadence,
    required this.streak,
    required this.freezes,
    required this.completionsThisWeek,
    required this.weekDays,
  });

  final CadenceInfo cadence;
  final int streak;
  final int freezes;
  final int completionsThisWeek;
  final List<WeekDay> weekDays;

  bool get _isWeekGoal => cadence.model == RetentionModel.weekGoal;

  /// Whether there is anything to glow about yet: a running streak, or at
  /// least one completion this week. Otherwise the mark stays muted.
  bool get _lit => _isWeekGoal ? completionsThisWeek > 0 : streak > 0;

  /// "Elke dag", "3x per week (ma, wo, vr)", …
  String get _cadenceLabel {
    if (!_isWeekGoal) return 'elke dag';
    if (cadence.fixedWeekdays.isEmpty) {
      return '${cadence.weekGoalTarget}x per week';
    }
    final days = cadence.fixedWeekdays.toList()..sort();
    final labels = days.map((d) => _kWeekdayLabels[d - 1]).join(', ');
    return '${cadence.weekGoalTarget}x per week ($labels)';
  }

  /// The count under the title. Singular and plural are both real cases here:
  /// a streak of 1 is the most common streak there is.
  String get _countLine {
    if (_isWeekGoal) {
      return '$completionsThisWeek van de ${cadence.weekGoalTarget} keer deze week';
    }
    return streak > 0 ? '$streak ${_dayWord(streak)} op rij' : 'Nog geen reeks';
  }

  /// The reader's own tree with the count in its badge — the header mark,
  /// grown a step — or, for readers who switched the tree off, the plain
  /// icon: "Boom verbergen" means no tree anywhere (TREE_FEATURE_PLAN §10).
  Widget _mark(TreeState? tree) {
    if (tree?.disabled == true) {
      return IconChip(
        icon: _isWeekGoal ? Icons.flag_outlined : Icons.local_fire_department,
        color: _isWeekGoal ? AppTheme.teal : AppTheme.flame,
        size: _kHeroSize,
        iconSize: 28,
      );
    }
    if (_isWeekGoal) {
      final target = cadence.weekGoalTarget;
      return MiniTree(
        tree: tree,
        badge: '$completionsThisWeek/$target',
        semanticsLabel:
            'Je boom — $completionsThisWeek van $target ${_lessonWord(target)} deze week',
        dormant: completionsThisWeek <= 0,
        size: _kHeroSize,
      );
    }
    return MiniTree(
      tree: tree,
      badge: '$streak',
      semanticsLabel: freezes > 0
          ? 'Je boom — reeks van $streak ${_dayWord(streak)}, met een vrije dag'
          : 'Je boom — reeks van $streak ${_dayWord(streak)}',
      dormant: streak <= 0,
      hasFreeze: freezes > 0,
      size: _kHeroSize,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final pick = ref.watch(continueStudyProvider);
    final tree = ref.watch(treeStateProvider).value;

    // Same rule as the lesson card and the celebration: the account's own
    // motion pref, or the OS one, and nothing moves.
    final still =
        (tree?.reducedMotion ?? false) ||
        MediaQuery.maybeDisableAnimationsOf(context) == true;

    // The glow takes the accent the rest of the app already gives this
    // reader: gold for a Pro ring, otherwise flame for a streak and teal for
    // a week goal, matching the icon the sheet used to open with.
    final gold = tree?.avatar.ring == TreeRing.goud;
    final accent = gold
        ? kGoldRing
        : (_isWeekGoal ? AppTheme.teal : AppTheme.flame);

    final best = tree?.longestStreak ?? 0;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _Hero(
                  accent: accent,
                  lit: _lit,
                  still: still,
                  child: _mark(tree),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isWeekGoal ? 'Je weekdoel' : 'Je leesreeks',
                        style: AppTheme.displayTitle.copyWith(color: scheme.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _countLine,
                        style: AppTheme.bodyStrong.copyWith(
                          color: AppTheme.teal,
                          fontSize: 13,
                        ),
                      ),
                      if (!_isWeekGoal && best > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          streak >= best
                              ? 'Je beste reeks tot nu toe'
                              : 'Beste reeks: $best ${_dayWord(best)}',
                          style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _WeekStrip(days: weekDays, still: still),
            const SizedBox(height: 20),
            Text(
              _isWeekGoal
                  ? 'Dit doel telt hoe vaak je deze week een les afrondt of een hoofdstuk leest.'
                  : 'Deze reeks telt de dagen achter elkaar dat je een hoofdstuk leest of een studieles afrondt.',
              style: AppTheme.bodyMuted,
            ),
            const SizedBox(height: 10),
            Text(
              _isWeekGoal
                  ? 'Je studietempo staat op $_cadenceLabel. Rond dat aantal lessen af voor het einde van de week om je doel te halen.'
                  : 'Je studietempo staat op "$_cadenceLabel". Lees je liever een paar vaste dagen per week? Dat stel je in bij de instellingen van je studie.',
              style: AppTheme.bodyMuted,
            ),
            if (!_isWeekGoal) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.ac_unit, size: 16, color: AppTheme.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      freezes > 0
                          ? 'Je hebt $freezes bevriezingsdag${freezes == 1 ? '' : 'en'} gespaard. Mis je toch een dag, dan redt een vrije dag je reeks automatisch - als Pro-lid kun je daarna nog een bevriezingsdag inzetten.'
                          : 'Elke vijf dagen reeks verdien je een bevriezingsdag. Mis je een dag, dan blijft je reeks daarnaast nog één dag lang gespaard.',
                      style: AppTheme.caption.copyWith(color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Tip: lees op een vast moment van de dag - dan wordt het vanzelf een gewoonte.',
              style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
            ),
            const SizedBox(height: 20),
            SiteButton(
              label: pick != null ? 'Verder met ${pick.study.title}' : 'Bekijk bijbelstudies',
              trailingIcon: Icons.arrow_forward,
              onPressed: () {
                Navigator.of(context).pop();
                if (pick != null) {
                  context.push('/studie/${pick.study.id}/${pick.resumeDay}');
                } else {
                  context.push('/studies');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The tapped header mark at sheet size: a soft accent glow behind it and a
/// short settle-in on open, so the sheet reads as opening *out of* the ring
/// the reader just tapped rather than appearing beside it. A single finite
/// tween — nothing here loops — and skipped entirely under reduced motion.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.child,
    required this.accent,
    required this.lit,
    required this.still,
  });

  final Widget child;
  final Color accent;

  /// No glow while there is nothing to glow about yet (streak 0, nothing
  /// done this week); the mark itself is already muted then.
  final bool lit;

  final bool still;

  /// Room for the glow to fall off around the mark.
  static const double _box = _kHeroSize + 12;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _box,
      height: _box,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: still ? 1.0 : 0.0, end: 1.0),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Stack(
          alignment: Alignment.center,
          children: [
            if (lit)
              Positioned.fill(
                child: Opacity(
                  opacity: t,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          accent.withValues(alpha: 0.34),
                          accent.withValues(alpha: 0),
                        ],
                        stops: const [0.3, 1],
                      ),
                    ),
                  ),
                ),
              ),
            Transform.scale(
              scale: 0.82 + 0.18 * t,
              child: Opacity(opacity: t, child: child),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// A compact Ma–Zo strip: a filled dot for a day with activity, an outline for
/// one without, and a teal ring around today. The same 7-day data the "Deze
/// week" card on the dashboard renders, so the two never disagree.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.days, required this.still});

  final List<WeekDay> days;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final week = days.length == 7
        ? days
        : _kWeekdayLabels
              .map((l) => WeekDay(label: l, count: 0, heightPct: 0, isToday: false))
              .toList();

    return Row(
      children: [
        for (var i = 0; i < week.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                _WeekDot(day: week[i], order: i, still: still),
                const SizedBox(height: 6),
                Text(
                  week[i].label,
                  style: AppTheme.overline.copyWith(
                    letterSpacing: 0,
                    color: week[i].isToday ? AppTheme.teal : AppTheme.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One day of the strip. Done days pop in left to right when the sheet opens,
/// so the week reads as being counted up rather than as a static chart. Each
/// dot is its own finite tween on a shared timeline (an [Interval] per
/// position), and days without activity — and every day under reduced
/// motion — are simply drawn.
class _WeekDot extends StatelessWidget {
  const _WeekDot({required this.day, required this.order, required this.still});

  final WeekDay day;
  final int order;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = day.count > 0;

    final dot = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppTheme.teal : scheme.surfaceContainerHighest,
        border: day.isToday ? Border.all(color: AppTheme.teal, width: 2) : null,
      ),
      child: done ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
    );

    if (still || !done) return dot;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 900),
      curve: Interval(0.11 * order, 1, curve: Curves.easeOutBack),
      builder: (context, t, child) => Transform.scale(
        scale: 0.6 + 0.4 * t,
        // easeOutBack overshoots 1 for a moment; opacity must not.
        child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
      ),
      child: dot,
    );
  }
}
