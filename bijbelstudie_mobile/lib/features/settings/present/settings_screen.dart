import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/content_cache.dart';
import '../../../core/notifications/reminder_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../bible/present/bible_providers.dart';
import '../../bible/present/offline_library_sheet.dart';
import '../../notes/data/notes_repository.dart';
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

          const _ReminderSection(),

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

/// Derives the reminder's on-screen state from what the OS actually reports,
/// not from [ReadingSettings.dailyReminderMinutes] alone.
///
/// A stored time with nothing genuinely pending means Part 1's manifest fix
/// was missing on a previous run, or Android dropped the alarm (reinstall,
/// force-stop) - `main.dart` re-applies the stored reminder for the same
/// reason on every launch; this catches whatever slips past that during a
/// running session, by trying the same fix again before the tile has to
/// decide what to show.
final _reminderStatusProvider = FutureProvider<ReminderStatus>((ref) async {
  final service = ref.watch(reminderServiceProvider);
  final minutes = ref.watch(
    readingSettingsProvider.select((s) => s.dailyReminderMinutes),
  );

  var status = await service.currentStatus();
  if (minutes != null && status.available && status.permitted && !status.pending) {
    await service.scheduleDaily(hour: minutes ~/ 60, minute: minutes % 60);
    status = await service.currentStatus();
  }
  return status;
});

class _ReminderSection extends ConsumerWidget {
  const _ReminderSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ReminderService no-ops everything on web; currentStatus() would report
    // this too, but skip the round trip entirely.
    if (kIsWeb) return const SizedBox.shrink();

    final statusAsync = ref.watch(_reminderStatusProvider);
    final settings = ref.watch(readingSettingsProvider);

    return statusAsync.when(
      // Resolving the real state is a platform-channel round trip. Showing
      // the stored time before that lands would be exactly the unverified
      // claim this rewrite exists to remove, so show nothing meanwhile.
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (status) {
        // No notifications implementation on this platform at all: a tile
        // the user could never make work either way.
        if (!status.available) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            const SectionHeader(eyebrow: 'Herinnering', title: 'Dagelijks lezen'),
            const SizedBox(height: 8),
            _ReminderTile(settings: settings, active: status.isActive),
          ],
        );
      },
    );
  }
}

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({required this.settings, required this.active});

  final ReadingSettings settings;

  /// Whether the OS confirms this reminder is both permitted and actually
  /// scheduled - never taken from [settings] directly, see
  /// [_reminderStatusProvider].
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time = active ? settings.dailyReminderTime : null;

    return RuleGrid(
      children: [
        RuleListTile(
          showRule: false,
          onTap: () => _pick(context, ref),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Herinnering', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      time == null
                          ? 'Uit'
                          : 'Elke dag om ${time.hour.toString().padLeft(2, '0')}:'
                                '${time.minute.toString().padLeft(2, '0')}',
                      style: AppTheme.bodyMuted.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (time != null)
                TextButton(
                  onPressed: () async {
                    await ref.read(reminderServiceProvider).cancelDaily();
                    await ref.read(readingSettingsProvider.notifier).setDailyReminder(null);
                    ref.invalidate(_reminderStatusProvider);
                  },
                  child: const Text('Uitzetten'),
                ),
              Icon(Icons.chevron_right, size: 18, color: AppTheme.inkMuted),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: settings.dailyReminderTime ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked == null) return;

    final service = ref.read(reminderServiceProvider);
    final granted = await service.requestPermission();
    if (!granted) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Meldingen staan uit. Zet ze aan in de systeeminstellingen.'),
        ),
      );
      return;
    }

    await service.scheduleDaily(hour: picked.hour, minute: picked.minute);
    await ref
        .read(readingSettingsProvider.notifier)
        .setDailyReminder(picked.hour * 60 + picked.minute);
    ref.invalidate(_reminderStatusProvider);
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
