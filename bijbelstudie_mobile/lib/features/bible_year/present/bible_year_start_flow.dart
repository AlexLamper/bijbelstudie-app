import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../settings/data/notification_prefs.dart';
import '../data/bible_year_models.dart';
import '../data/bible_year_repository.dart';
import '../domain/bible_year_display.dart';
import 'bible_year_parts.dart';

/// What the start flow hands back: the body for the API, and the reminder
/// time the reader chose (null = "Geen herinnering": the plan is left out of
/// the morning notification; nothing else changes).
typedef BibleYearStartSubmit =
    Future<String?> Function(BibleYearStartBody body, int? reminderMinutes);

/// The start flow: duur -> volgorde -> startdatum -> herinneringstijd ->
/// bevestigen. The website's `BibleYearStart` plus one app-only step, the
/// reminder time, which is the morning notification ("Ochtend") and defaults
/// to its current time.
///
/// The body carries the device's time zone, so "vandaag" and every later day
/// are the reader's own days.
class BibleYearStartFlow extends ConsumerStatefulWidget {
  const BibleYearStartFlow({
    super.key,
    required this.onSubmit,
    this.catalogue = const [],
    this.tracks = const [],
    this.initialPlan,
    this.heading = 'Begin met Bijbel in een jaar',
    this.submitLabel = 'Begin met lezen',
    this.onCancel,
    this.today,
  });

  final BibleYearStartSubmit onSubmit;
  final List<BibleYearCatalogueEntry> catalogue;
  final List<BibleYearTrackEntry> tracks;
  final BibleYearPlanKey? initialPlan;
  final String heading;
  final String submitLabel;

  /// Shows "Annuleren" on the first step.
  final VoidCallback? onCancel;

  /// Overrides the device's date (tests).
  final String? today;

  @override
  ConsumerState<BibleYearStartFlow> createState() => _BibleYearStartFlowState();
}

const _steps = ['Duur', 'Volgorde', 'Startdatum', 'Herinnering', 'Bevestigen'];

class _BibleYearStartFlowState extends ConsumerState<BibleYearStartFlow> {
  int _step = 0;
  late BibleYearPlanKey _plan;
  late BibleYearTrackKey _track;
  StartDateChoice _dateChoice = StartDateChoice.vandaag;
  late String _today;
  late String _customDate;
  bool _remind = true;
  int? _reminderMinutes;
  bool _pending = false;
  String? _error;

  List<BibleYearCatalogueEntry> get _plans =>
      widget.catalogue.isNotEmpty ? widget.catalogue : kDefaultBibleYearCatalogue;
  List<BibleYearTrackEntry> get _orders =>
      widget.tracks.isNotEmpty ? widget.tracks : kDefaultBibleYearTracks;

  @override
  void initState() {
    super.initState();
    _today = widget.today ?? deviceToday();
    _customDate = _today;
    final wanted = widget.initialPlan ?? kDefaultBibleYearPlan;
    _plan = _plans.any((p) => p.planKey == wanted) ? wanted : _plans.first.planKey;
    _track = _orders.any((t) => t.track == kDefaultBibleYearTrack)
        ? kDefaultBibleYearTrack
        : _orders.first.track;
  }

  BibleYearCatalogueEntry get _planEntry =>
      _plans.firstWhere((p) => p.planKey == _plan, orElse: () => _plans.first);

  String get _startDate {
    if (_dateChoice == StartDateChoice.kies) return _customDate;
    for (final option in startDateOptions(_today)) {
      if (option.id == _dateChoice) return option.date ?? _today;
    }
    return _today;
  }

  /// The reader's current morning time, read once prefs are loaded.
  int _defaultReminder(NotificationPrefs prefs) => prefs.morningMinutes;

  Future<void> _pickDate() async {
    final parts = _customDate.split('-').map(int.parse).toList();
    final todayParts = _today.split('-').map(int.parse).toList();
    final first = DateTime(todayParts[0], todayParts[1], todayParts[2]);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(parts[0], parts[1], parts[2]),
      firstDate: first,
      lastDate: first.add(const Duration(days: kMaxStartDaysAhead)),
      helpText: 'Startdatum',
      cancelText: 'Annuleren',
      confirmText: 'Kiezen',
      fieldLabelText: 'Startdatum',
      errorFormatText: 'Kies een geldige datum.',
      errorInvalidText: 'Kies een datum binnen een jaar.',
    );
    if (picked != null && mounted) setState(() => _customDate = isoDate(picked));
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
        _reminderMinutes = picked.hour * 60 + picked.minute;
      });
    }
  }

  Future<void> _submit(int reminderMinutes) async {
    final startDate = _startDate;
    if (startDateError(startDate, _today) != null) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    final timeZone = await ref.read(bibleYearRepositoryProvider).deviceTimeZone();
    final error = await widget.onSubmit(
      BibleYearStartBody(planKey: _plan, track: _track, startDate: startDate, timeZone: timeZone),
      _remind ? reminderMinutes : null,
    );
    if (!mounted) return;
    setState(() {
      _pending = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final prefs = ref.watch(notificationPrefsProvider);
    final reminder = _reminderMinutes ?? _defaultReminder(prefs);

    final startDate = _startDate;
    final dateError = startDateError(startDate, _today);
    final endDate = dateError == null ? planEndDate(startDate, _planEntry.totalDays) : null;
    final last = _step == _steps.length - 1;
    final canContinue = _step != 2 || dateError == null;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BibleYearEyebrow('Stap ${_step + 1} van ${_steps.length} · ${_steps[_step]}'),
          const SizedBox(height: 4),
          Semantics(
            header: true,
            child: Text(widget.heading, style: AppTheme.displayTitle.copyWith(fontSize: 20)),
          ),
          const SizedBox(height: 16),
          ..._stepBody(reminder, dateError, startDate, endDate),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(_error!, style: AppTheme.caption.copyWith(fontSize: 13)),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              if (_step > 0)
                BibleYearSecondaryButton(
                  label: 'Terug',
                  height: 44,
                  onPressed: _pending ? null : () => setState(() => _step -= 1),
                )
              else if (widget.onCancel != null)
                BibleYearSecondaryButton(
                  label: 'Annuleren',
                  height: 44,
                  onPressed: _pending ? null : widget.onCancel,
                ),
              const Spacer(),
              if (last)
                BibleYearPrimaryButton(
                  label: _pending ? 'Bezig...' : widget.submitLabel,
                  height: 44,
                  onPressed: _pending || dateError != null ? null : () => _submit(reminder),
                )
              else
                BibleYearPrimaryButton(
                  label: 'Verder',
                  height: 44,
                  onPressed: canContinue ? () => setState(() => _step += 1) : null,
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _stepBody(int reminder, String? dateError, String startDate, String? endDate) {
    switch (_step) {
      case 0:
        return [
          _Options(
            label: 'Hoe lang wil je erover doen?',
            children: [
              for (final entry in _plans)
                _Option(
                  selected: _plan == entry.planKey,
                  onSelect: () => setState(() => _plan = entry.planKey),
                  title: entry.label,
                  detail: '${entry.totalDays} dagen, ongeveer ${entry.minutesPerDay} minuten per dag',
                ),
            ],
          ),
        ];
      case 1:
        return [
          _Options(
            label: 'In welke volgorde wil je lezen?',
            children: [
              for (final entry in _orders)
                _Option(
                  selected: _track == entry.track,
                  onSelect: () => setState(() => _track = entry.track),
                  title: entry.track == kDefaultBibleYearTrack
                      ? '${entry.label} (aanbevolen)'
                      : entry.label,
                  detail: entry.description,
                ),
            ],
          ),
        ];
      case 2:
        return [
          _Options(
            label: 'Wanneer wil je beginnen?',
            children: [
              for (final option in startDateOptions(_today))
                _Option(
                  selected: _dateChoice == option.id,
                  onSelect: () {
                    setState(() => _dateChoice = option.id);
                    if (option.id == StartDateChoice.kies) _pickDate();
                  },
                  title: option.label,
                  detail: option.date != null
                      ? formatDutchDate(option.date!, weekday: true, year: true)
                      : _dateChoice == StartDateChoice.kies
                      ? formatDutchDate(_customDate, weekday: true, year: true)
                      : 'Vandaag of later',
                ),
            ],
          ),
          if (_dateChoice == StartDateChoice.kies) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: BibleYearSecondaryButton(
                label: 'Andere datum kiezen',
                height: 40,
                onPressed: _pickDate,
              ),
            ),
            if (dateError != null) ...[
              const SizedBox(height: 6),
              Text(dateError, style: AppTheme.caption.copyWith(fontSize: 12.5)),
            ],
          ],
        ];
      case 3:
        return [
          _Options(
            label: 'Wanneer wil je eraan herinnerd worden?',
            children: [
              _Option(
                selected: _remind,
                onSelect: () => setState(() => _remind = true),
                title: 'Elke dag om ${formatClock(reminder)}',
                detail: 'In je ochtendmelding, op dezelfde tijd. Je kunt die hier wijzigen.',
              ),
              _Option(
                selected: !_remind,
                onSelect: () => setState(() => _remind = false),
                title: 'Geen herinnering',
                detail: 'Je leesplan komt niet in je ochtendmelding. Aan te passen bij Instellingen.',
              ),
            ],
          ),
          if (_remind) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: BibleYearSecondaryButton(
                label: 'Tijd wijzigen',
                height: 40,
                onPressed: () => _pickTime(reminder),
              ),
            ),
          ],
        ];
      default:
        return [
          _Summary(
            rows: [
              ('Duur', '${_planEntry.label} · ongeveer ${_planEntry.minutesPerDay} min per dag'),
              ('Volgorde', trackLabel(_track, _orders)),
              ('Begint', formatDutchDate(startDate, weekday: true, year: true)),
              if (endDate != null) ('Klaar op', formatDutchDate(endDate)),
              ('Herinnering', _remind ? 'Elke dag om ${formatClock(reminder)}' : 'Geen'),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Hoofdstukken die je in de Bijbel leest, worden vanzelf afgevinkt. Loop je achter, dan kun je bijlezen of je schema opschuiven. Er is geen deadline.',
            style: AppTheme.caption.copyWith(fontSize: 13, height: 1.6),
          ),
        ];
    }
  }
}

class _Options extends StatelessWidget {
  const _Options({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppTheme.bodyStrong),
        const SizedBox(height: 10),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          children[i],
        ],
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.selected,
    required this.onSelect,
    required this.title,
    required this.detail,
  });

  final bool selected;
  final VoidCallback onSelect;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: selected ? AppTheme.teal : AppTheme.rule, width: selected ? 1.5 : 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppTheme.teal : Colors.transparent,
                    border: Border.all(color: selected ? AppTheme.teal : AppTheme.ruleStrong),
                  ),
                  child: selected ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTheme.displayBase.copyWith(fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text(detail, style: AppTheme.caption.copyWith(fontSize: 13, height: 1.5)),
                    ],
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

class _Summary extends StatelessWidget {
  const _Summary({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(label, style: AppTheme.bodyMuted),
                ),
                Expanded(child: Text(value, style: AppTheme.bodyStrong)),
              ],
            ),
          ),
      ],
    );
  }
}
