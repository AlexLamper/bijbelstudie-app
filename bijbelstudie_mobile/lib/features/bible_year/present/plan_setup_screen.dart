import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/notification_scheduler.dart';
import '../../../core/notifications/permission_moment.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/primary_button.dart';
import '../../../core/ui/segmented_track.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/timed_snack_bar.dart';
import '../../settings/data/notification_prefs.dart';
import '../data/bible_year_models.dart';
import '../data/bible_year_repository.dart';
import '../domain/bible_year_display.dart';
import 'bible_year_providers.dart';
import 'plan_widgets.dart';

/// Extra minutes a 'studeren' day takes over 'lezen': the uitleg and the vraag.
const int kStudyExtraMinutes = 10;

const _stepNames = ['Manier', 'Duur', 'Volgorde', 'Herinnering'];

/// Leesplan instellen: 4 steps (Manier, Duur, Volgorde, Herinnering). Full screen.
///
/// New plans POST start; the gear ([edit]) is prefilled from the running plan
/// and saves with PATCH update, which keeps the chapters already read. The
/// reminder rides the morning notification, as in the old start flow.
class PlanSetupScreen extends ConsumerStatefulWidget {
  const PlanSetupScreen({super.key, this.edit = false, this.initialPlan, this.today});

  /// The gear: prefilled from the running plan, saves with PATCH update.
  final bool edit;
  final BibleYearPlanKey? initialPlan;

  /// Overrides the device's date (tests).
  final String? today;

  @override
  ConsumerState<PlanSetupScreen> createState() => _PlanSetupScreenState();
}

class _PlanSetupScreenState extends ConsumerState<PlanSetupScreen> {
  int _step = 0;
  BibleYearMode _mode = BibleYearMode.lezen;
  late BibleYearPlanKey _plan;
  BibleYearTrackKey _track = kDefaultBibleYearTrack;
  StartDateChoice _dateChoice = StartDateChoice.vandaag;
  late final String _today;
  String? _customDate;

  /// Null until the reader touches it: then the prefs decide.
  bool? _remind;
  int? _reminderMinutes;
  bool _reminderTouched = false;

  bool _prefilled = false;
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _today = widget.today ?? deviceToday();
    _plan = widget.initialPlan ?? kDefaultBibleYearPlan;
  }

  /* ── Derived values ─────────────────────────────────────────────────── */

  /// The coming 1 January (today when it is 1 January): a fresh start at
  /// new year, never a start in the past with months of days open.
  String get _newYear {
    final year = int.parse(_today.substring(0, 4));
    return _today.endsWith('-01-01') ? _today : '${year + 1}-01-01';
  }

  String get _startDate => switch (_dateChoice) {
    StartDateChoice.vandaag => _today,
    StartDateChoice.nieuwjaar => _newYear,
    StartDateChoice.kies => _customDate ?? _today,
  };

  BibleYearCatalogueEntry _entryFor(List<BibleYearCatalogueEntry> catalogue, BibleYearPlanKey key) {
    for (final entry in [...catalogue, ...kDefaultBibleYearCatalogue]) {
      if (entry.planKey == key) return entry;
    }
    return kDefaultBibleYearCatalogue.first;
  }

  int _minutes(BibleYearCatalogueEntry entry, BibleYearMode mode) =>
      entry.minutesPerDay + (mode == BibleYearMode.studeren ? kStudyExtraMinutes : 0);

  /// The server takes a start up to a year either side of today. The running
  /// plan's own start date always stands, however long ago it was.
  String? _startError(String date, BibleYearEnrollment? editing) {
    if (!isIsoDate(date)) return 'Kies een geldige datum.';
    if (editing != null && date == editing.startDate) return null;
    if (daysBetween(_today, date).abs() > kMaxStartDaysAhead) {
      return 'Kies een datum binnen een jaar van vandaag.';
    }
    return null;
  }

  String _endDate(String start, int totalDays, BibleYearEnrollment? editing) {
    // A schedule moved by "opschuiven" keeps its shift while the start stands.
    final shift = editing != null && start == editing.startDate ? editing.shiftDays : 0;
    return planEndDate(start, totalDays, shift);
  }

  void _prefill(BibleYearEnrollment enrollment) {
    _prefilled = true;
    _mode = enrollment.mode;
    _plan = enrollment.planKey;
    _track = enrollment.track;
    if (enrollment.startDate == _today) {
      _dateChoice = StartDateChoice.vandaag;
    } else if (enrollment.startDate == _newYear) {
      _dateChoice = StartDateChoice.nieuwjaar;
    } else {
      _dateChoice = StartDateChoice.kies;
      _customDate = enrollment.startDate;
    }
  }

  /* ── Actions ────────────────────────────────────────────────────────── */

  DateTime _local(String iso) {
    final p = iso.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  Future<void> _pickDate() async {
    final today = _local(_today);
    final current = _local(_startDate);
    var first = today.subtract(const Duration(days: kMaxStartDaysAhead));
    var last = today.add(const Duration(days: kMaxStartDaysAhead));
    if (current.isBefore(first)) first = current;
    if (current.isAfter(last)) last = current;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: first,
      lastDate: last,
      helpText: 'Startdatum',
      cancelText: 'Annuleren',
      confirmText: 'Kiezen',
      fieldLabelText: 'Startdatum',
      errorFormatText: 'Kies een geldige datum.',
      errorInvalidText: 'Kies een datum binnen een jaar.',
    );
    if (picked != null && mounted) {
      setState(() {
        _customDate = isoDate(picked);
        _dateChoice = StartDateChoice.kies;
      });
    }
  }

  Future<void> _pickTime(int minutes) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      helpText: 'Herinneringstijd',
      cancelText: 'Annuleren',
      confirmText: 'Kiezen',
    );
    if (picked != null && mounted) {
      setState(() {
        _remind = true;
        _reminderTouched = true;
        _reminderMinutes = picked.hour * 60 + picked.minute;
      });
    }
  }

  /// Same as the old start flow: a time is the morning time and switches the
  /// plan's content on; off ([minutes] null) only takes the plan out of the
  /// morning notification. A reminder without OS permission goes through the
  /// permission sheet, like every other ask.
  Future<void> _saveReminder(int? minutes) async {
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

  Future<void> _submit({
    required BibleYearEnrollment? editing,
    required bool remind,
    required int reminderMinutes,
  }) async {
    if (_pending) return;
    setState(() => _pending = true);
    final repository = ref.read(bibleYearRepositoryProvider);
    final controller = ref.read(bibleYearProvider.notifier);
    final timeZone = await repository.deviceTimeZone();
    final body = BibleYearStartBody(
      planKey: _plan,
      track: _track,
      mode: _mode,
      startDate: _startDate,
      timeZone: timeZone,
    );
    final error = editing != null
        ? await controller.updateSettings(body)
        : await controller.start(body);
    if (!mounted) return;
    if (error != null) {
      setState(() => _pending = false);
      _showError(error);
      return;
    }
    if (editing == null || _reminderTouched) {
      await _saveReminder(remind ? reminderMinutes : null);
    }
    if (!mounted) return;
    if (editing != null) {
      _close(fallback: PlanRoutes.plan);
    } else {
      context.go(PlanRoutes.plan);
    }
  }

  bool get _signedOut {
    final error = ref.read(bibleYearProvider).error;
    return error is BibleYearException && error.isUnauthorized;
  }

  void _showError(String message) {
    final messenger = ScaffoldMessenger.of(context);
    if (_signedOut) {
      showTimedSnackBar(
        messenger,
        SnackBar(
          content: Text(message),
          duration: kActionSnackBarDuration,
          action: SnackBarAction(label: 'Inloggen', onPressed: () => context.go('/login')),
        ),
      );
    } else {
      showTimedSnackBar(messenger, SnackBar(content: Text(message)));
    }
  }

  void _close({String fallback = '/dashboard'}) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(fallback);
    }
  }

  void _back() {
    if (_step > 0 && !_pending) setState(() => _step -= 1);
  }

  /* ── Build ──────────────────────────────────────────────────────────── */

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final async = ref.watch(bibleYearProvider);
    final prefs = ref.watch(notificationPrefsProvider);
    final data = async.value;
    final enrollment = data?.enrollment;
    final editing = widget.edit && enrollment != null && enrollment.isActive ? enrollment : null;
    if (editing != null && !_prefilled) _prefill(editing);

    // The gear waits for the running plan; a new plan never has to.
    final waiting = widget.edit && data == null;
    final catalogue = data?.catalogue ?? const <BibleYearCatalogueEntry>[];
    final entry = _entryFor(catalogue, _plan);
    final remind = _remind ?? (editing != null ? prefs.planEnabled && prefs.masterEnabled : true);
    final reminderMinutes = _reminderMinutes ?? prefs.morningMinutes;
    final startDate = _startDate;
    final dateError = _startError(startDate, editing);
    final last = _step == _stepNames.length - 1;

    final String label;
    if (last) {
      label = editing != null ? 'Opslaan' : 'Start leesplan';
    } else {
      label = 'Verder naar ${_stepNames[_step + 1].toLowerCase()}';
    }
    final VoidCallback? onPressed;
    if (waiting || (dateError != null && _step >= 1)) {
      onPressed = null;
    } else if (last) {
      onPressed = () => _submit(editing: editing, remind: remind, reminderMinutes: reminderMinutes);
    } else {
      onPressed = () => setState(() => _step += 1);
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlayStyle,
      child: PopScope(
        canPop: _step == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          backgroundColor: AppTheme.canvas,
          body: Column(
            children: [
              _Header(
                step: _step,
                title: 'Leesplan instellen',
                onClose: _pending ? null : _close,
                onBack: _step > 0 && !_pending ? _back : null,
              ),
              Expanded(
                child: ListView(
                  key: ValueKey('plan-setup-step-$_step'),
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 28),
                  children: waiting
                      ? _waitingBody(async)
                      : _stepBody(
                          catalogue: catalogue,
                          entry: entry,
                          editing: editing,
                          startDate: startDate,
                          dateError: dateError,
                          remind: remind,
                          reminderMinutes: reminderMinutes,
                        ),
                ),
              ),
              _Footer(
                child: PrimaryButton(text: label, isLoading: _pending, onPressed: onPressed),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _waitingBody(AsyncValue<BibleYearState> async) {
    final error = async.error;
    if (error == null) {
      return [Semantics(label: 'Leesplan laden', child: const SkeletonCardColumn(count: 2))];
    }
    final signedOut = error is BibleYearException && error.isUnauthorized;
    return [
      AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              signedOut
                  ? 'Log opnieuw in om je leesplan te zien.'
                  : error is BibleYearException
                  ? error.message
                  : 'Je leesplan kon niet worden geladen.',
              style: AppTheme.bodyMuted,
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              text: signedOut ? 'Inloggen' : 'Opnieuw proberen',
              height: 44,
              isSecondary: true,
              onPressed: signedOut
                  ? () => context.go('/login')
                  : () => ref.invalidate(bibleYearProvider),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _stepBody({
    required List<BibleYearCatalogueEntry> catalogue,
    required BibleYearCatalogueEntry entry,
    required BibleYearEnrollment? editing,
    required String startDate,
    required String? dateError,
    required bool remind,
    required int reminderMinutes,
  }) {
    switch (_step) {
      case 0:
        final lezen = _minutes(entry, BibleYearMode.lezen);
        final studeren = _minutes(entry, BibleYearMode.studeren);
        final study = _mode == BibleYearMode.studeren;
        return [
          const _StepTitle(
            title: 'Wil je lezen of studeren?',
            lead: 'Kies hoeveel tijd je elke dag wilt nemen.',
          ),
          _TileRow(
            children: [
              _ChoiceTile(
                vertical: true,
                icon: Icons.menu_book_outlined,
                title: 'Lezen',
                subtitle: '± $lezen min per dag',
                selected: !study,
                onTap: () => setState(() => _mode = BibleYearMode.lezen),
              ),
              _ChoiceTile(
                vertical: true,
                icon: Icons.school_outlined,
                title: 'Studeren',
                subtitle: '± $studeren min per dag',
                selected: study,
                onTap: () => setState(() => _mode = BibleYearMode.studeren),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoCard(
            title: study ? 'Een dag met Studeren' : 'Een dag met Lezen',
            rows: [
              _InfoRow(
                icon: Icons.menu_book_outlined,
                title: 'Lezing',
                text: 'De hoofdstukken van die dag, ± $lezen min.',
              ),
              if (study) ...const [
                _InfoRow(
                  icon: Icons.lightbulb_outline,
                  title: 'Uitleg',
                  text: 'Een korte uitleg (Matthew Henry) bij een van de hoofdstukken.',
                ),
                _InfoRow(
                  icon: Icons.chat_bubble_outline,
                  title: 'Vraag',
                  text: 'Eén vraag om over na te denken.',
                ),
              ],
            ],
            footnote: study ? null : 'Met Studeren komt er elke dag een korte uitleg en een vraag bij.',
          ),
        ];
      case 1:
        final options = [
          for (final key in BibleYearPlanKey.values) _entryFor(catalogue, key),
        ];
        final past = dateError == null && startDate.compareTo(_today) < 0;
        return [
          const _StepTitle(
            title: 'Hoe lang wil je erover doen?',
            lead: 'Hetzelfde plan, verdeeld over één of twee jaar.',
          ),
          _TileRow(
            children: [
              for (final option in options)
                _ChoiceTile(
                  vertical: true,
                  icon: option.planKey == BibleYearPlanKey.jaar1
                      ? Icons.calendar_today_outlined
                      : Icons.date_range_outlined,
                  title: option.label,
                  subtitle: '± ${_minutes(option, _mode)} min per dag',
                  detail: dateError == null
                      ? 'eindigt op ${formatDutchDate(_endDate(startDate, option.totalDays, editing))}'
                      : null,
                  selected: _plan == option.planKey,
                  onTap: () => setState(() => _plan = option.planKey),
                ),
            ],
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Startdatum', style: AppTheme.bodyStrong),
                const SizedBox(height: 10),
                SegmentedTrack(
                  segments: const [
                    SegmentedTrackSegment(label: 'Vandaag'),
                    SegmentedTrackSegment(label: '1 januari'),
                    SegmentedTrackSegment(label: 'Kies datum'),
                  ],
                  selectedIndex: _dateChoice.index,
                  onChanged: (index) {
                    final choice = StartDateChoice.values[index];
                    if (choice == StartDateChoice.kies) {
                      _pickDate();
                    } else {
                      setState(() => _dateChoice = choice);
                    }
                  },
                ),
                const SizedBox(height: 12),
                if (dateError != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(dateError, style: AppTheme.caption.copyWith(fontSize: 13)),
                  )
                else ...[
                  Text(
                    'Je begint op ${formatDutchDate(startDate, weekday: true, year: true)} en '
                    'eindigt op ${formatDutchDate(_endDate(startDate, entry.totalDays, editing))}.',
                    style: AppTheme.bodyMuted.copyWith(fontSize: 13.5, height: 1.5),
                  ),
                  if (past && (editing == null || startDate != editing.startDate)) ...[
                    const SizedBox(height: 6),
                    Text(
                      'De dagen voor vandaag staan dan open. Je kunt ze inhalen of opschuiven.',
                      style: AppTheme.caption.copyWith(fontSize: 12.5, height: 1.5),
                    ),
                  ],
                ],
              ],
            ),
          ),
          if (editing != null) const _EditNote(),
        ];
      case 2:
        return [
          const _StepTitle(
            title: 'In welke volgorde wil je lezen?',
            lead: 'In alle drie lees je de hele Bijbel.',
          ),
          for (final track in BibleYearTrackKey.values) ...[
            if (track != BibleYearTrackKey.values.first) const SizedBox(height: 10),
            _ChoiceTile(
              icon: _trackIcon(track),
              title: _trackTitle(track),
              subtitle: _trackSubtitle(track),
              selected: _track == track,
              onTap: () => setState(() => _track = track),
              extra: _track == track ? _DayOneExample(text: _dayOne(track, editing)) : null,
            ),
          ],
          const SizedBox(height: 16),
          _InfoCard(title: _trackTitle(_track), body: _trackDescription(_track)),
          if (editing != null) const _EditNote(),
        ];
      default:
        final entryMinutes = _minutes(entry, _mode);
        final endDate = dateError == null ? _endDate(startDate, entry.totalDays, editing) : null;
        return [
          const _StepTitle(
            title: 'Wil je een herinnering?',
            lead: 'Elke dag een melding op het moment dat jij kiest.',
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingRow(
                  icon: Icons.notifications_none_outlined,
                  title: 'Dagelijkse herinnering',
                  subtitle: 'In je ochtendmelding',
                  onTap: () => setState(() {
                    _remind = !remind;
                    _reminderTouched = true;
                  }),
                  trailing: Switch(
                    value: remind,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (value) => setState(() {
                      _remind = value;
                      _reminderTouched = true;
                    }),
                  ),
                ),
                if (remind) ...[
                  Divider(height: 1, thickness: 1, color: AppTheme.rule),
                  _SettingRow(
                    icon: Icons.schedule,
                    title: 'Tijd',
                    subtitle: 'Ook de tijd van je ochtendmelding',
                    onTap: () => _pickTime(reminderMinutes),
                    trailing: Text(
                      formatClock(reminderMinutes),
                      style: AppTheme.bodyStrong.copyWith(color: AppTheme.teal, fontSize: 15),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SummaryCard(
            rows: [
              ('Manier', '${_modeLabel(_mode)} · ± $entryMinutes min per dag'),
              ('Duur', '${entry.label} (${entry.totalDays} dagen)'),
              ('Volgorde', _trackTitle(_track)),
              ('Start', formatDutchDate(startDate, weekday: true, year: true)),
              ('Herinnering', remind ? 'Elke dag om ${formatClock(reminderMinutes)}' : 'Uit'),
            ],
            endDate: endDate,
          ),
        ];
    }
  }

  /// Day 1 of the chosen plan and order, from the real schedule; a static
  /// line while it loads (or when it cannot).
  String _dayOne(BibleYearTrackKey track, BibleYearEnrollment? editing) {
    final day = ref.watch(bibleYearDayPreviewProvider((plan: _plan, track: track, day: 1))).value;
    if (day != null && day.portions.isNotEmpty) {
      return day.portions.map((p) => p.label).join(', ');
    }
    return switch (track) {
      BibleYearTrackKey.gemengd => 'Genesis 1-3, Mattheüs 1, Psalm 1',
      BibleYearTrackKey.canoniek => 'Genesis 1-4',
      BibleYearTrackKey.chronologisch => 'Genesis 1-3',
    };
  }
}

String _modeLabel(BibleYearMode mode) => mode == BibleYearMode.studeren ? 'Studeren' : 'Lezen';

String _trackTitle(BibleYearTrackKey track) => switch (track) {
  BibleYearTrackKey.gemengd => 'Gemengd',
  BibleYearTrackKey.canoniek => 'Van begin tot eind',
  BibleYearTrackKey.chronologisch => 'Chronologisch',
};

String _trackSubtitle(BibleYearTrackKey track) => switch (track) {
  BibleYearTrackKey.gemengd => 'Oude Testament, Nieuwe Testament en een psalm',
  BibleYearTrackKey.canoniek => 'Van Genesis tot Openbaring',
  BibleYearTrackKey.chronologisch => 'In de volgorde waarin het gebeurde',
};

String _trackDescription(BibleYearTrackKey track) => switch (track) {
  BibleYearTrackKey.gemengd =>
    'Elke dag een stuk uit het Oude Testament, uit het Nieuwe Testament en uit Psalmen of '
        'Spreuken. Alle drie zijn ze op de laatste dag klaar.',
  BibleYearTrackKey.canoniek =>
    'De Bijbel in de volgorde van de boeken, van het eerste hoofdstuk tot het laatste.',
  BibleYearTrackKey.chronologisch =>
    'De gebeurtenissen in de volgorde waarin ze plaatsvonden. Profeten en psalmen staan '
        'bij de geschiedenis waar ze bij horen.',
};

IconData _trackIcon(BibleYearTrackKey track) => switch (track) {
  BibleYearTrackKey.gemengd => Icons.shuffle,
  BibleYearTrackKey.canoniek => Icons.format_list_numbered,
  BibleYearTrackKey.chronologisch => Icons.history,
};

/* ── Parts ─────────────────────────────────────────────────────────────── */

/// White bar from the status bar down: close (and back from step 2), the
/// centred title, and the four named steps.
class _Header extends StatelessWidget {
  const _Header({required this.step, required this.title, this.onClose, this.onBack});

  final int step;
  final String title;
  final VoidCallback? onClose;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.rule)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 52,
            child: Stack(
              children: [
                Center(
                  child: Semantics(
                    header: true,
                    child: Text(title, style: AppTheme.displayTitle.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ),
                Positioned(
                  left: 4,
                  top: 4,
                  bottom: 4,
                  child: Row(
                    children: [
                      _BarButton(icon: Icons.close, label: 'Sluiten', onTap: onClose),
                      if (step > 0)
                        _BarButton(icon: Icons.arrow_back, label: 'Terug', onTap: onBack),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
            child: _StepIndicator(step: step),
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 22, color: AppTheme.inkSoft),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Stap ${step + 1} van ${_stepNames.length}: ${_stepNames[step]}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < _stepNames.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= step ? AppTheme.teal : AppTheme.rule,
                        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${i + 1} ${_stepNames[i]}',
                        maxLines: 1,
                        style: AppTheme.caption.copyWith(
                          fontSize: 12,
                          color: i == step ? AppTheme.teal : AppTheme.inkMuted,
                          fontWeight: i == step ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.rule)),
      ),
      child: child,
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.title, required this.lead});

  final String title;
  final String lead;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: AppTheme.screenTitle.copyWith(fontSize: 24, height: 1.25)),
          ),
          const SizedBox(height: 6),
          Text(lead, style: AppTheme.bodyMuted),
        ],
      ),
    );
  }
}

/// Two tiles side by side, equally tall.
class _TileRow extends StatelessWidget {
  const _TileRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// A choice: icon in a rounded square, name, subline. Chosen = accent border,
/// light accent tint and a check top right.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.detail,
    this.extra,
    this.vertical = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  /// Shown under the text (the "Dag 1" example).
  final Widget? extra;

  /// Icon above the text, for tiles side by side.
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    final iconBox = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: selected ? AppTheme.surface : AppTheme.paper,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Icon(icon, size: 22, color: selected ? AppTheme.teal : AppTheme.inkSoft),
    );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppTheme.displayBase.copyWith(fontSize: 15.5)),
        const SizedBox(height: 2),
        Text(subtitle, style: AppTheme.caption.copyWith(fontSize: 13, height: 1.4, color: AppTheme.inkSoft)),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(detail!, style: AppTheme.caption.copyWith(fontSize: 12.5, height: 1.4)),
        ],
      ],
    );
    final content = vertical
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [iconBox, const SizedBox(height: 12), texts],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              iconBox,
              const SizedBox(width: 12),
              Expanded(child: texts),
              const SizedBox(width: 24),
            ],
          );

    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: Material(
        color: selected ? AppTheme.tealTint : AppTheme.surface,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected ? AppTheme.teal : AppTheme.rule,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    content,
                    if (extra != null) ...[const SizedBox(height: 12), extra!],
                  ],
                ),
                if (selected)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(color: AppTheme.teal, shape: BoxShape.circle),
                      child: const Icon(Icons.check, size: 14, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayOneExample extends StatelessWidget {
  const _DayOneExample({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dag 1', style: AppTheme.metaLabel.copyWith(color: AppTheme.teal)),
          const SizedBox(height: 3),
          Text(text, style: AppTheme.bodyStrong.copyWith(fontSize: 13.5)),
        ],
      ),
    );
  }
}

class _InfoRow {
  const _InfoRow({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;
}

/// What the choice means: a title, then rows (icon, name, line) or a body.
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, this.rows = const [], this.body, this.footnote});

  final String title;
  final List<_InfoRow> rows;
  final String? body;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTheme.bodyStrong),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!, style: AppTheme.bodyMuted.copyWith(fontSize: 13.5, height: 1.5)),
          ],
          for (final row in rows) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.tealTint,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Icon(row.icon, size: 18, color: AppTheme.teal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.title, style: AppTheme.bodyStrong.copyWith(fontSize: 13.5)),
                      const SizedBox(height: 1),
                      Text(row.text, style: AppTheme.caption.copyWith(fontSize: 13, height: 1.45)),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (footnote != null) ...[
            const SizedBox(height: 12),
            Text(footnote!, style: AppTheme.caption.copyWith(fontSize: 12.5, height: 1.45)),
          ],
        ],
      ),
    );
  }
}

class _EditNote extends StatelessWidget {
  const _EditNote();

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: AppTheme.inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Je gelezen hoofdstukken blijven staan.',
              style: AppTheme.caption.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row in the reminder card: icon, title over a subline, and a trailing
/// control. The whole row is the tap target.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.inkSoft),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTheme.bodyStrong),
                    const SizedBox(height: 1),
                    Text(subtitle, style: AppTheme.caption.copyWith(fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.rows, this.endDate});

  final List<(String, String)> rows;
  final String? endDate;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Je leesplan', style: AppTheme.bodyStrong),
          const SizedBox(height: 8),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 104, child: Text(label, style: AppTheme.bodyMuted)),
                  Expanded(child: Text(value, style: AppTheme.bodyStrong)),
                ],
              ),
            ),
          if (endDate != null) ...[
            const SizedBox(height: 8),
            Divider(height: 1, thickness: 1, color: AppTheme.rule),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.flag_outlined, size: 18, color: AppTheme.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Je hebt de hele Bijbel uit op ${formatDutchDate(endDate!)}.',
                    style: AppTheme.bodyStrong.copyWith(color: AppTheme.teal),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
