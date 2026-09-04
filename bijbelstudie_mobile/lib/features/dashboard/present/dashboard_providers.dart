import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/provider_cache.dart';
import '../../../core/notifications/notification_copy.dart';
import '../../../core/notifications/notification_scheduler.dart';
import '../../../core/notifications/notification_service.dart' show NotifType;
import '../../../core/notifications/retention_store.dart';
import '../../studies/data/study_models.dart';
import '../../studies/data/study_plan_store.dart';
import '../../studies/present/studies_providers.dart';

import '../data/dashboard_models.dart';
import '../data/dashboard_repository.dart';

final dashboardProvider = FutureProvider.autoDispose<DashboardData>((ref) {
  ref.cacheFor();
  return ref.watch(dashboardRepositoryProvider).getDashboard();
});

/// What the quiet "vandaag nog niet gedaan" chip shows, or null when it should
/// stay hidden (`RETENTION_PLAN.md` §3.3): only when the reader has not studied
/// today, today *is* a cadence day, and the cadence is not `free`.
class HomeNudge {
  const HomeNudge({required this.message, required this.route});

  final String message;
  final String route;
}

final homeNudgeProvider = Provider.autoDispose<HomeNudge?>((ref) {
  final store = ref.watch(retentionStoreProvider);
  final storeCtl = ref.read(retentionStoreProvider.notifier);
  if (!store.loaded || storeCtl.studiedToday) return null;

  final enrollments = ref.watch(studyEnrollmentsProvider).value ?? const {};
  final plans = ref.watch(studyPlansProvider);
  final studies =
      ref.watch(curatedStudiesProvider).value ?? const <CuratedStudy>[];

  CadenceInfo? cadence;
  String? studyId;
  int resumeDay = 1;
  StudyCadence? localCadence;
  DateTime? startedAt;

  for (final e in enrollments.values) {
    if (e.isActive && !e.isCompleted) {
      cadence = cadenceFrom(
        rhythm: e.rhythm,
        reminderDays: e.reminderDays,
        startedAt: e.startedAt,
      );
      studyId = e.studyId;
      resumeDay = e.currentLessonDay;
      break;
    }
  }
  if (cadence == null) {
    for (final p in plans.values) {
      if (p.started) {
        localCadence = p.cadence;
        startedAt = p.startedAt;
        studyId = p.studyId;
      }
    }
    if (localCadence != null) {
      cadence = cadenceFrom(localCadence: localCadence, startedAt: startedAt);
    }
  }

  if (cadence == null || cadence.model == RetentionModel.none) return null;
  if (!cadence.isCadenceDay(DateTime.now())) return null;

  CuratedStudy? study;
  for (final s in studies) {
    if (s.id == studyId) {
      study = s;
      break;
    }
  }
  final variant = pickVariant(
    NotifType.studyReminder,
    rotation: DateTime.now().day,
    tokens: {
      'study': study?.title,
      'lesson': study?.lessonForDay(resumeDay)?.title,
    },
  );
  return HomeNudge(
    message: variant.title,
    route: studyId != null ? '/studie/$studyId/$resumeDay' : '/dashboard',
  );
});

/// The website recomputes its greeting every minute so it stays correct as the
/// clock rolls over; the app does the same on each build, which is cheaper and
/// just as accurate because the tab rebuilds on focus.
String greetingFor(String fullName, {DateTime? now}) {
  final firstName = fullName.trim().isEmpty
      ? 'Gebruiker'
      : fullName.trim().split(' ').first;
  final hour = (now ?? DateTime.now()).hour;

  if (hour < 6) return 'Goedenacht, $firstName';
  if (hour < 12) return 'Goedemorgen, $firstName';
  if (hour < 18) return 'Goedemiddag, $firstName';
  if (hour < 22) return 'Goedenavond, $firstName';
  return 'Goedenacht, $firstName';
}

const _weekdays = [
  'maandag',
  'dinsdag',
  'woensdag',
  'donderdag',
  'vrijdag',
  'zaterdag',
  'zondag',
];

const _months = [
  'januari',
  'februari',
  'maart',
  'april',
  'mei',
  'juni',
  'juli',
  'augustus',
  'september',
  'oktober',
  'november',
  'december',
];

/// `new Date().toLocaleDateString("nl-NL", { weekday, day, month })` — the
/// sub-line under the dashboard greeting. Written out rather than pulled from
/// `intl` so the app ships no extra locale data for one string.
String dutchLongDate([DateTime? now]) {
  final d = now ?? DateTime.now();
  return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}
