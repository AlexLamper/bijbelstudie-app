import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../bible/present/bible_providers.dart';
import '../../../bible/present/reader_settings_sheet.dart';
import '../../../studies/present/study_settings_sheet.dart';
import '../../domain/lesson_models.dart';

/// The settings a reader can change without leaving the lesson.
///
/// The study flow is a full-screen route outside the tab shell, so nothing the
/// rest of the app offers for this was reachable from it: the translation
/// could only be changed from the chips on Het Woord - invisible from every
/// other step - and the type controls not at all, because they live on the
/// reader bar and on Instellingen, both of which are behind the X. A reader
/// who wanted larger text had to abandon the lesson to get it.
///
/// Three sections, and the split between them is real rather than cosmetic:
///
///  * **Studievertaling** changes the enrollment itself - the same setting the
///    startup sheet ([showStudySettingsSheet]) collects, reusing its
///    [TranslationPicker] and writing through the same
///    [EnrollmentRepository.updateSettings] call, so a reader who picked the
///    wrong translation at the start is never stuck with it.
///  * **Vertaling** is scoped to this lesson only. It writes `viewTranslation`,
///    which the server stores per lesson, and deliberately does not touch the
///    enrollment's own translation - picking up NBG51 to compare one passage
///    must not silently re-set the whole study.
///  * **Weergave** is global, exactly as it is everywhere else. The same
///    [ReaderTypographyControls] the reader bar shows, writing straight
///    through to [ReadingSettingsController].
Future<void> showLessonSettingsSheet(
  BuildContext context, {
  required LessonPayload lesson,
  required String translation,
  required ValueChanged<String> onTranslationChanged,
  required String studyTranslation,
  required ValueChanged<String> onStudyTranslationChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusLg),
      ),
    ),
    builder: (_) => _LessonSettingsSheet(
      lesson: lesson,
      translation: translation,
      onTranslationChanged: onTranslationChanged,
      studyTranslation: studyTranslation,
      onStudyTranslationChanged: onStudyTranslationChanged,
    ),
  );
}

class _LessonSettingsSheet extends ConsumerStatefulWidget {
  const _LessonSettingsSheet({
    required this.lesson,
    required this.translation,
    required this.onTranslationChanged,
    required this.studyTranslation,
    required this.onStudyTranslationChanged,
  });

  final LessonPayload lesson;
  final String translation;
  final ValueChanged<String> onTranslationChanged;
  final String studyTranslation;
  final ValueChanged<String> onStudyTranslationChanged;

  @override
  ConsumerState<_LessonSettingsSheet> createState() =>
      _LessonSettingsSheetState();
}

class _LessonSettingsSheetState extends ConsumerState<_LessonSettingsSheet> {
  /// Held locally so the chips answer the tap immediately. The lesson shell
  /// owns the real value and rebuilds behind the sheet; without this the
  /// selection would only move once that rebuild reached a sheet that is not
  /// part of its subtree, which it never does.
  late String _translation = widget.translation;

  /// Same reasoning as [_translation], for the study-wide pick.
  late String _studyTranslation = widget.studyTranslation;

  void _select(String id) {
    if (id == _translation) return;
    setState(() => _translation = id);
    widget.onTranslationChanged(id);
  }

  void _selectStudy(String id) {
    if (id == _studyTranslation) return;
    setState(() => _studyTranslation = id);
    widget.onStudyTranslationChanged(id);
  }

  @override
  Widget build(BuildContext context) {
    // Dutch first, as everywhere else in the app.
    final translations = [
      ...widget.lesson.translations.where((t) => t.isDutch),
      ...widget.lesson.translations.where((t) => !t.isDutch),
    ];

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Eyebrow('Instellingen'),
              ),
            ),
            const RuleLine(),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                shrinkWrap: true,
                children: [
                  Text('Studievertaling', style: AppTheme.bodyStrong),
                  const SizedBox(height: 4),
                  Text(
                    'Geldt voor de hele studie, vanaf nu.',
                    style: AppTheme.caption,
                  ),
                  const SizedBox(height: 10),
                  Consumer(
                    builder: (context, ref, _) {
                      final versions = ref.watch(bibleVersionsProvider);
                      return versions.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: AppLoader(size: 20),
                        ),
                        error: (_, _) => Text(
                          'De vertalingen konden niet worden geladen.',
                          style: AppTheme.caption,
                        ),
                        data: (sources) => TranslationPicker(
                          sources: sources,
                          selected: _studyTranslation,
                          onChanged: _selectStudy,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const RuleLine(),
                  const SizedBox(height: 20),
                  if (translations.isNotEmpty) ...[
                    Text('Vertaling', style: AppTheme.bodyStrong),
                    const SizedBox(height: 4),
                    Text(
                      'Geldt voor deze les. De studie zelf houdt de vertaling '
                      'waarmee je bent begonnen.',
                      style: AppTheme.caption,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final translation in translations)
                          ChoiceChip(
                            label: Text(translation.name),
                            selected: translation.id == _translation,
                            onSelected: (_) => _select(translation.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const RuleLine(),
                    const SizedBox(height: 20),
                  ],
                  Text('Weergave', style: AppTheme.bodyStrong),
                  const SizedBox(height: 12),
                  const ReaderTypographyControls(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
