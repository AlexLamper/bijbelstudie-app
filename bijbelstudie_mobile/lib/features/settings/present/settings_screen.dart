import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/content_cache.dart';
import '../../../core/notifications/notification_scheduler.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../bible/present/bible_providers.dart';
import '../../bible/present/offline_library_sheet.dart';
import '../../notes/data/notes_repository.dart';
import '../../studies/present/studies_providers.dart';
import '../data/notification_prefs.dart';
import '../data/reading_settings.dart';
import 'theme_mode_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int? _cacheBytes;
  int _pendingChanges = 0;

  @override
  void initState() {
    super.initState();
    _refreshCacheSize();
  }

  Future<void> _refreshCacheSize() async {
    final cache = ref.read(contentCacheProvider);
    final bytes = await cache?.totalBytes();
    final pending = await cache?.pendingChangeCount();
    if (mounted) {
      setState(() {
        _cacheBytes = bytes ?? 0;
        _pendingChanges = pending ?? 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readingSettingsProvider);
    final controller = ref.read(readingSettingsProvider.notifier);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Instellingen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          const SectionHeader(eyebrow: 'Uiterlijk', title: 'Thema'),
          const SizedBox(height: 12),
          // Applies on the spot: main.dart watches the same stored value and
          // resolves AppTheme's brightness from it.
          _ThemeModeSwitcher(
            selected: settings.themeMode,
            onChanged: controller.setThemeMode,
          ),
          const SizedBox(height: 24),
          const SectionHeader(eyebrow: 'Lezen', title: 'Leesweergave'),
          const SizedBox(height: 12),
          _SamplePreview(settings: settings),
          const SizedBox(height: 16),
          _OptionRow<ReaderFontSize>(
            label: 'Tekstgrootte',
            values: ReaderFontSize.values,
            selected: settings.fontSize,
            labelOf: (v) => v.label,
            onChanged: controller.setFontSize,
          ),
          const SizedBox(height: 12),
          _OptionRow<ReaderLineHeight>(
            label: 'Regelafstand',
            values: ReaderLineHeight.values,
            selected: settings.lineHeight,
            labelOf: (v) => v.label,
            onChanged: controller.setLineHeight,
          ),
          const SizedBox(height: 12),
          _OptionRow<ReaderFontFamily>(
            label: 'Lettertype',
            values: ReaderFontFamily.values,
            selected: settings.fontFamily,
            labelOf: (v) => v.label,
            onChanged: controller.setFontFamily,
          ),
          const SizedBox(height: 12),
          _OptionRow<ReaderLetterSpacing>(
            label: 'Letterafstand',
            values: ReaderLetterSpacing.values,
            selected: settings.letterSpacing,
            labelOf: (v) => v.label,
            onChanged: controller.setLetterSpacing,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Versnummers tonen'),
            value: settings.showVerseNumbers,
            onChanged: controller.setShowVerseNumbers,
          ),

          const _NotificationsSection(),

          const SizedBox(height: 24),
          const SectionHeader(eyebrow: 'Offline', title: 'Opgeslagen tekst'),
          const SizedBox(height: 8),
          RuleGrid(
            children: [
              RuleListTile(
                showRule: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cache', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            _cacheBytes == null
                                ? 'Berekenen…'
                                : '${_formatBytes(_cacheBytes!)} opgeslagen',
                            style: AppTheme.bodyMuted.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        // Downloads are spared, which is what the paragraph
                        // below promises. Wiping them here would delete
                        // megabytes the reader deliberately fetched, without
                        // ever saying so.
                        await ref.read(contentCacheProvider)?.clear();
                        ref.invalidate(offlineBooksProvider);
                        await _refreshCacheSize();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Cache geleegd. Gedownloade boeken zijn bewaard.'),
                          ),
                        );
                      },
                      child: const Text('Cache legen'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Hoofdstukken die je leest worden opgeslagen zodat je ze offline kunt teruglezen. '
            'Boeken die je expliciet downloadt blijven bewaard; de rest wordt automatisch '
            'opgeruimd bij ${_formatBytes(ContentCache.defaultMaxBytes)}.',
            style: AppTheme.bodyMuted.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 16),
          // The same list as the reader's offline sheet, so the answer to
          // "what is actually on my phone, and how do I get that space back"
          // is in both places a reader would look for it.
          const OfflineBooksList(),

          if (_pendingChanges > 0) ...[
            const SizedBox(height: 20),
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$_pendingChanges wijziging${_pendingChanges == 1 ? '' : 'en'} wacht'
                      '${_pendingChanges == 1 ? '' : 'en'} op synchronisatie.',
                      style: AppTheme.bodyMuted.copyWith(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await ref.read(notesRepositoryProvider).flushPendingChanges();
                      await _refreshCacheSize();
                    },
                    child: const Text('Nu synchroniseren'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// OS-truth notification state for the master row - never taken from the stored
/// pref alone, so the switch cannot claim "on" after the OS revoked permission.
/// Extended from the old 1001..1014 check to any managed pending id.
final _notifStatusProvider = FutureProvider<ReminderStatus>((ref) async {
  return ref.watch(notificationServiceProvider).currentStatus();
});

String _fmtMinutes(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// The full notifications block (`RETENTION_PLAN.md` §6): a master switch, the
/// study-reminder time, per-type toggles, quiet hours, and a one-tap
/// "sla vandaag over". Full opt-out is a single tap on the master row - no
/// confirmation nag.
class _NotificationsSection extends ConsumerWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return const SizedBox.shrink();

    final statusAsync = ref.watch(_notifStatusProvider);
    final prefs = ref.watch(notificationPrefsProvider);
    final prefsCtl = ref.read(notificationPrefsProvider.notifier);

    return statusAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (status) {
        if (!status.available) return const SizedBox.shrink();
        final master = prefs.masterEnabled && status.permitted;

        final enrollments =
            ref.watch(studyEnrollmentsProvider).value ?? const {};
        final hasWeekGoal = enrollments.values.any((e) =>
            e.isActive &&
            !e.isCompleted &&
            cadenceFrom(rhythm: e.rhythm, reminderDays: e.reminderDays).model ==
                RetentionModel.weekGoal);

        void bump() => ref.invalidate(notificationRecomputeProvider);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            const SectionHeader(eyebrow: 'Meldingen', title: 'Herinneringen'),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Herinneringen'),
              subtitle: Text(
                status.permitted
                    ? 'Hooguit één per dag, op jouw moment.'
                    : 'Zet meldingen aan in de systeeminstellingen.',
                style: AppTheme.bodyMuted.copyWith(fontSize: 12),
              ),
              value: master,
              onChanged: (on) async {
                if (on) {
                  final granted = await ref
                      .read(notificationServiceProvider)
                      .requestPermission();
                  await prefsCtl.setMasterEnabled(granted);
                  if (!granted && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Meldingen staan uit. Zet ze aan in de systeeminstellingen.'),
                    ));
                  }
                } else {
                  await prefsCtl.setMasterEnabled(false);
                  await ref
                      .read(notificationServiceProvider)
                      .cancelAllManaged();
                }
                ref.invalidate(_notifStatusProvider);
                bump();
              },
            ),
            if (master) ...[
              _NotifTimeRow(
                title: 'Studieherinnering',
                enabled: prefs.studyReminderEnabled,
                minutes: prefs.studyReminderMinutes,
                onToggle: (v) async {
                  await prefsCtl.setStudyReminder(enabled: v);
                  bump();
                },
                onPickTime: (m) async {
                  await prefsCtl.setStudyReminder(minutes: m, enabled: true);
                  bump();
                },
              ),
              _NotifToggleRow(
                title: 'Reeks bijna kwijt',
                value: prefs.streakAtRiskEnabled,
                onChanged: (v) async {
                  await prefsCtl.setType('streakAtRisk', v);
                  bump();
                },
              ),
              _NotifToggleRow(
                title: 'Onafgemaakte les',
                value: prefs.lessonHalfwayEnabled,
                onChanged: (v) async {
                  await prefsCtl.setType('lessonHalfway', v);
                  bump();
                },
              ),
              if (hasWeekGoal)
                _NotifToggleRow(
                  title: 'Weekdoel',
                  value: prefs.weeklyGoalEnabled,
                  onChanged: (v) async {
                    await prefsCtl.setType('weeklyGoal', v);
                    bump();
                  },
                ),
              _NotifToggleRow(
                title: 'Mijlpalen',
                value: prefs.milestonesEnabled,
                onChanged: (v) async {
                  await prefsCtl.setType('milestone', v);
                  bump();
                },
              ),
              _NotifToggleRow(
                title: 'Weer welkom (afwezigheid)',
                value: prefs.dormantEnabled,
                onChanged: (v) async {
                  await prefsCtl.setType('dormant', v);
                  bump();
                },
              ),
              _NotifTimeRow(
                title: 'Vers van de dag',
                enabled: prefs.dailyVerseEnabled,
                minutes: prefs.dailyVerseMinutes,
                onToggle: (v) async {
                  await prefsCtl.setDailyVerse(enabled: v);
                  bump();
                },
                onPickTime: (m) async {
                  await prefsCtl.setDailyVerse(minutes: m, enabled: true);
                  bump();
                },
              ),
              _QuietHoursRow(
                startMinutes: prefs.quietStartMinutes,
                endMinutes: prefs.quietEndMinutes,
                onChanged: (s, e) async {
                  await prefsCtl.setQuietHours(startMinutes: s, endMinutes: e);
                  bump();
                },
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextButton(
                  onPressed: () async {
                    if (prefs.snoozedNow) {
                      await prefsCtl.clearSnooze();
                    } else {
                      await prefsCtl.snoozeToday();
                    }
                    bump();
                  },
                  child: Text(prefs.snoozedNow
                      ? 'Meldingen weer aanzetten voor vandaag'
                      : 'Sla vandaag over'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _NotifToggleRow extends StatelessWidget {
  const _NotifToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _NotifTimeRow extends StatelessWidget {
  const _NotifTimeRow({
    required this.title,
    required this.enabled,
    required this.minutes,
    required this.onToggle,
    required this.onPickTime,
  });

  final String title;
  final bool enabled;
  final int minutes;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onPickTime;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title),
      subtitle: Text(
        enabled ? 'Elke keer om ${_fmtMinutes(minutes)}' : 'Uit',
        style: AppTheme.bodyMuted.copyWith(fontSize: 12),
      ),
      value: enabled,
      onChanged: onToggle,
      secondary: enabled
          ? TextButton(
              onPressed: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime:
                      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
                );
                if (picked != null) onPickTime(picked.hour * 60 + picked.minute);
              },
              child: Text(_fmtMinutes(minutes)),
            )
          : null,
    );
  }
}

class _QuietHoursRow extends StatelessWidget {
  const _QuietHoursRow({
    required this.startMinutes,
    required this.endMinutes,
    required this.onChanged,
  });

  final int startMinutes;
  final int endMinutes;
  final void Function(int? start, int? end) onChanged;

  Future<void> _pick(BuildContext context, {required bool isStart}) async {
    final current = isStart ? startMinutes : endMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    final m = picked.hour * 60 + picked.minute;
    onChanged(isStart ? m : null, isStart ? null : m);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text('Stille uren',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          TextButton(
            onPressed: () => _pick(context, isStart: true),
            child: Text(_fmtMinutes(startMinutes)),
          ),
          Text('–', style: AppTheme.bodyMuted),
          TextButton(
            onPressed: () => _pick(context, isStart: false),
            child: Text(_fmtMinutes(endMinutes)),
          ),
        ],
      ),
    );
  }
}

class _SamplePreview extends StatelessWidget {
  const _SamplePreview({required this.settings});

  final ReadingSettings settings;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Text.rich(
        TextSpan(
          children: [
            if (settings.showVerseNumbers)
              TextSpan(
                text: '1 ',
                style: TextStyle(
                  fontFamily: AppTheme.sansFontName,
                  fontSize: settings.fontSize.points * 0.62,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.inkMuted,
                ),
              ),
            const TextSpan(text: 'In den beginne schiep God den hemel en de aarde.'),
          ],
        ),
        style: TextStyle(
          fontFamily: settings.fontFamily.fontName,
          fontSize: settings.fontSize.points,
          height: settings.lineHeight.factor,
          letterSpacing: settings.letterSpacing.points,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
    );
  }
}

class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.bodyMuted.copyWith(fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in values)
              ChoiceChip(
                label: Text(labelOf(value)),
                selected: value == selected,
                onSelected: (_) => onChanged(value),
              ),
          ],
        ),
      ],
    );
  }
}

/// A segmented Licht/Donker/Systeem switcher, shown at the top of Settings
/// so the dark-mode toggle isn't buried among the reading-preference rows.
class _ThemeModeSwitcher extends StatelessWidget {
  const _ThemeModeSwitcher({required this.selected, required this.onChanged});

  final ThemeMode selected;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ThemeMode>(
      segments: [
        for (final mode in ThemeModeLabelX.pickerOrder)
          ButtonSegment(value: mode, icon: Icon(mode.icon), label: Text(mode.label)),
      ],
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (values) => onChanged(values.first),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} kB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
