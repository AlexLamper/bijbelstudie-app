import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../study/domain/lesson_models.dart';
import '../data/study_models.dart';
import 'studies_providers.dart';
import 'study_banner.dart';
import 'study_settings_sheet.dart';

/// The public face of a study: what it is about, what you will read, and one
/// button to begin or carry on.
///
/// The website splits this into two scrolling panes beside each other. A phone
/// gets one scroll with the action pinned to the bottom, because the decision
/// the screen exists to support - start this or not - must never be scrolled
/// out of reach.
class StudyDetailScreen extends ConsumerWidget {
  const StudyDetailScreen({super.key, required this.studyId});

  final String studyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final study = ref.watch(curatedStudyProvider(studyId));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goBack(context);
      },
      child: Scaffold(
      backgroundColor: AppTheme.paper,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Terug naar studies',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _goBack(context),
        ),
        title: Text(study.value?.title ?? 'Studie'),
        actions: [
          if (study.value != null)
            IconButton(
              tooltip: 'Studie-instellingen',
              icon: const Icon(Icons.tune),
              onPressed: () => _openSettings(context, ref, study.value!),
            ),
        ],
      ),
      body: study.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: SkeletonCardColumn(count: 2),
        ),
        error: (error, _) => const AppEmptyState(
          icon: Icons.wifi_off_outlined,
          title: 'Studie niet geladen',
          description: 'Controleer je verbinding en probeer het opnieuw.',
        ),
        data: (data) {
          if (data == null) {
            return const AppEmptyState(
              icon: Icons.search_off,
              title: 'Studie niet gevonden',
              description: 'Deze studie bestaat niet meer.',
            );
          }
          return _Body(study: data);
        },
      ),
      ),
    );
  }

  static void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/studies');
    }
  }

  Future<void> _openSettings(
    BuildContext context,
    WidgetRef ref,
    CuratedStudy study,
  ) async {
    final enrollment = ref.read(studyEnrollmentProvider(study.id));
    await showStudySettingsSheet(
      context,
      ref,
      study: study,
      enrollment: enrollment,
      // Already enrolled, so this only saves - it never starts a lesson.
      startAfterSave: false,
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.study});

  final CuratedStudy study;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(studyStatusProvider(study));
    final enrollment = status.enrollment;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(AppTheme.radiusMd),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 6,
                  child: StudyBanner(study: study),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  SiteBadge.teal(_typeLabel(study.type)),
                  const SizedBox(width: 8),
                  if (status.completed)
                    SiteBadge.positive('Voltooid', icon: Icons.check_circle)
                  else if (status.started)
                    SiteBadge.neutral('${status.done} van ${status.total} lessen'),
                ],
              ),
              const SizedBox(height: 12),
              Text(study.title, style: AppTheme.displayLarge),
              const SizedBox(height: 18),
              const SectionHeader(
                eyebrow: 'Voor je begint',
                title: 'Waar gaat deze studie over?',
              ),
              const SizedBox(height: 10),
              // At most two paragraphs, as on the website: this is a decision
              // aid, not the study itself.
              for (final paragraph in _about(study))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(paragraph, style: AppTheme.bodyLead),
                ),
              const SizedBox(height: 8),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _FactLine(
                      icon: Icons.checklist,
                      label: '${study.lessonCount} lessen',
                    ),
                    _FactLine(
                      icon: Icons.schedule,
                      label: '± ${formatStudyMinutes(study.estimatedMinutes)} totaal',
                    ),
                    for (final entry in _readingPlan(study))
                      _FactLine(
                        icon: Icons.menu_book_outlined,
                        label: entry,
                        showRule: entry != _readingPlan(study).last,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SectionHeader(
                eyebrow: 'Les voor les',
                title: 'De lessen',
                description: '${status.done} van ${study.lessonCount} afgerond',
              ),
              const SizedBox(height: 10),
              RuleGrid(
                children: [
                  for (final lesson in study.lessons)
                    _LessonTile(
                      study: study,
                      lesson: lesson,
                      done: status.completedDays.contains(lesson.day),
                      isCurrent: !status.completed && lesson.day == status.resumeDay(study),
                      enrolled: enrollment != null,
                    ),
                ],
              ),
            ],
          ),
        ),
        _ActionBar(study: study, status: status),
      ],
    );
  }

  static List<String> _about(CuratedStudy study) {
    final paragraphs = study.about.isNotEmpty ? study.about : [study.description];
    return paragraphs.where((p) => p.isNotEmpty).take(2).toList(growable: false);
  }

  /// `Markus 1-16`, one line per book. Contiguous chapters collapse to a range
  /// and gaps stay listed, so the line is honest about what you actually read.
  static List<String> _readingPlan(CuratedStudy study) {
    final byBook = <String, List<int>>{};
    for (final lesson in study.lessons) {
      if (lesson.book.isEmpty) continue;
      (byBook[lesson.book] ??= []).add(lesson.chapter);
    }

    final lines = <String>[];
    for (final entry in byBook.entries) {
      final chapters = entry.value.toSet().toList()..sort();
      lines.add('${entry.key} ${_collapse(chapters)}');
    }
    return lines;
  }

  static String _collapse(List<int> chapters) {
    if (chapters.isEmpty) return '';
    if (chapters.length == 1) return '${chapters.first}';
    final contiguous = chapters.last - chapters.first == chapters.length - 1;
    if (contiguous) return '${chapters.first}-${chapters.last}';
    return chapters.join(', ');
  }

  static String _typeLabel(String type) => switch (type) {
    'Boek' => 'Bijbelboek',
    'Persoon' => 'Persoon',
    'Gedeelte' => 'Gedeelte',
    _ => 'Onderwerp',
  };
}

class _FactLine extends StatelessWidget {
  const _FactLine({required this.icon, required this.label, this.showRule = true});

  final IconData icon;
  final String label;
  final bool showRule;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: showRule
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.rule)),
            )
          : null,
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppTheme.teal),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppTheme.bodyStrong)),
        ],
      ),
    );
  }
}

/// One lesson. Expanding it reveals the focus question and the way in - or the
/// reason there is no way in yet.
class _LessonTile extends ConsumerStatefulWidget {
  const _LessonTile({
    required this.study,
    required this.lesson,
    required this.done,
    required this.isCurrent,
    required this.enrolled,
  });

  final CuratedStudy study;
  final StudyLesson lesson;
  final bool done;
  final bool isCurrent;
  final bool enrolled;

  @override
  ConsumerState<_LessonTile> createState() => _LessonTileState();
}

class _LessonTileState extends ConsumerState<_LessonTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;

    return Column(
      children: [
        RuleListTile(
          showRule: false,
          onTap: () => setState(() => _open = !_open),
          child: Row(
            children: [
              _DayDisc(day: lesson.day, done: widget.done, isCurrent: widget.isCurrent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lesson.title,
                            style: AppTheme.bodyStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.isCurrent) ...[
                          const SizedBox(width: 6),
                          SiteBadge.teal('Nu'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${lesson.reference} · ${widget.study.minutesPerLesson} min',
                      style: AppTheme.caption.copyWith(color: AppTheme.teal),
                    ),
                  ],
                ),
              ),
              Icon(
                _open ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: AppTheme.inkMuted,
              ),
            ],
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (lesson.focus.isNotEmpty) ...[
                  Text(lesson.focus, style: AppTheme.bodyMuted),
                  const SizedBox(height: 10),
                ],
                if (widget.enrolled)
                  SiteOutlineButton(
                    label: widget.done ? 'Opnieuw doen' : 'Open deze les',
                    icon: Icons.play_arrow,
                    height: 40,
                    expand: false,
                    onPressed: () => context.push(
                      '/studie/${widget.study.id}/${lesson.day}',
                    ),
                  )
                else
                  Row(
                    children: [
                      Icon(Icons.lock_outline, size: 14, color: AppTheme.inkMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Start de studie om deze les te openen.',
                          style: AppTheme.caption,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        RuleLine(),
      ],
    );
  }
}

class _DayDisc extends StatelessWidget {
  const _DayDisc({required this.day, required this.done, required this.isCurrent});

  final int day;
  final bool done;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? AppTheme.teal : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: done || isCurrent ? AppTheme.teal : AppTheme.rule,
          width: isCurrent && !done ? 2 : 1,
        ),
      ),
      child: done
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : Text('$day', style: AppTheme.metaLabel.copyWith(color: AppTheme.inkSoft)),
    );
  }
}

/// The pinned footer: how far along, and the one thing to do next.
class _ActionBar extends ConsumerStatefulWidget {
  const _ActionBar({required this.study, required this.status});

  final CuratedStudy study;
  final StudyStatus status;

  @override
  ConsumerState<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends ConsumerState<_ActionBar> {
  bool _busy = false;

  Future<void> _start() async {
    final study = widget.study;
    setState(() => _busy = true);
    try {
      final started = await showStudySettingsSheet(
        context,
        ref,
        study: study,
        enrollment: null,
        startAfterSave: true,
      );
      if (!mounted || started == null) return;
      context.push('/studie/${study.id}/${started.currentLessonDay}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final study = widget.study;
    final started = status.started;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.paperRaised,
        border: Border(top: BorderSide(color: AppTheme.rule)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      started
                          ? 'Je bent bezig met deze studie'
                          : 'Je bent nog niet begonnen',
                      style: AppTheme.caption,
                    ),
                  ),
                  Text(
                    started ? '${status.progressPercent}%' : '${status.total} lessen',
                    style: AppTheme.metaLabel,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (started) ...[
                SiteProgressBar(value: status.progress),
                const SizedBox(height: 10),
              ],
              SiteButton(
                label: status.completed
                    ? 'Studie opnieuw lezen'
                    : started
                    ? 'Verder met les ${status.resumeDay(study)}'
                    : 'Start deze studie',
                trailingIcon: Icons.arrow_forward,
                loading: _busy,
                onPressed: _busy
                    ? null
                    : () {
                        if (started) {
                          final step = status.enrollment?.resumeStep;
                          final suffix = step == null ? '' : '?stap=${step.id}';
                          context.push(
                            '/studie/${study.id}/${status.resumeDay(study)}$suffix',
                          );
                          return;
                        }
                        _start();
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
