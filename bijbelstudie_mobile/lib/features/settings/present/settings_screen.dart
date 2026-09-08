import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/db/content_cache.dart';
import '../../../core/notifications/notification_scheduler.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../bible/present/bible_providers.dart';
import '../../bible/present/offline_library_sheet.dart';
import '../../levensboom/present/levensboom_providers.dart';
import '../../levensboom/present/studio/levensboom_studio_screen.dart' show publicProfileUrl;
import '../../notes/data/notes_repository.dart';
import '../../studies/present/studies_providers.dart';
import '../data/notification_prefs.dart';
import '../data/reading_settings.dart';
import 'theme_mode_provider.dart';

/// Settings, as one ruled list: titled groups divided by full-bleed rules, each
/// a run of [_SettingsRow]s - label left, value / switch / chevron right.
/// Multi-choice options open a bottom sheet with the same choices instead of
/// spreading chips through the list.
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

  Future<void> _clearCache() async {
    // Downloads are spared, which is what the paragraph under the row
    // promises. Wiping them here would delete megabytes the reader
    // deliberately fetched, without ever saying so.
    await ref.read(contentCacheProvider)?.clear();
    ref.invalidate(offlineBooksProvider);
    await _refreshCacheSize();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cache geleegd. Gedownloade boeken zijn bewaard.'),
      ),
    );
  }

  Future<void> _syncPending() async {
    await ref.read(notesRepositoryProvider).flushPendingChanges();
    await _refreshCacheSize();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readingSettingsProvider);
    final controller = ref.read(readingSettingsProvider.notifier);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Instellingen')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _SettingsGroup(
            title: 'Weergave',
            first: true,
            children: [
              // Applies on the spot: main.dart watches the same stored value
              // and resolves AppTheme's brightness from it.
              _SettingsRow(
                label: 'Thema',
                value: settings.themeMode.label,
                onTap: () => _pickThemeMode(
                  context,
                  current: settings.themeMode,
                  onChanged: controller.setThemeMode,
                ),
              ),
            ],
          ),
          _SettingsGroup(
            title: 'Leesweergave',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: _SamplePreview(settings: settings),
              ),
              _SettingsRow(
                label: 'Tekstgrootte',
                value: settings.fontSize.label,
                onTap: () => _pickReaderOption<ReaderFontSize>(
                  context,
                  title: 'Tekstgrootte',
                  values: ReaderFontSize.values,
                  selectedOf: (s) => s.fontSize,
                  labelOf: (v) => v.label,
                  onChanged: controller.setFontSize,
                ),
              ),
              _SettingsRow(
                label: 'Regelafstand',
                value: settings.lineHeight.label,
                onTap: () => _pickReaderOption<ReaderLineHeight>(
                  context,
                  title: 'Regelafstand',
                  values: ReaderLineHeight.values,
                  selectedOf: (s) => s.lineHeight,
                  labelOf: (v) => v.label,
                  onChanged: controller.setLineHeight,
                ),
              ),
              _SettingsRow(
                label: 'Lettertype',
                value: settings.fontFamily.label,
                onTap: () => _pickReaderOption<ReaderFontFamily>(
                  context,
                  title: 'Lettertype',
                  values: ReaderFontFamily.values,
                  selectedOf: (s) => s.fontFamily,
                  labelOf: (v) => v.label,
                  onChanged: controller.setFontFamily,
                ),
              ),
              _SettingsRow(
                label: 'Letterafstand',
                value: settings.letterSpacing.label,
                onTap: () => _pickReaderOption<ReaderLetterSpacing>(
                  context,
                  title: 'Letterafstand',
                  values: ReaderLetterSpacing.values,
                  selectedOf: (s) => s.letterSpacing,
                  labelOf: (v) => v.label,
                  onChanged: controller.setLetterSpacing,
                ),
              ),
              _SettingsRow(
                label: 'Versnummers tonen',
                switchValue: settings.showVerseNumbers,
                onSwitchChanged: controller.setShowVerseNumbers,
              ),
            ],
          ),

          const _NotificationsSection(),

          const _LevensboomSection(),

          _SettingsGroup(
            title: 'Opgeslagen tekst',
            children: [
              _SettingsRow(
                label: 'Cache',
                subtitle: _cacheBytes == null
                    ? 'Berekenen…'
                    : '${_formatBytes(_cacheBytes!)} opgeslagen',
                trailing: _RowButton(label: 'Cache legen', onPressed: _clearCache),
              ),
              if (_pendingChanges > 0)
                _SettingsRow(
                  label: 'Synchronisatie',
                  subtitle:
                      '$_pendingChanges wijziging${_pendingChanges == 1 ? '' : 'en'} wacht'
                      '${_pendingChanges == 1 ? '' : 'en'} op synchronisatie',
                  trailing: _RowButton(
                    label: 'Nu synchroniseren',
                    onPressed: _syncPending,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Text(
                  'Hoofdstukken die je leest worden opgeslagen zodat je ze offline kunt '
                  'teruglezen. Boeken die je expliciet downloadt blijven bewaard; de rest '
                  'wordt automatisch opgeruimd bij ${_formatBytes(ContentCache.defaultMaxBytes)}.',
                  style: AppTheme.caption,
                ),
              ),
              // The same list as the reader's offline sheet, so the answer to
              // "what is actually on my phone, and how do I get that space back"
              // is in both places a reader would look for it.
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: OfflineBooksList(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _pickThemeMode(
  BuildContext context, {
  required ThemeMode current,
  required ValueChanged<ThemeMode> onChanged,
}) async {
  final picked = await showModalBottomSheet<ThemeMode>(
    context: context,
    showDragHandle: true,
    builder: (_) => _ThemeModeSheet(selected: current),
  );
  // Applied only once the sheet has been popped: the switch rekeys the whole
  // app, and a sheet still on screen would be repainted mid-dismissal.
  if (picked != null && picked != current) onChanged(picked);
}

void _pickReaderOption<T>(
  BuildContext context, {
  required String title,
  required List<T> values,
  required T Function(ReadingSettings settings) selectedOf,
  required String Function(T value) labelOf,
  required ValueChanged<T> onChanged,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ReaderOptionSheet<T>(
      title: title,
      values: values,
      selectedOf: selectedOf,
      labelOf: labelOf,
      onChanged: onChanged,
    ),
  );
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

        return _SettingsGroup(
          title: 'Meldingen',
          children: [
            _SettingsRow(
              label: 'Herinneringen',
              subtitle: status.permitted
                  ? 'Hooguit één per dag, op jouw moment.'
                  : 'Zet meldingen aan in de systeeminstellingen.',
              switchValue: master,
              onSwitchChanged: (on) async {
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
              _SettingsRow(
                label: 'Reeks bijna kwijt',
                switchValue: prefs.streakAtRiskEnabled,
                onSwitchChanged: (v) async {
                  await prefsCtl.setType('streakAtRisk', v);
                  bump();
                },
              ),
              _SettingsRow(
                label: 'Onafgemaakte les',
                switchValue: prefs.lessonHalfwayEnabled,
                onSwitchChanged: (v) async {
                  await prefsCtl.setType('lessonHalfway', v);
                  bump();
                },
              ),
              if (hasWeekGoal)
                _SettingsRow(
                  label: 'Weekdoel',
                  switchValue: prefs.weeklyGoalEnabled,
                  onSwitchChanged: (v) async {
                    await prefsCtl.setType('weeklyGoal', v);
                    bump();
                  },
                ),
              _SettingsRow(
                label: 'Mijlpalen',
                switchValue: prefs.milestonesEnabled,
                onSwitchChanged: (v) async {
                  await prefsCtl.setType('milestone', v);
                  bump();
                },
              ),
              _SettingsRow(
                label: 'Weer welkom (afwezigheid)',
                switchValue: prefs.dormantEnabled,
                onSwitchChanged: (v) async {
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
              _SettingsRow(
                label: prefs.snoozedNow
                    ? 'Meldingen weer aanzetten voor vandaag'
                    : 'Sla vandaag over',
                subtitle: prefs.snoozedNow
                    ? 'Vandaag blijft het stil.'
                    : 'Eén dag geen meldingen; morgen gaat het gewoon door.',
                trailing: Icon(
                  prefs.snoozedNow
                      ? Icons.notifications_active_outlined
                      : Icons.snooze_outlined,
                  size: 20,
                  color: AppTheme.teal,
                ),
                onTap: () async {
                  if (prefs.snoozedNow) {
                    await prefsCtl.clearSnooze();
                  } else {
                    await prefsCtl.snoozeToday();
                  }
                  bump();
                },
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The Levensboom controls, mirroring the website's Instellingen section.
///
/// Turning the tree off is purely visual - XP, levels and badges keep accruing
/// - which the copy has to say out loud, or the toggle reads as "stop counting
/// my progress".
class _LevensboomSection extends ConsumerWidget {
  const _LevensboomSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(treeStateProvider).value;
    final notifier = ref.read(treeStateProvider.notifier);

    return _SettingsGroup(
      title: 'Voortgang',
      children: [
        _SettingsRow(
          label: 'Boom tonen',
          subtitle: 'Je XP, niveau en badges lopen door',
          switchValue: !(tree?.disabled ?? false),
          onSwitchChanged: tree == null
              ? null
              : (value) => notifier.setPrefs(disabled: !value),
        ),
        _SettingsRow(
          label: 'Minder beweging',
          subtitle: 'Geen wiegen, deeltjes of groei-animatie',
          switchValue: tree?.reducedMotion ?? false,
          onSwitchChanged: tree == null
              ? null
              : (value) => notifier.setPrefs(reducedMotion: value),
        ),
        _SettingsRow(
          label: 'Openbaar profiel',
          subtitle:
              'Een pagina op de website met je boom, je voornaam, je niveau en je '
              'badges. Nooit je e-mail, reeks of leesgeschiedenis.',
          switchValue: tree?.publicProfile ?? false,
          onSwitchChanged:
              tree == null ? null : (value) => notifier.setPublicProfile(value),
        ),
        if (tree != null && tree.publicProfile) ...[
          _SettingsRow(
            label: 'Kopieer link',
            trailing: Icon(Icons.link, size: 20, color: AppTheme.teal),
            onTap: () async {
              await Clipboard.setData(
                ClipboardData(text: publicProfileUrl(tree.seed)),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Link gekopieerd.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
          _SettingsRow(
            label: 'Bekijken op de website',
            trailing: Icon(Icons.open_in_new, size: 18, color: AppTheme.teal),
            // The page lives on the website; it opens in the browser, like
            // every other external link in the app.
            onTap: () {
              final uri = Uri.tryParse(publicProfileUrl(tree.seed));
              if (uri != null) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ],
    );
  }
}

/// A reminder with a time: the switch arms it, the time button (only shown
/// while armed) opens the picker. Tapping the row itself flips the switch.
class _NotifTimeRow extends StatelessWidget implements _SettingsRowLike {
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
    return _SettingsRow(
      label: title,
      subtitle: enabled ? 'Elke keer om ${_fmtMinutes(minutes)}' : 'Uit',
      trailing: enabled ? _TimeButton(minutes: minutes, onPicked: onPickTime) : null,
      switchValue: enabled,
      onSwitchChanged: onToggle,
    );
  }
}

class _QuietHoursRow extends StatelessWidget implements _SettingsRowLike {
  const _QuietHoursRow({
    required this.startMinutes,
    required this.endMinutes,
    required this.onChanged,
  });

  final int startMinutes;
  final int endMinutes;
  final void Function(int? start, int? end) onChanged;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return _SettingsRow(
      label: 'Stille uren',
      subtitle: 'Geen meldingen tussen deze tijden',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TimeButton(minutes: startMinutes, onPicked: (m) => onChanged(m, null)),
          Text('–', style: AppTheme.bodyMuted),
          _TimeButton(minutes: endMinutes, onPicked: (m) => onChanged(null, m)),
        ],
      ),
    );
  }
}

/// A compact text button for the trailing slot of a row, sized to the row
/// rather than to the 48px tap target a bare TextButton would claim.
class _RowButton extends StatelessWidget {
  const _RowButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

/// `08:00` as a button that opens the time picker.
class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.minutes, required this.onPicked});

  final int minutes;
  final ValueChanged<int> onPicked;

  @override
  Widget build(BuildContext context) {
    return _RowButton(
      label: _fmtMinutes(minutes),
      onPressed: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
        );
        if (picked != null) onPicked(picked.hour * 60 + picked.minute);
      },
    );
  }
}

/// The reader's own text, set the way the current preferences say.
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

/// Licht / Donker / Systeem as a picker sheet. Returns the choice through
/// `Navigator.pop` so the caller applies it after the sheet is gone.
class _ThemeModeSheet extends StatelessWidget {
  const _ThemeModeSheet({required this.selected});

  final ThemeMode selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _SettingsGroup(
          title: 'Thema',
          first: true,
          children: [
            for (final mode in ThemeModeLabelX.pickerOrder)
              _SettingsRow(
                icon: mode.icon,
                label: mode.label,
                selected: mode == selected,
                onTap: () => Navigator.of(context).pop(mode),
              ),
          ],
        ),
      ),
    );
  }
}

/// One reading preference as a picker sheet, with the sample text above the
/// choices so a tap shows its effect right away. The sheet stays open while
/// the reader compares options; the drag handle closes it.
class _ReaderOptionSheet<T> extends ConsumerWidget {
  const _ReaderOptionSheet({
    required this.title,
    required this.values,
    required this.selectedOf,
    required this.labelOf,
    required this.onChanged,
  });

  final String title;
  final List<T> values;
  final T Function(ReadingSettings settings) selectedOf;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched here rather than passed in: the sheet outlives the tap, so the
    // sample and the check mark have to follow the store.
    final settings = ref.watch(readingSettingsProvider);
    final selected = selectedOf(settings);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: _SettingsGroup(
          title: title,
          first: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: _SamplePreview(settings: settings),
            ),
            for (final value in values)
              _SettingsRow(
                label: labelOf(value),
                selected: value == selected,
                onTap: () => onChanged(value),
              ),
          ],
        ),
      ),
    );
  }
}

/// Marker for widgets that render as a [_SettingsRow]; [_SettingsGroup] only
/// draws a hairline between two neighbours that both carry it, so cards and
/// paragraphs inside a group are never underlined.
abstract interface class _SettingsRowLike {}

/// One titled block of the settings list: a bold title, its children with
/// hairlines between consecutive rows, and a full-bleed rule above the block
/// (except the first one).
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.children,
    this.first = false,
  });

  final String title;
  final List<Widget> children;
  final bool first;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (first)
          const SizedBox(height: 12)
        else ...[
          const SizedBox(height: 22),
          const RuleLine(),
          const SizedBox(height: 26),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(title, style: AppTheme.displaySmall),
        ),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0 &&
              children[i - 1] is _SettingsRowLike &&
              children[i] is _SettingsRowLike)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: RuleLine(),
            ),
          children[i],
        ],
      ],
    );
  }
}

/// One row of a [_SettingsGroup]: label and optional subtitle on the left; on
/// the right - only the ones that apply, in this order - a muted value, a
/// custom trailing widget, a switch, a check mark (picker sheets) or a chevron
/// (rows that open something). A switch row flips its switch when tapped.
class _SettingsRow extends StatelessWidget implements _SettingsRowLike {
  const _SettingsRow({
    required this.label,
    this.subtitle,
    this.icon,
    this.value,
    this.trailing,
    this.onTap,
    this.switchValue,
    this.onSwitchChanged,
    this.selected,
  }) : assert(switchValue == null || onTap == null,
            'a switch row toggles on tap; it cannot also open something');

  final String label;
  final String? subtitle;
  final IconData? icon;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitchChanged;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final isSwitch = switchValue != null;
    final dimmed = isSwitch && onSwitchChanged == null;
    final tap = onTap ??
        (isSwitch && onSwitchChanged != null
            ? () => onSwitchChanged!(!switchValue!)
            : null);
    final showChevron =
        onTap != null && !isSwitch && selected == null && trailing == null;
    final inkColor = dimmed ? AppTheme.inkFaint : AppTheme.ink;

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: dimmed ? AppTheme.inkFaint : AppTheme.inkMuted),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTheme.bodyLead.copyWith(
                      color: inkColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: AppTheme.caption),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  value!,
                  style: AppTheme.bodyMuted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            if (isSwitch) ...[
              const SizedBox(width: 8),
              Switch(
                value: switchValue!,
                onChanged: onSwitchChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
            if (selected != null) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.check,
                size: 20,
                color: selected! ? AppTheme.teal : Colors.transparent,
              ),
            ],
            if (showChevron) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: AppTheme.inkFaint),
            ],
          ],
        ),
      ),
    );

    if (tap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: tap, child: content),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} kB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
