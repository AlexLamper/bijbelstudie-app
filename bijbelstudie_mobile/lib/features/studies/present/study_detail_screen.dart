import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../notes/domain/note_models.dart';
import '../../notes/present/notes_providers.dart';
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
    AppTheme.dependOn(context);
    final study = ref.watch(curatedStudyProvider(studyId));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goBack(context);
      },
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _AppBar(
                title: study.value?.title ?? 'Studie',
                onBack: () => _goBack(context),
                onSettings: study.value == null
                    ? null
                    : () => _openSettings(context, ref, study.value!),
              ),
              Expanded(
                child: study.when(
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
            ],
          ),
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

class _AppBar extends StatelessWidget {
  const _AppBar({required this.title, required this.onBack, this.onSettings});

  final String title;
  final VoidCallback onBack;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.rule)),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Terug naar studies',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBack,
              child: Icon(
                Icons.arrow_back_ios_new,
                size: 20,
                color: AppTheme.inkSoft,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: AppTheme.displayTitle.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (onSettings != null) ...[
            const SizedBox(width: 14),
            Semantics(
              button: true,
              label: 'Studie-instellingen',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSettings,
                child: Icon(Icons.tune, size: 20, color: AppTheme.inkMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _DetailTab { lessons, about, notes }

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.study});

  final CuratedStudy study;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  _DetailTab _tab = _DetailTab.lessons;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final study = widget.study;
    final status = ref.watch(studyStatusProvider(study));

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _Banner(study: study, status: status),
              _Intro(
                study: study,
                onReadMore: () => setState(() => _tab = _DetailTab.about),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppTheme.rule)),
                  ),
                  child: AppUnderlineTabs(
                    labels: const ['Lessen', 'Over', 'Notities'],
                    gap: 24,
                    selectedIndex: _DetailTab.values.indexOf(_tab),
                    activeColor: AppTheme.ink,
                    onChanged: (index) =>
                        setState(() => _tab = _DetailTab.values[index]),
                  ),
                ),
              ),
              switch (_tab) {
                _DetailTab.lessons => _Timeline(study: study, status: status),
                _DetailTab.about => _About(study: study),
                _DetailTab.notes => _Notes(study: study),
              },
            ],
          ),
        ),
        _ActionBar(study: study, status: status),
      ],
    );
  }
}

/// The server banner, with the two facts that decide whether this study fits
/// the reader's week laid over it.
class _Banner extends StatelessWidget {
  const _Banner({required this.study, required this.status});

  final CuratedStudy study;
  final StudyStatus status;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    Widget pill(String label, {required Color background, required Color foreground}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        ),
        child: Text(
          label,
          style: AppTheme.caption.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      );
    }

    return SizedBox(
      height: 150,
      child: Stack(
        fit: StackFit.expand,
        children: [
          StudyBanner(study: study),
          Positioned(
            left: 16,
            bottom: 14,
            child: Row(
              children: [
                pill(
                  _typeLabel(study.type),
                  background: Colors.white,
                  foreground: AppTheme.tealStrong,
                ),
                const SizedBox(width: 8),
                pill(
                  '${study.lessonCount} lessen · ±${formatStudyMinutes(study.estimatedMinutes)}',
                  background: const Color(0x8C111827),
                  foreground: Colors.white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _typeLabel(String type) => switch (type) {
    'Boek' => 'Bijbelboek',
    'Persoon' => 'Persoon',
    'Gedeelte' => 'Gedeelte',
    _ => 'Onderwerp',
  };
}

/// Title and the first paragraph, with "Lees meer" as the way into the full
/// introduction on the Over tab rather than an expander that pushes the
/// lessons off the screen.
class _Intro extends StatelessWidget {
  const _Intro({required this.study, required this.onReadMore});

  final CuratedStudy study;
  final VoidCallback onReadMore;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final paragraphs = aboutParagraphs(study);
    final lead = paragraphs.isEmpty ? study.description : paragraphs.first;
    final hasMore = paragraphs.length > 1 || lead != study.description;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(study.title, style: AppTheme.screenTitle)),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: lead),
                if (hasMore) ...[
                  const TextSpan(text: ' '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: Semantics(
                      button: true,
                      child: GestureDetector(
                        onTap: onReadMore,
                        child: Text(
                          'Lees meer',
                          style: AppTheme.bodyMuted.copyWith(
                            height: 1.6,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.teal,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            style: AppTheme.bodyMuted.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}

/// The lessons as a timeline: one rail, one disc per lesson, three states.
///
/// The rail is what the old expander list could not give - at a glance you see
/// where you are in fifty lessons without reading a single title.
class _Timeline extends ConsumerWidget {
  const _Timeline({required this.study, required this.status});

  final CuratedStudy study;
  final StudyStatus status;

  /// Disc centre, measured from the padding box: 24 wide, so 12 in, minus half
  /// the 2px rail.
  static const double _railLeft = 11;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    // Unchanged rule: without an enrollment no lesson opens from here, so
    // nothing is "current" either and the footer is the only way in.
    final enrolled = status.enrollment != null;
    final resumeDay = status.resumeDay(study);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Stack(
        children: [
          Positioned(
            left: _railLeft,
            top: 26,
            bottom: 14,
            child: Container(width: 2, color: AppTheme.rule),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final lesson in study.lessons)
                _LessonRow(
                  study: study,
                  lesson: lesson,
                  done: status.completedDays.contains(lesson.day),
                  isCurrent:
                      enrolled && !status.completed && lesson.day == resumeDay,
                  enrolled: enrolled,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({
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
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final open = enrolled && (done || isCurrent);

    final titleStyle = isCurrent
        ? AppTheme.bodyStrong.copyWith(fontSize: 15, fontWeight: FontWeight.w700)
        : AppTheme.bodyMuted.copyWith(
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w500,
            color: done ? AppTheme.inkMuted : AppTheme.inkFaint,
          );

    final meta = '${lesson.reference} · ${study.minutesPerLesson} min'
        '${isCurrent ? ' · nu' : ''}';
    final metaStyle = AppTheme.caption.copyWith(
      fontSize: 12,
      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
      color: isCurrent
          ? AppTheme.teal
          : done
          ? AppTheme.inkFaint
          : AppTheme.ruleStrong,
    );

    return Semantics(
      button: open,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // A locked lesson is inert: no ripple, no snackbar. Telling someone
        // off for tapping is worse than nothing happening.
        onTap: open
            ? () => context.push('/studie/${study.id}/${lesson.day}')
            : null,
        child: Padding(
          padding: EdgeInsets.only(bottom: isCurrent ? 16 : 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LessonDisc(done: done, isCurrent: isCurrent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${lesson.day}. ${lesson.title}',
                      style: titleStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(meta, style: metaStyle, maxLines: 1),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LessonDisc extends StatelessWidget {
  const _LessonDisc({required this.done, required this.isCurrent});

  final bool done;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? AppTheme.positive
            : isCurrent
            ? AppTheme.surface
            : AppTheme.paperSunken,
        border: done
            ? null
            : Border.all(
                color: isCurrent ? AppTheme.teal : AppTheme.rule,
                width: isCurrent ? 2.5 : 1,
              ),
      ),
      child: done
          ? const Icon(Icons.check, size: 13, color: Colors.white, weight: 700)
          : null,
    );
  }
}

/// What the old screen showed above the lessons: the introduction in full and
/// the reading plan, now behind their own tab.
///
/// The facts were a bordered card of icon rows, which is the one shape this
/// redesign took off every other screen. They are two figures and a list
/// instead: what you are committing to, then what you will actually read.
class _About extends StatelessWidget {
  const _About({required this.study});

  final CuratedStudy study;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final plan = _readingPlan(study);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final paragraph in aboutParagraphs(study))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(paragraph, style: AppTheme.bodyLead),
            ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppTheme.rule),
                bottom: BorderSide(color: AppTheme.rule),
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Fact(
                    value: '${study.lessonCount}',
                    label: study.lessonCount == 1 ? 'les' : 'lessen',
                  ),
                  _Fact(
                    value: formatStudyMinutes(study.estimatedMinutes),
                    label: 'totale leestijd',
                    divided: true,
                  ),
                  _Fact(
                    value: '${study.minutesPerLesson}',
                    label: 'min per les',
                    divided: true,
                  ),
                ],
              ),
            ),
          ),
          if (plan.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 22, bottom: 10),
              child: Row(
                children: [
                  Text('WAT JE LEEST', style: AppTheme.groupLabel),
                  const SizedBox(width: 9),
                  Expanded(child: Container(height: 1, color: AppTheme.rule)),
                ],
              ),
            ),
            for (final entry in plan)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.menu_book_outlined,
                        size: 15,
                        color: AppTheme.teal,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry,
                        style: AppTheme.bodyStrong.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
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
}

/// One figure in the Over tab's strip.
class _Fact extends StatelessWidget {
  const _Fact({required this.value, required this.label, this.divided = false});

  final String value;
  final String label;

  /// Every column but the first carries the rule that separates it.
  final bool divided;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: divided
            ? BoxDecoration(
                border: Border(left: BorderSide(color: AppTheme.rule)),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: AppTheme.statNumber.copyWith(fontSize: 20),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reader's own notes on the books this study walks through.
///
/// Derived from the same `/notes` list the Notities tab reads - there is no
/// note-per-study on the server, and inventing one would mean a second source
/// of truth for the same rows.
class _Notes extends ConsumerWidget {
  const _Notes({required this.study});

  final CuratedStudy study;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final books = study.books.toSet();
    final notes = (ref.watch(notesListProvider).value ?? const <StudyNote>[])
        .where((note) => books.contains(note.book))
        .toList(growable: false);

    if (notes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: AppEmptyState(
          icon: Icons.edit_note_outlined,
          title: 'Nog geen notities',
          description:
              'Wat je tijdens deze studie opschrijft, verzamelt zich hier.',
        ),
      );
    }

    return Column(
      children: [
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${note.book} ${note.chapter}${note.verse == null ? '' : ':${note.verse}'}',
                  style: AppTheme.pillLabel.copyWith(color: AppTheme.teal),
                ),
                const SizedBox(height: 6),
                Text(
                  note.noteText,
                  style: AppTheme.bodyMuted.copyWith(
                    height: 1.6,
                    color: AppTheme.ink,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// At most two paragraphs, as on the website: this is a decision aid, not the
/// study itself.
List<String> aboutParagraphs(CuratedStudy study) {
  final paragraphs = study.about.isNotEmpty ? study.about : [study.description];
  return paragraphs.where((p) => p.isNotEmpty).take(2).toList(growable: false);
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
    AppTheme.dependOn(context);
    final status = widget.status;
    final study = widget.study;
    final started = status.started;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.rule)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      started
                          ? 'Je bent bezig met deze studie'
                          : 'Je bent nog niet begonnen',
                      style: AppTheme.caption.copyWith(fontSize: 13),
                    ),
                  ),
                  Text(
                    started ? '${status.progressPercent} %' : '${status.total} lessen',
                    style: AppTheme.caption.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (started) ...[
                SiteProgressBar(value: status.progress, height: 6),
                const SizedBox(height: 12),
              ],
              SiteButton(
                label: status.completed
                    ? 'Studie opnieuw lezen'
                    : started
                    ? 'Verder met les ${status.resumeDay(study)}'
                    : 'Start deze studie',
                trailingIcon: Icons.arrow_forward,
                height: 48,
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
