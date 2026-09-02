import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../bible/domain/bible_models.dart';
import '../../bible/present/bible_providers.dart';
import '../../settings/data/reading_settings.dart';
import '../data/enrollment_models.dart';
import '../data/enrollment_repository.dart';
import '../data/study_models.dart';
import 'studies_providers.dart';

/// The three questions asked before a study starts: how often, how deep, and in
/// which translation.
///
/// Returns the enrollment when one was created or updated, or null when the
/// reader backed out. Nothing is written until they confirm.
Future<StudyEnrollment?> showStudySettingsSheet(
  BuildContext context,
  WidgetRef ref, {
  required CuratedStudy study,
  required StudyEnrollment? enrollment,
  required bool startAfterSave,
}) {
  return showModalBottomSheet<StudyEnrollment?>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.paperRaised,
    builder: (sheetContext) => _StudySettingsSheet(
      study: study,
      enrollment: enrollment,
      startAfterSave: startAfterSave,
    ),
  );
}

class _StudySettingsSheet extends ConsumerStatefulWidget {
  const _StudySettingsSheet({
    required this.study,
    required this.enrollment,
    required this.startAfterSave,
  });

  final CuratedStudy study;
  final StudyEnrollment? enrollment;
  final bool startAfterSave;

  @override
  ConsumerState<_StudySettingsSheet> createState() => _StudySettingsSheetState();
}

class _StudySettingsSheetState extends ConsumerState<_StudySettingsSheet> {
  late StudyRhythm _rhythm;
  late StudyDepth _depth;
  late String _translation;
  late List<int> _days;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final enrollment = widget.enrollment;
    final study = widget.study;

    // An existing enrollment wins; otherwise the study's own suggestion; and
    // only then the defaults. A reader who already chose is never re-asked.
    _rhythm = enrollment?.rhythm ?? StudyRhythm.fromId(study.suggestedRhythm);
    _depth = enrollment?.depth ?? StudyDepth.fromId(study.suggestedDepth);
    _translation =
        enrollment?.translation ??
        ref.read(readingSettingsProvider).lastVersionId;
    _days = enrollment != null && enrollment.reminderDays.isNotEmpty
        ? List<int>.from(enrollment.reminderDays)
        : const [1, 3, 5];
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final settings = EnrollmentSettings(
      rhythm: _rhythm,
      depth: _depth,
      translation: _translation,
      reminderDays: _days,
    );

    try {
      final repository = ref.read(enrollmentRepositoryProvider);
      final saved = widget.enrollment == null
          ? await repository.enrol(widget.study.id, settings)
          : await repository.updateSettings(widget.study.id, settings);

      // The translation the reader picked here is the one they mean generally.
      await ref.read(readingSettingsProvider.notifier).setLastVersion(_translation);
      ref.invalidate(studyEnrollmentsProvider);

      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on EnrollmentException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pop();
        context.push('/login');
        return;
      }
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final versions = ref.watch(bibleVersionsProvider);
    final enrolled = widget.enrollment != null;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Eyebrow(enrolled ? 'Je instellingen' : 'Stel je studie in'),
            const SizedBox(height: 6),
            Text(widget.study.title, style: AppTheme.displaySmall),
            const SizedBox(height: 20),

            Text('Studieritme', style: AppTheme.bodyStrong),
            const SizedBox(height: 8),
            for (final rhythm in StudyRhythm.values)
              _ChoiceRow(
                label: rhythm.label,
                description: rhythm.description,
                selected: _rhythm == rhythm,
                onTap: () => setState(() => _rhythm = rhythm),
              ),

            // Only "eigen dagen" has days to pick, so the toggles appear with it.
            if (_rhythm == StudyRhythm.ownDays) ...[
              const SizedBox(height: 10),
              _WeekdayPicker(
                days: _days,
                onChanged: (days) => setState(() => _days = days),
              ),
            ],

            const SizedBox(height: 20),
            Text('Type uitleg', style: AppTheme.bodyStrong),
            const SizedBox(height: 8),
            for (final depth in StudyDepth.values)
              _ChoiceRow(
                label: depth.label,
                description: depth.description,
                selected: _depth == depth,
                onTap: () => setState(() => _depth = depth),
              ),

            const SizedBox(height: 20),
            Text('Bijbelvertaling', style: AppTheme.bodyStrong),
            const SizedBox(height: 8),
            versions.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: AppLoader(size: 20),
              ),
              error: (_, _) => Text(
                'De vertalingen konden niet worden geladen. '
                'De studie begint in ${widget.study.startVersion}.',
                style: AppTheme.caption,
              ),
              data: (sources) => _TranslationPicker(
                sources: sources,
                selected: _translation,
                onChanged: (id) => setState(() => _translation = id),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: AppTheme.caption.copyWith(color: AppTheme.destructive),
              ),
            ],

            const SizedBox(height: 22),
            SiteButton(
              label: enrolled
                  ? 'Opslaan'
                  : widget.startAfterSave
                  ? 'Opslaan en starten'
                  : 'Opslaan',
              trailingIcon: enrolled ? null : Icons.arrow_forward,
              loading: _busy,
              onPressed: _busy ? null : _save,
            ),
            const SizedBox(height: 8),
            SiteOutlineButton(
              label: 'Annuleren',
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppTheme.tealTint : AppTheme.paper,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: selected ? AppTheme.teal : AppTheme.rule),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 18,
                  color: selected ? AppTheme.teal : AppTheme.inkMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppTheme.bodyStrong),
                      Text(description, style: AppTheme.caption),
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

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.days, required this.onChanged});

  /// `0` is Sunday, matching what the API stores.
  final List<int> days;
  final ValueChanged<List<int>> onChanged;

  static const _labels = <int, String>{
    1: 'ma',
    2: 'di',
    3: 'wo',
    4: 'do',
    5: 'vr',
    6: 'za',
    0: 'zo',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final entry in _labels.entries)
          FilterChip(
            label: Text(entry.value),
            selected: days.contains(entry.key),
            onSelected: (selected) {
              final next = List<int>.from(days);
              if (selected) {
                next.add(entry.key);
              } else {
                next.remove(entry.key);
              }
              next.sort();
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class _TranslationPicker extends StatefulWidget {
  const _TranslationPicker({
    required this.sources,
    required this.selected,
    required this.onChanged,
  });

  final List<BibleSource> sources;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  State<_TranslationPicker> createState() => _TranslationPickerState();
}

class _TranslationPickerState extends State<_TranslationPicker> {
  late bool _otherExpanded;

  @override
  void initState() {
    super.initState();
    // Start expanded when the reader's own choice lives in this section —
    // their pick should never be hidden from them.
    _otherExpanded = widget.sources.any(
      (s) => s.language != 'nl' && s.id == widget.selected,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Dutch first: this is a Dutch app, and the other languages are the
    // exception a reader goes looking for.
    final dutch = widget.sources.where((s) => s.language == 'nl').toList(growable: false);
    final other = widget.sources.where((s) => s.language != 'nl').toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RuleGrid(
          children: [
            for (final source in dutch) _translationTile(source),
          ],
        ),
        if (other.isNotEmpty) ...[
          const SizedBox(height: 12),
          RuleGrid(
            children: [
              RuleListTile(
                showRule: _otherExpanded,
                onTap: () => setState(() => _otherExpanded = !_otherExpanded),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Overige vertalingen', style: AppTheme.metaLabel),
                    ),
                    AnimatedRotation(
                      turns: _otherExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(Icons.keyboard_arrow_down, size: 20),
                    ),
                  ],
                ),
              ),
              if (_otherExpanded)
                for (final source in other) _translationTile(source),
            ],
          ),
        ],
      ],
    );
  }

  Widget _translationTile(BibleSource source) {
    final isSelected = source.id == widget.selected;
    return RuleListTile(
      onTap: () => widget.onChanged(source.id),
      child: Row(
        children: [
          Expanded(
            child: Text(source.name, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Icon(
            isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: isSelected ? AppTheme.teal : Theme.of(context).colorScheme.outline,
          ),
        ],
      ),
    );
  }
}
