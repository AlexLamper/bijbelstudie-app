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
import '../../auth/present/auth_controller.dart' show sessionAccountProvider;
import '../../bible/present/bible_providers.dart';
import '../../bible/present/offline_library_sheet.dart';
import '../../friends/present/contacts/contact_discovery_providers.dart'
    show contactDiscoveryOfferedProvider;
import '../../friends/present/contacts/findable_switch.dart';
import '../../levensboom/present/levensboom_providers.dart';
import '../../levensboom/present/studio/levensboom_studio_screen.dart' show publicProfileUrl;
import '../../notes/data/notes_repository.dart';
import '../../studies/present/studies_providers.dart';
import '../data/notification_prefs.dart';
import '../data/reading_settings.dart';
import 'settings_controls.dart';
import 'theme_mode_provider.dart';
import 'vriendenkring_copy.dart' as kring;
import 'vriendenkring_settings_provider.dart';

/// Settings, as one ruled list: titled groups divided by full-bleed rules, each
/// a run of [SettingsRow]s - label left, control / switch / chevron right.
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
            children: readingDisplayRows(
              settings: settings,
              controller: controller,
            ),
          ),

          const _NotificationsSection(),

          const _LevensboomSection(),

          const _VriendenkringSection(),

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
              SettingsRow(
                label: 'Cache',
                subtitle: _cacheBytes == null
                    ? 'Berekenen…'
                    : '${_formatBytes(_cacheBytes!)} opgeslagen',
                trailing: _RowButton(label: 'Cache legen', onPressed: _clearCache),
              ),
              if (_pendingChanges > 0)
                SettingsRow(
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
            SettingsRow(
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
              SettingsRow(
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
              SettingsRow(
                label: 'Tekst van de dag',
                switchValue: prefs.verseEnabled,
                onSwitchChanged: (v) async {
                  await prefsCtl.setContent(DailyContentKind.verse, v);
                  bump();
                },
              ),
              SettingsRow(
                label: 'Leesplan',
                subtitle: 'Bijbel in een jaar',
                switchValue: prefs.planEnabled,
                onSwitchChanged: (v) async {
                  await prefsCtl.setContent(DailyContentKind.plan, v);
                  bump();
                },
              ),
              SettingsRow(
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
              SettingsRow(
                label: 'Reeks bijna kwijt',
                switchValue: prefs.streakAtRiskEnabled,
                onSwitchChanged: (v) async {
                  await prefsCtl.setType('streakAtRisk', v);
                  bump();
                },
              ),
              SettingsRow(
                label: 'Onafgemaakte les',
                switchValue: prefs.lessonHalfwayEnabled,
                onSwitchChanged: (v) async {
                  await prefsCtl.setType('lessonHalfway', v);
                  bump();
                },
              ),
              if (hasWeekGoal)
                SettingsRow(
                  label: 'Weekdoel',
                  switchValue: prefs.weeklyGoalEnabled,
                  onSwitchChanged: (v) async {
                    await prefsCtl.setType('weeklyGoal', v);
                    bump();
                  },
                ),
              SettingsRow(
                label: 'Mijlpalen',
                switchValue: prefs.milestonesEnabled,
                onSwitchChanged: (v) async {
                  await prefsCtl.setType('milestone', v);
                  bump();
                },
              ),
              SettingsRow(
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
              SettingsRow(
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
        SettingsRow(
          label: 'Boom tonen',
          subtitle: 'Je XP, niveau en beloningen lopen door',
          switchValue: !(tree?.disabled ?? false),
          onSwitchChanged: tree == null
              ? null
              : (value) => notifier.setPrefs(disabled: !value),
        ),
        SettingsRow(
          label: 'Minder beweging',
          subtitle: 'Geen wiegen, deeltjes of groei-animatie',
          switchValue: tree?.reducedMotion ?? false,
          onSwitchChanged: tree == null
              ? null
              : (value) => notifier.setPrefs(reducedMotion: value),
        ),
        SettingsRow(
          label: 'Openbaar profiel',
          subtitle:
              'Een pagina op de website met je boom, je voornaam, je niveau en je '
              'beloningen. Nooit je e-mail, reeks of leesgeschiedenis.',
          switchValue: tree?.publicProfile ?? false,
          onSwitchChanged:
              tree == null ? null : (value) => notifier.setPublicProfile(value),
        ),
        if (tree != null && tree.publicProfile) ...[
          SettingsRow(
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
          SettingsRow(
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

/// The Vriendenkring controls, mirroring the website's panel of the same name
/// (`components/settings/vriendenkringCopy.ts`, reused word for word in
/// `vriendenkring_copy.dart`).
///
/// Four switches: who may find you, and permission for each of the three
/// things that could land in your kring. Only Mijlpalen is read by the server
/// today, so the paragraph under the card says so out loud instead of letting
/// two switches imply an automatic sharing that no code does - a tekst van de
/// dag and a notitie reach the kring only through their own "Deel met je
/// vrienden".
///
/// Every switch writes one named path and then adopts whatever the server says
/// the settings now are; see [vriendenkringSettingsProvider].
class _VriendenkringSection extends ConsumerWidget {
  const _VriendenkringSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final settings = ref.watch(vriendenkringSettingsProvider).value;
    final notifier = ref.read(vriendenkringSettingsProvider.notifier);
    final share = settings?.autoShare;

    // Whether contact matching exists at all in this build and on this server.
    // It decides which of the two findability controls is drawn, and the
    // important word is "which": `POST /friends/discovery/hashes` sets
    // `discoverable` itself (service.ts), so the contacts tile and the plain
    // switch below write the same field, and exactly one of them may be on
    // screen. See the slot comment further down.
    final contactsOffered = ref.watch(contactDiscoveryOfferedProvider).value == true;

    // Null while the settings are still coming in, or after a failed read:
    // the rows then render dimmed and unflippable rather than inviting a tap
    // that would write a value nobody has read yet.
    ValueChanged<bool>? flip(VriendenkringSwitch which) {
      if (settings == null) return null;
      return (value) async {
        final messenger = ScaffoldMessenger.of(context);
        final result = await notifier.setSwitch(which, value);
        // Only a failure is worth a SnackBar: the switch itself is the
        // confirmation when it lands. The line is the server's own.
        if (!result.ok) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(result.message),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      };
    }

    return _SettingsGroup(
      title: kring.vriendenkringSectionTitle,
      footer: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 10, 32, 0),
          child: Text(kring.autoShareFootnote, style: AppTheme.caption),
        ),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
          child: Text(
            kring.vriendenkringSectionSubtitle,
            style: AppTheme.caption,
          ),
        ),
        // ---------------------------------------------------------------
        // THE CONTACTS FLOW - the slot that was left here, now filled.
        //
        // There is exactly one findability control, as the slot asked, but it
        // is the contacts tile rather than the plain switch when contact
        // matching is live. Both write `discoverable`: the plain row writes
        // only the flag, while the tile also uploads (or deletes) the hashed
        // number and e-mail that make the flag mean anything. A flag on
        // without hashes is a promise nobody can keep - no address book can
        // match you - and turning the plain row off leaves the hashes behind,
        // so the tile is the honest one wherever it can take.
        //
        // When contact matching is off (no `CONTACT_MATCHING` dart-define or
        // no server pepper) the tile renders nothing by itself, so the plain
        // row stands in and the section is never left with a lone header.
        // ---------------------------------------------------------------
        if (!contactsOffered)
          SettingsRow(
            label: kring.discoverableLabel,
            subtitle: kring.discoverableHint,
            switchValue: settings?.discoverable ?? false,
            onSwitchChanged: flip(VriendenkringSwitch.discoverable),
          ),
        if (contactsOffered) const _FindableRow(),
        // Only when there is something to forget: offering it to a reader who
        // never made themselves findable is a row that does nothing and a
        // sentence that worries them for no reason.
        if (contactsOffered && (settings?.hasContactHashes ?? false))
          const _ForgetContactsRow(),

        SettingsRow(
          label: kring.autoShareMilestonesLabel,
          subtitle: kring.autoShareMilestonesHint,
          switchValue: share?.milestones ?? true,
          onSwitchChanged: flip(VriendenkringSwitch.milestones),
        ),
        SettingsRow(
          label: kring.autoShareVersesLabel,
          subtitle: kring.autoShareVersesHint,
          switchValue: share?.verses ?? false,
          onSwitchChanged: flip(VriendenkringSwitch.verses),
        ),
        SettingsRow(
          label: kring.autoShareNotesLabel,
          subtitle: kring.autoShareNotesHint,
          switchValue: share?.notes ?? false,
          onSwitchChanged: flip(VriendenkringSwitch.notes),
        ),
        // Only when there is something to forget. Offering it to a reader who
        // never let the app read their contacts is a row that does nothing
        // and a sentence that worries them for no reason.
        //
        // Skipped when contact matching is live: [ForgetContactsTile] above
        // is then the one way out, and it clears the app's own local traces
        // (the matched ids, the recorded disclosure, the findability mirror)
        // as well as the hashes on the server, which this row cannot.
        if (!contactsOffered && settings != null && settings.hasContactHashes)
          SettingsRow(
            label: kring.forgetContactsLabel,
            subtitle: kring.forgetContactsHint,
            trailing: _RowButton(
              label: kring.forgetContactsAction,
              onPressed: () => _forgetContacts(context, notifier),
            ),
          ),
      ],
    );
  }

  /// Confirms, then really deletes - the hashes are gone server-side, which is
  /// the whole point of the row, so it may not happen on a mis-tap.
  Future<void> _forgetContacts(
    BuildContext context,
    VriendenkringSettingsNotifier notifier,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(kring.forgetContactsConfirmTitle),
        content: const Text(kring.forgetContactsConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
            child: const Text(kring.forgetContactsConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await notifier.forgetContacts();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? kring.forgetContactsDone : 'Dat is niet gelukt. Probeer het later nog eens.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// [FindableSwitchTile] as a settings row, so it gets the card's hairlines.
///
/// The tile draws its own [AppCard] by default, which would be a card inside a
/// card here; `showCard: false` hands over the bare row and this adds the
/// padding the rest of the group uses. It self-gates on
/// `contactDiscoveryOfferedProvider` too, so this is belt and braces.
class _FindableRow extends StatelessWidget implements SettingsRowLike {
  const _FindableRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: FindableSwitchTile(showCard: false),
    );
  }
}

/// "Mijn contactgegevens vergeten" as a settings row. See [_FindableRow].
class _ForgetContactsRow extends StatelessWidget implements SettingsRowLike {
  const _ForgetContactsRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(8, 2, 8, 2),
      child: Align(alignment: Alignment.centerLeft, child: ForgetContactsTile()),
    );
  }
}

/// A reminder with a time: the switch arms it, the time button (only shown
/// while armed) opens the picker. Tapping the row itself flips the switch.
class _NotifTimeRow extends StatelessWidget implements SettingsRowLike {
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
    return SettingsRow(
      label: title,
      subtitle: subtitle ?? (enabled ? 'Elke keer om ${_fmtMinutes(minutes)}' : 'Uit'),
      trailing: enabled ? _TimeButton(minutes: minutes, onPicked: onPickTime) : null,
      switchValue: enabled,
      onSwitchChanged: onToggle,
    );
  }
}

class _QuietHoursRow extends StatelessWidget implements SettingsRowLike {
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
    return SettingsRow(
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: first ? 16 : 28),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
          child: Eyebrow(title),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SettingsCard(children: children),
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

    // The container insets its child by the border width, so the mini screen has
    // to clip to the border's inner curve - the container's own clip follows the
    // outer radius, which lets the child's corners cover the border there.
    final borderWidth = selected ? 2.0 : 1.0;

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
                  width: borderWidth,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd - borderWidth),
                clipBehavior: Clip.antiAlias,
                child: screen,
              ),
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} kB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
