import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/reminder_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../auth/present/splash_screen.dart' show BijbelStudieWordmark;
import '../../bible/domain/version_catalog.dart';
import '../../bible/present/bible_providers.dart';
import '../../settings/data/reading_settings.dart';
import '../data/onboarding_storage.dart';
import '../data/preferences_repository.dart';

/// Post-registration setup: the questions the marketing intro
/// (`onboarding_screen.dart`) never asked. Reached once per account, from
/// [resolvePostAuthRoute] - see that function for the full trigger story.
///
/// Every choice here is applied through the app's real settings controllers
/// the moment it is made (not staged until "Aan de slag"), so leaving the
/// wizard half-finished - the app killed mid-flow - keeps whatever was
/// already picked instead of losing it. Only completion itself
/// ([OnboardingStorage.markSetupCompleted]) waits for the final step, which is
/// what makes the wizard reappear on the next launch if it never got that far.
class SetupFlowScreen extends ConsumerStatefulWidget {
  const SetupFlowScreen({super.key});

  @override
  ConsumerState<SetupFlowScreen> createState() => _SetupFlowScreenState();
}

class _SetupFlowScreenState extends ConsumerState<SetupFlowScreen> {
  static const _totalSteps = 3;

  final PageController _controller = PageController();
  int _index = 0;
  bool _finishing = false;

  bool get _isLast => _index == _totalSteps - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    _controller.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);

    await ref.read(onboardingStorageProvider).markSetupCompleted();

    // Best-effort: everything is already applied locally through
    // ReadingSettingsController, so a failed sync only means the website does
    // not see these choices yet - it must never block reaching the tour.
    final settings = ref.read(readingSettingsProvider);
    try {
      await ref.read(preferencesRepositoryProvider).syncPreferences({
        'onboardingCompleted': true,
        'translation': settings.lastVersionId,
        'fontSize': settings.fontSize.id,
        'lineHeight': settings.lineHeight.syncId,
        'reminderEnabled': settings.dailyReminderMinutes != null,
        if (settings.dailyReminderMinutes != null)
          'reminderMinutes': settings.dailyReminderMinutes,
      });
    } catch (_) {}

    if (mounted) context.go('/tour');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: Column(
          children: [
            // Header rail, matching the marketing intro's.
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.rule)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              height: 60,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const BijbelStudieWordmark(fontSize: 20),
                  TextButton(
                    // Setup is never a gate: skipping keeps whatever was
                    // already chosen and the defaults for the rest.
                    onPressed: _finishing ? null : _finish,
                    child: Text(
                      'Overslaan',
                      style: AppTheme.bodyStrong.copyWith(color: AppTheme.inkMuted),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                // Steps are driven by their own controls (chips, cards), not
                // by a horizontal drag that could skip past an unread step.
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _index = i),
                children: const [
                  _TranslationStep(),
                  _ReadingPrefsStep(),
                  _ReminderStep(),
                ],
              ),
            ),
            // Hairline step indicator, matching the marketing intro's.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: List.generate(_totalSteps, (i) {
                  final active = i == _index;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i == _totalSteps - 1 ? 0 : 6),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        height: 2,
                        color: active ? AppTheme.teal : AppTheme.rule,
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  SiteButton(
                    label: _isLast ? 'Aan de slag' : 'Volgende',
                    trailingIcon: Icons.arrow_forward,
                    loading: _finishing,
                    onPressed: _finishing ? null : _next,
                  ),
                  if (_index > 0) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _finishing ? null : _back,
                      child: const Text('Vorige'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Step 1 - which translation opens by default. Selection is read straight
/// off [ReadingSettingsController] rather than staged in local state, so
/// tapping a row takes effect immediately, exactly as the reader would expect
/// if it changed the same setting from Instellingen.
///
/// The list is grouped by language ([VersionCatalog]): Dutch first, then a
/// rule and a heading before the English ones, so it is obvious at a glance
/// where the Dutch translations stop.
class _TranslationStep extends ConsumerWidget {
  const _TranslationStep();

  /// Applies the choice to the reader as well as to the stored preference.
  ///
  /// [ReadingSettingsController.setLastVersion] alone was not enough: nothing
  /// re-reads it once [ReaderLocationController] has hydrated, and the splash
  /// screen deliberately hydrates the reader *before* it works out that this
  /// user still owes the setup wizard. So the translation picked here was
  /// written to disk, shown as selected, and then ignored for the rest of the
  /// session - the reader opened whatever it had already settled on.
  void _select(WidgetRef ref, String versionId) {
    ref.read(readerLocationProvider.notifier).applyPreferredVersion(versionId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionsAsync = ref.watch(bibleVersionsProvider);
    final selected = ref.watch(
      readingSettingsProvider.select((s) => s.lastVersionId),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Vertaling'),
          const SizedBox(height: 16),
          const Text('Kies je bijbelvertaling', style: AppTheme.displayLarge),
          const SizedBox(height: 12),
          const Text(
            'Welke vertaling wil je standaard gebruiken bij het lezen en '
            'studeren? Je kunt altijd wisselen.',
            style: AppTheme.bodyLead,
          ),
          const SizedBox(height: 28),
          versionsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 24),
              child: AppLoader(),
            ),
            error: (_, __) => Text(
              'Vertalingen konden niet worden geladen. Je kunt dit later '
              'instellen bij Instellingen.',
              style: AppTheme.bodyMuted,
            ),
            data: (versions) {
              final groups = VersionCatalog.grouped(versions);
              return Column(
                children: [
                  for (var g = 0; g < groups.length; g++) ...[
                    // No heading above the first group: the screen's own
                    // question already says these are Bible translations, and
                    // a "Nederlands" label above the very first row reads as
                    // noise. The separator earns its place only where the
                    // language actually changes.
                    if (g > 0) _LanguageSeparator(label: groups[g].label),
                    for (final version in groups[g].versions) ...[
                      _SelectableRow(
                        title: version.name,
                        subtitle: version.attribution,
                        selected: version.id == selected,
                        onTap: () => _select(ref, version.id),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A hairline with the language name sitting on it, drawn between two
/// language groups in the translation list. Same rule colour and eyebrow type
/// as every other divider in the app, so it reads as structure rather than as
/// another option.
class _LanguageSeparator extends StatelessWidget {
  const _LanguageSeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 18),
        child: Row(
          children: [
            const Expanded(child: RuleLine()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              // Eyebrow, not a bare Text: it carries the app's uppercase
              // treatment for section labels, and reusing it keeps this
              // divider looking like every other one.
              child: Eyebrow(label, compact: true),
            ),
            const Expanded(child: RuleLine()),
          ],
        ),
      ),
    );
  }
}

/// Step 2 - text size and line spacing, the two `ReadingSettings` a first
/// read is most sensitive to. Font family and verse numbers stay reachable
/// from Instellingen rather than crowding a first-run screen with every knob
/// that exists.
class _ReadingPrefsStep extends ConsumerWidget {
  const _ReadingPrefsStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readingSettingsProvider);
    final controller = ref.read(readingSettingsProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Leesvoorkeuren'),
          const SizedBox(height: 16),
          const Text('Stel je leesvoorkeuren in', style: AppTheme.displayLarge),
          const SizedBox(height: 12),
          const Text(
            'Zo lees je de bijbeltekst meteen zoals jij dat prettig vindt. '
            'Dit kun je later altijd aanpassen bij Instellingen.',
            style: AppTheme.bodyLead,
          ),
          const SizedBox(height: 24),
          _SamplePreview(settings: settings),
          const SizedBox(height: 20),
          Text('Tekstgrootte', style: AppTheme.bodyMuted.copyWith(fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final size in ReaderFontSize.values)
                ChoiceChip(
                  label: Text(size.label),
                  selected: size == settings.fontSize,
                  onSelected: (_) => controller.setFontSize(size),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Regelafstand', style: AppTheme.bodyMuted.copyWith(fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final lineHeight in ReaderLineHeight.values)
                ChoiceChip(
                  label: Text(lineHeight.label),
                  selected: lineHeight == settings.lineHeight,
                  onSelected: (_) => controller.setLineHeight(lineHeight),
                ),
            ],
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
      child: Text(
        'In den beginne schiep God den hemel en de aarde.',
        style: TextStyle(
          fontFamily: settings.fontFamily.fontName,
          fontSize: settings.fontSize.points,
          height: settings.lineHeight.factor,
          color: AppTheme.ink,
        ),
      ),
    );
  }
}

class _ReminderPreset {
  const _ReminderPreset(this.label, this.hour, this.minute);

  final String label;
  final int hour;
  final int minute;

  int get minutesPastMidnight => hour * 60 + minute;
}

const _reminderPresets = [
  _ReminderPreset('07:00', 7, 0),
  _ReminderPreset('08:00', 8, 0),
  _ReminderPreset('20:00', 20, 0),
];

/// Step 3 - the daily reading reminder. Picking a preset requests the OS
/// permission and schedules the notification right away (the same path
/// Instellingen uses), rather than deferring it to "Aan de slag": a denied
/// permission has to surface here, while the wizard can still explain why.
class _ReminderStep extends ConsumerStatefulWidget {
  const _ReminderStep();

  @override
  ConsumerState<_ReminderStep> createState() => _ReminderStepState();
}

class _ReminderStepState extends ConsumerState<_ReminderStep> {
  bool _busy = false;

  Future<void> _setReminder(int hour, int minute) async {
    setState(() => _busy = true);
    final service = ref.read(reminderServiceProvider);
    final granted = await service.requestPermission();
    if (!granted) {
      if (mounted) setState(() => _busy = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Meldingen staan uit. Zet ze aan in de systeeminstellingen.'),
        ),
      );
      return;
    }
    await service.scheduleDaily(hour: hour, minute: minute);
    await ref
        .read(readingSettingsProvider.notifier)
        .setDailyReminder(hour * 60 + minute);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickCustomTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked == null) return;
    await _setReminder(picked.hour, picked.minute);
  }

  Future<void> _turnOff() async {
    setState(() => _busy = true);
    await ref.read(reminderServiceProvider).cancelDaily();
    await ref.read(readingSettingsProvider.notifier).setDailyReminder(null);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final minutes = ref.watch(
      readingSettingsProvider.select((s) => s.dailyReminderMinutes),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Herinnering'),
          const SizedBox(height: 16),
          const Text('Wil je een dagelijkse herinnering?', style: AppTheme.displayLarge),
          const SizedBox(height: 12),
          const Text(
            'Een korte melding op een vast moment helpt om het lezen vast te '
            'houden. Je kunt dit altijd wijzigen of uitzetten bij Instellingen.',
            style: AppTheme.bodyLead,
          ),
          const SizedBox(height: 28),
          if (kIsWeb)
            Text(
              'Herinneringen zijn niet beschikbaar in de webversie.',
              style: AppTheme.bodyMuted,
            )
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final preset in _reminderPresets)
                  ChoiceChip(
                    label: Text(preset.label),
                    selected: minutes == preset.minutesPastMidnight,
                    onSelected: _busy
                        ? null
                        : (_) => _setReminder(preset.hour, preset.minute),
                  ),
                ActionChip(
                  label: const Text('Aangepaste tijd'),
                  onPressed: _busy ? null : _pickCustomTime,
                ),
              ],
            ),
            if (minutes != null) ...[
              const SizedBox(height: 20),
              TextButton(
                onPressed: _busy ? null : _turnOff,
                child: const Text('Geen herinnering, bedankt'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A selectable card row - a radio button dressed as the site's picker cards
/// (`onboarding-modal.tsx`'s option list), reused from the plan picker style
/// on `premium_screen.dart`.
class _SelectableRow extends StatelessWidget {
  const _SelectableRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: AppCard(
        onTap: onTap,
        borderColor: selected ? AppTheme.teal : AppTheme.rule,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTheme.bodyMuted.copyWith(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? AppTheme.teal : AppTheme.inkMuted,
            ),
          ],
        ),
      ),
    );
  }
}
