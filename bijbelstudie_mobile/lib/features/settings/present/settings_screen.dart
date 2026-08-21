import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/content_cache.dart';
import '../../../core/notifications/reminder_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../notes/data/notes_repository.dart';
import '../data/reading_settings.dart';

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
          const SectionHeader(eyebrow: 'Lezen', title: 'Weergave'),
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
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Versnummers tonen'),
            value: settings.showVerseNumbers,
            onChanged: controller.setShowVerseNumbers,
          ),

          // The Thema picker is gone while the app is light-only. Offering a
          // Donker option that renders near-black text on a near-black
          // background is what got 1.0 (7) rejected under guideline 4; a
          // control that produces an unreadable screen is worse than no
          // control. See the note in main.dart for what has to change before
          // it comes back.

          const SizedBox(height: 24),
          const SectionHeader(eyebrow: 'Herinnering', title: 'Dagelijks lezen'),
          const SizedBox(height: 8),
          _ReminderTile(settings: settings),

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
                        await ref.read(contentCacheProvider)?.clear();
                        await _refreshCacheSize();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cache geleegd')),
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

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({required this.settings});

  final ReadingSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time = settings.dailyReminderTime;

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
                  },
                  child: const Text('Uitzetten'),
                ),
              const Icon(Icons.chevron_right, size: 18, color: AppTheme.inkMuted),
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} kB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
