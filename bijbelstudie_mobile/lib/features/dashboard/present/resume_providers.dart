import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/bible_books.dart';
import '../../bible/present/bible_providers.dart';
import '../../studies/data/enrollment_models.dart';
import '../../studies/present/studies_providers.dart';
import '../../study/present/study_pane_controller.dart';
import '../data/dashboard_models.dart';
import '../data/resume_link.dart';
import '../data/resume_models.dart';

/// Opens a resume item's [href] in the app: a lesson or study route is pushed,
/// a chapter is opened in the reader the way every other "lees hoofdstuk"
/// link does it (reader location, reader half of the split screen, Bijbel tab).
void openResumeHref(BuildContext context, WidgetRef ref, String href) {
  switch (resumeTargetFor(href)) {
    case ResumeChapter(:final book, :final chapter, :final version):
      ref
          .read(readerLocationProvider.notifier)
          .openChapter(versionId: version, book: book, chapter: chapter);
      ref.read(studyPaneProvider.notifier).showReader();
      context.go('/study');
    case final ResumeRoute route when route.isTab:
      context.go(route.location);
    case final ResumeRoute route:
      context.push(route.location);
  }
}

/// The go_router location of a lesson, with `?stap=` when a step is known.
String lessonLocation(String studyId, int day, [StudyStep? step]) {
  final base = '/studie/$studyId/$day';
  if (step == null || step == StudyStep.done) return base;
  return '$base?stap=${step.id}';
}

/// The resume answer built on the device, for a server that does not send
/// `resume` yet (or a cached payload from before it did). Same meaning as the
/// old card: the most recently active unfinished study, else the last chapter
/// read, else an invitation to start.
///
/// [step] is only honoured when it belongs to the lesson being resumed.
DashboardResume buildLocalResume({
  ContinuePick? pick,
  StudyEnrollment? enrollment,
  LastRead? lastRead,
  Map<String, List<int>> readChapters = const {},
}) {
  if (pick != null) {
    final study = pick.study;
    final total = study.lessonCount;
    final day = pick.resumeDay;
    final lesson = study.lessonForDay(day);
    final cursorStep =
        enrollment != null && enrollment.currentLessonDay == day ? enrollment.resumeStep : null;
    final stepIndex = cursorStep == null ? 0 : StudyStep.renderable.indexOf(cursorStep) + 1;
    final step = cursorStep == null
        ? null
        : ResumeStep(
            id: cursorStep,
            index: stepIndex,
            count: StudyStep.renderable.length,
            label: cursorStep.label,
          );

    final lessonPart = total > 0 ? 'Les $day van $total' : 'Les $day';
    final titlePart = lesson?.title.trim() ?? '';

    return DashboardResume(
      primary: ResumeItem(
        kind: ResumeKind.study,
        title: study.title,
        subtitle: titlePart.isEmpty ? lessonPart : '$lessonPart · $titlePart',
        studyId: study.id,
        lessonDay: day,
        step: step,
        progress: total > 0
            ? ResumeProgress(done: pick.completed.clamp(0, total), total: total)
            : null,
        // The website's wording (`lib/dashboardResume.ts`).
        cta: step == null
            ? 'Verder met de les'
            : stepIndex <= 1
            ? 'Begin les $day'
            : 'Verder met stap $stepIndex',
        href: lessonLocation(study.id, day, cursorStep),
      ),
    );
  }

  if (lastRead != null) {
    final book = BibleBooks.toCanonical(lastRead.book);
    final total = BibleBooks.chapterCounts[book];
    final read = (readChapters[book] ?? const <int>[]).length;
    final href = Uri(
      path: '/lezen',
      queryParameters: {
        // The stored spelling, as the website's href carries it: the reader
        // resolves the translation's folder by it.
        'book': lastRead.book,
        'chapter': '${lastRead.chapter}',
        'version': lastRead.version,
      },
    ).toString();
    return DashboardResume(
      primary: ResumeItem(
        kind: ResumeKind.chapter,
        title: '$book ${lastRead.chapter}',
        subtitle: total == null ? null : '${read.clamp(0, total)} van $total hoofdstukken',
        progress: total == null ? null : ResumeProgress(done: read.clamp(0, total), total: total),
        cta: 'Verder lezen',
        href: href,
      ),
    );
  }

  return const DashboardResume(primary: startResumeItem);
}

/// The start prompt, word for word the website's (`START_ITEM` in
/// `lib/dashboardResume.ts`). The card adds "Of begin met lezen" under it.
const ResumeItem startResumeItem = ResumeItem(
  kind: ResumeKind.start,
  title: 'Kies een studie of begin met lezen',
  subtitle: 'Je laatste les of hoofdstuk verschijnt hier',
  cta: 'Kies een studie',
  href: '/studies',
);

/// What the "Verder waar je gebleven was" card shows: the server's answer when
/// it sent one, else [buildLocalResume] from this device's study state.
DashboardResume watchResume(
  WidgetRef ref, {
  DashboardResume? server,
  LastRead? lastRead,
  Map<String, List<int>> readChapters = const {},
}) {
  if (server != null) return server;
  final pick = ref.watch(continueStudyProvider);
  final enrollment = pick == null ? null : ref.watch(studyEnrollmentProvider(pick.study.id));
  return buildLocalResume(
    pick: pick,
    enrollment: enrollment,
    lastRead: lastRead,
    readChapters: readChapters,
  );
}
