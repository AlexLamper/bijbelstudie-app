// The "Verder waar je gebleven was" answer: `resume` on `GET /api/v1/dashboard`.
//
// Mirrors `lib/resumeTypes.ts` on www.bijbelstudie.io, which the web dashboard
// renders from the same object, so the two never disagree about where the
// reader is (DAILY_HABIT_PLAN.md §3). Parsing is deliberately forgiving: an
// older server sends no `resume` at all, a newer one may add kinds or step ids
// this build does not know, and neither may take the Start tab down.

import '../../studies/data/enrollment_models.dart';

/// What the primary item points at. [other] is any kind this build does not
/// know yet; it is rendered like a chapter (title, subtitle, bar, button).
enum ResumeKind {
  study('study'),
  chapter('chapter'),
  start('start'),
  other('');

  const ResumeKind(this.id);

  final String id;

  static ResumeKind fromId(Object? id) {
    for (final kind in values) {
      if (kind != other && kind.id == id) return kind;
    }
    return other;
  }
}

/// Where in the lesson the reader is: "Stap 3 van 6 · Verdieping".
class ResumeStep {
  const ResumeStep({
    required this.id,
    required this.index,
    required this.count,
    required this.label,
  });

  final StudyStep id;

  /// 1-based position within this lesson's real step list.
  final int index;

  /// Steps this lesson actually has (the context step may be absent).
  final int count;

  final String label;

  String get caption => 'Stap $index van $count · $label';

  /// Null for a step id this build does not render (an installed app must
  /// drop ids it does not know rather than guess), or for a malformed value.
  static ResumeStep? fromJson(Object? json) {
    if (json is! Map) return null;
    final rawId = json['id'];
    final step = StudyStep.tryFromId(rawId is String ? rawId : null);
    if (step == null || step == StudyStep.done) return null;

    final fallbackIndex = StudyStep.renderable.indexOf(step) + 1;
    final count = _int(json['count']) ?? StudyStep.renderable.length;
    final safeCount = count < 1 ? StudyStep.renderable.length : count;
    final index = (_int(json['index']) ?? fallbackIndex).clamp(1, safeCount);
    final label = _text(json['label']) ?? step.label;

    return ResumeStep(id: step, index: index, count: safeCount, label: label);
  }
}

enum ResumeScheduleStatus {
  onSchedule('op-schema'),
  behind('achter'),
  ahead('vooruit');

  const ResumeScheduleStatus(this.id);

  final String id;

  static ResumeScheduleStatus? tryFromId(Object? id) {
    for (final status in values) {
      if (status.id == id) return status;
    }
    return null;
  }
}

class ResumeSchedule {
  const ResumeSchedule({required this.status, required this.lessons});

  final ResumeScheduleStatus status;

  /// Lessons behind or ahead; 0 when on schedule.
  final int lessons;

  /// "Op schema" / "2 lessen achter" / "1 les vooruit". A behind or ahead of
  /// zero lessons is on schedule, whatever the status says.
  String get label {
    final n = lessons;
    if (status == ResumeScheduleStatus.onSchedule || n <= 0) return 'Op schema';
    final unit = n == 1 ? 'les' : 'lessen';
    return status == ResumeScheduleStatus.behind ? '$n $unit achter' : '$n $unit vooruit';
  }

  bool get isBehind => status == ResumeScheduleStatus.behind && lessons > 0;

  static ResumeSchedule? fromJson(Object? json) {
    if (json is! Map) return null;
    final status = ResumeScheduleStatus.tryFromId(json['status']);
    if (status == null) return null;
    final lessons = _int(json['lessons']) ?? _int(json['days']) ?? 0;
    return ResumeSchedule(status: status, lessons: lessons < 0 ? 0 : lessons);
  }
}

class ResumeProgress {
  const ResumeProgress({required this.done, required this.total});

  final int done;
  final int total;

  double get fraction => total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);

  static ResumeProgress? fromJson(Object? json) {
    if (json is! Map) return null;
    final total = _int(json['total']) ?? 0;
    if (total <= 0) return null;
    final done = (_int(json['done']) ?? 0).clamp(0, total);
    return ResumeProgress(done: done, total: total);
  }
}

class ResumeItem {
  const ResumeItem({
    required this.kind,
    required this.title,
    required this.cta,
    required this.href,
    this.subtitle,
    this.studyId,
    this.lessonDay,
    this.step,
    this.progress,
    this.schedule,
    this.doneToday = false,
    this.nextLabel,
    this.imageUrl,
  });

  final ResumeKind kind;
  final String title;
  final String? subtitle;
  final String? studyId;
  final int? lessonDay;
  final ResumeStep? step;
  final ResumeProgress? progress;
  final ResumeSchedule? schedule;

  /// Today's lesson for this study is finished.
  final bool doneToday;

  /// Shown when [doneToday], e.g. "Morgen les 7".
  final String? nextLabel;

  /// Button text, e.g. "Verder met stap 3", "Verder lezen".
  final String cta;

  /// The website path; the app maps it with `resumeTargetFor`.
  final String href;

  final String? imageUrl;

  static String defaultCta(ResumeKind kind) => switch (kind) {
    ResumeKind.study => 'Verder met de les',
    ResumeKind.chapter => 'Verder lezen',
    ResumeKind.start => 'Begin met lezen',
    ResumeKind.other => 'Verder',
  };

  /// Null when the item has nothing to show (no title).
  static ResumeItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final title = _text(json['title']);
    if (title == null) return null;
    final kind = ResumeKind.fromId(json['kind']);
    final day = _int(json['lessonDay']);

    return ResumeItem(
      kind: kind,
      title: title,
      subtitle: _text(json['subtitle']),
      studyId: _text(json['studyId']),
      lessonDay: day != null && day >= 1 ? day : null,
      step: ResumeStep.fromJson(json['step']),
      progress: ResumeProgress.fromJson(json['progress']),
      schedule: ResumeSchedule.fromJson(json['schedule']),
      doneToday: json['doneToday'] == true,
      nextLabel: _text(json['nextLabel']),
      cta: _text(json['cta']) ?? defaultCta(kind),
      href: _text(json['href']) ?? '/dashboard',
      imageUrl: _text(json['imageUrl']),
    );
  }
}

class DashboardResume {
  const DashboardResume({required this.primary, this.others = const []});

  final ResumeItem primary;

  /// Other running studies, newest activity first, at most [maxOthers].
  final List<ResumeItem> others;

  static const maxOthers = 3;

  /// Null when [json] is absent (an older server) or its primary item is
  /// unusable; the caller then falls back to what the device knows.
  static DashboardResume? fromJson(Object? json) {
    if (json is! Map) return null;
    final primary = ResumeItem.fromJson(json['primary']);
    if (primary == null) return null;
    final rawOthers = json['others'];
    final others = rawOthers is List
        ? rawOthers
              .map(ResumeItem.fromJson)
              .whereType<ResumeItem>()
              .take(maxOthers)
              .toList(growable: false)
        : const <ResumeItem>[];
    return DashboardResume(primary: primary, others: others);
  }
}

int? _int(Object? value) {
  if (value is num && value.isFinite) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
