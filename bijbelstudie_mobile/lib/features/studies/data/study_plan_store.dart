import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How a study is configured and how far through it the reader is, kept on the
/// device.
///
/// The website keeps the same state in `sessionStorage` on `/studies`
/// (`saveAndNavigate` in `app/studies/page.tsx`), which is why closing the tab
/// there loses it. `POST /api/v1/study-progress` records completed lessons for
/// the account, but no endpoint stores a chosen translation, commentary or
/// cadence - so those live here, alongside a device-local copy of the completed
/// lessons that keeps a study usable while signed out or offline. The two are
/// merged for display; the server stays the record that crosses devices.
enum StudyCadence { daily, everyOtherDay, threePerWeek, weekly, ownPace }

extension StudyCadenceX on StudyCadence {
  String get id => switch (this) {
    StudyCadence.daily => 'daily',
    StudyCadence.everyOtherDay => 'everyOtherDay',
    StudyCadence.threePerWeek => 'threePerWeek',
    StudyCadence.weekly => 'weekly',
    StudyCadence.ownPace => 'ownPace',
  };

  String get label => switch (this) {
    StudyCadence.daily => 'Elke dag',
    StudyCadence.everyOtherDay => 'Om de dag',
    StudyCadence.threePerWeek => '3x per week',
    StudyCadence.weekly => '1x per week',
    StudyCadence.ownPace => 'In eigen tempo',
  };

  String get description => switch (this) {
    StudyCadence.daily => 'Elke dag een les.',
    StudyCadence.everyOtherDay => 'Om de dag een les.',
    StudyCadence.threePerWeek => 'Drie lessen per week.',
    StudyCadence.weekly => 'Een les per week.',
    StudyCadence.ownPace => 'Geen vast ritme, je gaat verder wanneer je wilt.',
  };

  /// Null for [StudyCadence.ownPace], the one choice that cannot be turned into
  /// a finish date.
  double? get lessonsPerWeek => switch (this) {
    StudyCadence.daily => 7,
    StudyCadence.everyOtherDay => 3.5,
    StudyCadence.threePerWeek => 3,
    StudyCadence.weekly => 1,
    StudyCadence.ownPace => null,
  };

  static StudyCadence fromId(String? id) => StudyCadence.values.firstWhere(
    (v) => v.id == id,
    orElse: () => StudyCadence.daily,
  );
}

class StudyPlan {
  const StudyPlan({
    required this.studyId,
    required this.versionId,
    required this.commentaryId,
    this.cadence = StudyCadence.daily,
    this.completedDays = const <int>{},
    this.startedAt,
  });

  final String studyId;
  final String versionId;
  final String commentaryId;
  final StudyCadence cadence;
  final Set<int> completedDays;

  /// Null until the reader presses Start, which is what separates a study they
  /// merely looked at from one they are working through.
  final DateTime? startedAt;

  bool get started => startedAt != null;

  StudyPlan copyWith({
    String? versionId,
    String? commentaryId,
    StudyCadence? cadence,
    Set<int>? completedDays,
    DateTime? startedAt,
    bool clearStartedAt = false,
  }) {
    return StudyPlan(
      studyId: studyId,
      versionId: versionId ?? this.versionId,
      commentaryId: commentaryId ?? this.commentaryId,
      cadence: cadence ?? this.cadence,
      completedDays: completedDays ?? this.completedDays,
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
    );
  }

  Map<String, dynamic> toJson() => {
    'studyId': studyId,
    'versionId': versionId,
    'commentaryId': commentaryId,
    'cadence': cadence.id,
    'completedDays': completedDays.toList()..sort(),
    'startedAt': startedAt?.millisecondsSinceEpoch,
  };

  static StudyPlan? fromJson(Map<String, dynamic> json) {
    final id = json['studyId'] as String?;
    if (id == null || id.isEmpty) return null;
    final startedAt = (json['startedAt'] as num?)?.toInt();
    return StudyPlan(
      studyId: id,
      versionId: json['versionId'] as String? ?? 'statenvertaling',
      commentaryId: json['commentaryId'] as String? ?? 'matthew_henry_nl',
      cadence: StudyCadenceX.fromId(json['cadence'] as String?),
      completedDays: (json['completedDays'] as List? ?? const [])
          .whereType<num>()
          .map((d) => d.toInt())
          .toSet(),
      startedAt: startedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(startedAt),
    );
  }
}

/// One key holding every plan, so a plan can be read back without first knowing
/// which studies exist.
const _kPlansKey = 'studies.plans';

final studyPlansProvider =
    NotifierProvider<StudyPlansController, Map<String, StudyPlan>>(
      StudyPlansController.new,
    );

class StudyPlansController extends Notifier<Map<String, StudyPlan>> {
  final Completer<void> _loaded = Completer<void>();

  /// Completes once the first read from disk is done, successfully or not.
  /// [build] returns an empty map and fills it a moment later, so anything that
  /// must not act on "no plan yet" awaits this instead of racing the notifier.
  Future<void> get loaded => _loaded.future;

  @override
  Map<String, StudyPlan> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPlansKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final plans = <String, StudyPlan>{};
        for (final entry in decoded.entries) {
          final value = entry.value;
          if (value is! Map<String, dynamic>) continue;
          final plan = StudyPlan.fromJson(value);
          if (plan != null) plans[entry.key] = plan;
        }
        state = plans;
      }
    } catch (_) {
      // No preferences plugin (tests, an unusual platform) or a corrupt blob:
      // start from nothing rather than block the screen. The completer must
      // still fire or every awaiting caller hangs forever.
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  Future<void> _persist(Map<String, StudyPlan> plans) async {
    state = plans;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kPlansKey,
        jsonEncode({for (final e in plans.entries) e.key: e.value.toJson()}),
      );
    } catch (_) {
      // The in-memory state still stands for the rest of this session.
    }
  }

  StudyPlan? planFor(String studyId) => state[studyId];

  /// Writes the configuration without starting the study, so the choices
  /// survive backing out of the detail screen.
  Future<void> saveConfig({
    required String studyId,
    required String versionId,
    required String commentaryId,
    required StudyCadence cadence,
  }) async {
    final existing = state[studyId];
    final next =
        existing?.copyWith(
          versionId: versionId,
          commentaryId: commentaryId,
          cadence: cadence,
        ) ??
        StudyPlan(
          studyId: studyId,
          versionId: versionId,
          commentaryId: commentaryId,
          cadence: cadence,
        );
    await _persist({...state, studyId: next});
  }

  /// Marks the study as under way. Picking a started study back up keeps the
  /// original date, so "bezig sinds" does not reset on every visit.
  Future<void> start({
    required String studyId,
    required String versionId,
    required String commentaryId,
    required StudyCadence cadence,
  }) async {
    final existing = state[studyId];
    final next = StudyPlan(
      studyId: studyId,
      versionId: versionId,
      commentaryId: commentaryId,
      cadence: cadence,
      completedDays: existing?.completedDays ?? const <int>{},
      startedAt: existing?.startedAt ?? DateTime.now(),
    );
    await _persist({...state, studyId: next});
  }

  Future<void> setLessonDone({
    required String studyId,
    required int day,
    required bool done,
    required String versionId,
    required String commentaryId,
    required StudyCadence cadence,
  }) async {
    final existing =
        state[studyId] ??
        StudyPlan(
          studyId: studyId,
          versionId: versionId,
          commentaryId: commentaryId,
          cadence: cadence,
          startedAt: DateTime.now(),
        );
    final days = {...existing.completedDays};
    if (done) {
      days.add(day);
    } else {
      days.remove(day);
    }
    await _persist({
      ...state,
      studyId: existing.copyWith(
        completedDays: days,
        startedAt: existing.startedAt ?? DateTime.now(),
      ),
    });
  }

  /// Clears progress but keeps the configuration: someone reading a study a
  /// second time rarely wants a different translation for it.
  Future<void> reset(String studyId) async {
    final existing = state[studyId];
    if (existing == null) return;
    await _persist({
      ...state,
      studyId: existing.copyWith(
        completedDays: const <int>{},
        clearStartedAt: true,
      ),
    });
  }
}
