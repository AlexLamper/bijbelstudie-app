import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/account_scope.dart';
import '../../../core/db/content_cache.dart';
import '../../../core/notifications/notification_scheduler.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/segmented_track.dart';
import '../../auth/present/auth_controller.dart' show sessionAccountProvider;
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
/// a run of [_SettingsRow]s - label left, control / switch / chevron right.
/// Choices are made in place: Thema is a segmented control on its row, and the
/// reading preferences are the same chip rows the reader's Weergave sheet uses.
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
    // This account's queue only; another reader's waits for their sign-in.
    final account = await AccountScope.resolve(ref.read(sessionAccountProvider));
    final pending = await cache?.pendingChangeCount(account: account);
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
              _ThemePicker(
                selected: settings.themeMode,
                onChanged: (picked) {
                  if (picked != settings.themeMode) controller.setThemeMode(picked);
                },
              ),
            ],
          ),
          // The same settings the reader's Weergave sheet writes, through the
          // same controller, so the two places cannot drift apart.
          _SettingsGroup(
            title: 'Leesweergave',
            children: [
              _SegmentRow<ReaderFontSize>(
                label: 'Tekstgrootte',
                values: ReaderFontSize.values,
                selected: settings.fontSize,
                valueLabel: (v) => v.label,
                onChanged: controller.setFontSize,
                segment: (v, color) => Text(
                  'A',
                  style: TextStyle(
                    fontFamily: AppTheme.sansFontName,
                    fontSize: switch (v) {
                      ReaderFontSize.small => 12,
                      ReaderFontSize.base => 15,
                      ReaderFontSize.large => 18,
                      ReaderFontSize.xlarge => 21,
                    },
                    height: 1.2,
                    color: color,
                  ),
                ),
              ),
              _SegmentRow<ReaderFontFamily>(
                label: 'Lettertype',
                values: ReaderFontFamily.values,
                selected: settings.fontFamily,
                valueLabel: (v) => v.label,
                onChanged: controller.setFontFamily,
                segment: (v, color) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Aa',
                      style: TextStyle(
                        fontFamily: v.fontName,
                        fontSize: 18,
                        height: 1.2,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      v.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              _SegmentRow<ReaderLineHeight>(
                label: 'Regelafstand',
                values: ReaderLineHeight.values,
                selected: settings.lineHeight,
                valueLabel: (v) => v.label,
                onChanged: controller.setLineHeight,
                segment: (v, color) => _LineSpacingGlyph(
                  gap: switch (v) {
                    ReaderLineHeight.snug => 2,
                    ReaderLineHeight.normal => 3.5,
                    ReaderLineHeight.relaxed => 5,
                    ReaderLineHeight.loose => 6.5,
                  },
                  color: color,
                ),
              ),
              _SegmentRow<ReaderLetterSpacing>(
                label: 'Letterafstand',
                values: ReaderLetterSpacing.values,
                selected: settings.letterSpacing,
                valueLabel: (v) => v.label,
                onChanged: controller.setLetterSpacing,
                // The stored steps, exaggerated so they can be told apart at
                // this size.
                segment: (v, color) => Text(
                  'abc',
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: AppTheme.sansFontName,
                    fontSize: 14,
                    letterSpacing: v.points * 2,
                    color: color,
                  ),
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
            // Below the card rather than in it: the books list is a card of
            // its own.
            footer: [
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 10, 32, 0),
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
                padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: OfflineBooksList(),
              ),
            ],
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
            ],
          ),
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

/// The notifications block (DAILY_HABIT_PLAN.md §1): a master switch, the two
/// daily slots (Ochtend, Avond herinnering), what the morning may be about,
/// the other nudges, quiet hours, and a one-tap "sla vandaag over". Full
/// opt-out is a single tap on the master row - no confirmation nag.
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

        // A settings change never changes the words, only when and which:
        // the cached schedule is reused.
        void bump() => ref
            .read(notificationReschedulerProvider)
            .requestReschedule(contentChanged: false);

        return _SettingsGroup(
          title: 'Meldingen',
          children: [
            _SettingsRow(
              label: 'Herinneringen',
              subtitle: status.permitted
                  ? 'Hooguit twee per dag.'
                  : 'Zet meldingen aan in de systeeminstellingen.',
              switchValue: master,
              onSwitchChanged: (on) async {
                if (on) {
                  final granted = await ref
                      .read(notificationServiceProvider)
                      .requestPermission();
                  // A denial is not stored as "off": the switch reads the OS
                  // state too, and granting later in the system settings
                  // should just start the reminders.
                  if (granted) await prefsCtl.setMasterEnabled(true);
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
              _SettingsRow(
                label: 'Ochtend',
                subtitle: 'Je taak van vandaag, met de tekst van de dag',
                trailing: _TimeButton(
                  minutes: prefs.morningMinutes,
                  onPicked: (m) async {
                    await prefsCtl.setMorningMinutes(m);
                    bump();
                  },
                ),
              ),
              _NotifTimeRow(
                title: 'Avond herinnering',
                subtitle: 'Alleen als je die dag de app nog niet hebt geopend',
                enabled: prefs.eveningEnabled,
                minutes: prefs.eveningMinutes,
                onToggle: (v) async {
                  await prefsCtl.setEvening(enabled: v);
                  bump();
                },
                onPickTime: (m) async {
                  await prefsCtl.setEvening(minutes: m, enabled: true);
                  bump();
                },
              ),
              if (prefs.eveningEnabled && prefs.eveningMinutes <= prefs.morningMinutes)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'De avond valt voor de ochtend en wordt daarom overgeslagen.',
                    style: AppTheme.caption,
                  ),
                ),
              const _SubHeading('Inhoud'),
              _SettingsRow(
                label: 'Tekst van de dag',
                switchValue: prefs.verseEnabled,
                onSwitchChanged: (v) async {
                  await prefsCtl.setContent(DailyContentKind.verse, v);
                  bump();
                },
              ),
              _SettingsRow(
                label: 'Leesplan',
                subtitle: 'Bijbel in een jaar',
                switchValue: prefs.planEnabled,
                onSwitchChanged: (v) async {
                  await prefsCtl.setContent(DailyContentKind.plan, v);
                  bump();
                },
              ),
              _SettingsRow(
                label: 'Studie',
                subtitle: 'De les waar je gebleven was',
                switchValue: prefs.studyEnabled,
                onSwitchChanged: (v) async {
                  await prefsCtl.setContent(DailyContentKind.study, v);
                  bump();
                },
              ),
              const _SubHeading(
                'Overige meldingen',
                caption: 'Alleen op een dag waarop er nog ruimte is.',
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
              const _SubHeading('Rust'),
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

/// A small heading inside a group, splitting one block into parts.
class _SubHeading extends StatelessWidget {
  const _SubHeading(this.title, {this.caption});

  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTheme.bodyLead.copyWith(fontWeight: FontWeight.w600),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, style: AppTheme.caption),
          ],
        ],
      ),
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
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool enabled;
  final int minutes;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onPickTime;

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      label: title,
      subtitle: subtitle ?? (enabled ? 'Elke keer om ${_fmtMinutes(minutes)}' : 'Uit'),
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
          Text('-', style: AppTheme.bodyMuted),
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

/// Marker for widgets that render as a [_SettingsRow]; [_SettingsGroup] only
/// draws a hairline between two neighbours that both carry it, so cards and
/// paragraphs inside a group are never underlined.
abstract interface class _SettingsRowLike {}

/// One block of the settings list: a small uppercase title over a card that
/// holds its [children], with hairlines between consecutive rows. [footer]
/// sits under the card, on the page, for notes and anything that is a card of
/// its own.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.children,
    this.footer = const [],
    this.first = false,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> footer;
  final bool first;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: first ? 16 : 28),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
          child: Eyebrow(title),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: scheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0 &&
                    children[i - 1] is _SettingsRowLike &&
                    children[i] is _SettingsRowLike)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: RuleLine(),
                  ),
                children[i],
              ],
            ],
          ),
        ),
        ...footer,
      ],
    );
  }
}

/// The Thema choice as three small screens - light, dark, and half of each for
/// "follow the device" - each over a radio with its label. The chosen screen
/// gets an accent border.
class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.selected, required this.onChanged});

  final ThemeMode selected;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Thema',
            style: AppTheme.bodyLead.copyWith(
              color: AppTheme.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final mode in ThemeModeLabelX.pickerOrder) ...[
                if (mode != ThemeModeLabelX.pickerOrder.first) const SizedBox(width: 10),
                Expanded(
                  child: _ThemeTile(
                    mode: mode,
                    selected: mode == selected,
                    onTap: () => onChanged(mode),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.mode, required this.selected, required this.onTap});

  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const light = _MiniScreen(
      background: AppTheme.lightPaperRaised,
      line: AppTheme.lightRuleStrong,
    );
    const dark = _MiniScreen(
      background: AppTheme.darkPaper,
      line: AppTheme.darkRuleStrong,
    );
    final screen = switch (mode) {
      ThemeMode.light => light,
      ThemeMode.dark => dark,
      ThemeMode.system => Stack(
        fit: StackFit.expand,
        children: [
          light,
          ClipRect(clipper: _RightHalfClipper(), child: dark),
        ],
      ),
    };

    return Semantics(
      button: true,
      selected: selected,
      label: mode.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!selected) AppHaptics.selection();
          onTap();
        },
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 76,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: selected ? AppTheme.teal : AppTheme.rule,
                  width: selected ? 2 : 1,
                ),
              ),
              child: screen,
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Radio<ThemeMode>(
                  value: mode,
                  groupValue: selected ? mode : null,
                  onChanged: (_) => onTap(),
                  activeColor: AppTheme.teal,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                Flexible(
                  child: Text(
                    mode.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyLead.copyWith(
                      fontSize: 14,
                      color: selected ? AppTheme.ink : AppTheme.inkMuted,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A phone screen in miniature: three lines of "text" on a fixed background.
class _MiniScreen extends StatelessWidget {
  const _MiniScreen({required this.background, required this.line});

  final Color background;
  final Color line;

  @override
  Widget build(BuildContext context) {
    Widget bar(double widthFactor) => FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 5,
        decoration: BoxDecoration(
          color: line,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        ),
      ),
    );
    return ColoredBox(
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [bar(0.8), const SizedBox(height: 7), bar(0.95), const SizedBox(height: 7), bar(0.6)],
        ),
      ),
    );
  }
}

class _RightHalfClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) => Rect.fromLTRB(size.width / 2, 0, size.width, size.height);

  @override
  bool shouldReclip(_RightHalfClipper oldClipper) => false;
}

/// A Leesweergave row: label left, the current value right, and under both a
/// full-width [SegmentedTrack] whose segments show the choice rather than name
/// it.
class _SegmentRow<T> extends StatelessWidget implements _SettingsRowLike {
  const _SegmentRow({
    required this.label,
    required this.values,
    required this.selected,
    required this.valueLabel,
    required this.onChanged,
    required this.segment,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T value) valueLabel;
  final ValueChanged<T> onChanged;
  final Widget Function(T value, Color color) segment;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTheme.bodyLead.copyWith(
                    color: AppTheme.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(valueLabel(selected), style: AppTheme.bodyMuted),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedTrack(
            segments: [
              for (final v in values)
                SegmentedTrackSegment(
                  semanticLabel: valueLabel(v),
                  builder: (context, _, color) => segment(v, color),
                ),
            ],
            selectedIndex: values.indexOf(selected),
            onChanged: (i) {
              if (values[i] != selected) onChanged(values[i]);
            },
          ),
        ],
      ),
    );
  }
}

/// Three short lines with [gap] between them - the Regelafstand glyph.
class _LineSpacingGlyph extends StatelessWidget {
  const _LineSpacingGlyph({required this.gap, required this.color});

  final double gap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget line() => Container(
      width: 20,
      height: 2,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [line(), SizedBox(height: gap), line(), SizedBox(height: gap), line()],
    );
  }
}

/// One row of a [_SettingsGroup]: label and optional subtitle on the left; on
/// the right - only the ones that apply, in this order - a custom trailing
/// widget, a switch or a chevron (rows that open something). A switch row flips
/// its switch when tapped.
class _SettingsRow extends StatelessWidget implements _SettingsRowLike {
  const _SettingsRow({
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.switchValue,
    this.onSwitchChanged,
  }) : assert(switchValue == null || onTap == null,
            'a switch row toggles on tap; it cannot also open something');

  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitchChanged;

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
        onTap != null && !isSwitch && trailing == null;
    final inkColor = dimmed ? AppTheme.inkFaint : AppTheme.ink;

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
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
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            if (isSwitch) ...[
              const SizedBox(width: 8),
              Switch(
                value: switchValue!,
                onChanged: onSwitchChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
