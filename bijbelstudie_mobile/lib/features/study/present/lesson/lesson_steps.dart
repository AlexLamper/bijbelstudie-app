import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../../core/ui/skeleton.dart';
import '../../../bible/domain/bible_models.dart';
import '../../../bible/present/bible_providers.dart';
import '../../../settings/data/reading_settings.dart';
import '../../data/lesson_repository.dart';
import '../../domain/lesson_models.dart';

/// Step 1 - the written introduction.
///
/// Only reached when the study has authored prose for this lesson; the server
/// leaves `intro` out of the step list otherwise, so there is no empty state.
class LessonIntroStep extends StatelessWidget {
  const LessonIntroStep({super.key, required this.lesson});

  final LessonPayload lesson;

  @override
  Widget build(BuildContext context) {
    final intro = lesson.content.intro;
    if (intro == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Eyebrow(lesson.title),
        const SizedBox(height: 10),
        Text(intro.headline, style: AppTheme.displayMedium),
        const SizedBox(height: 16),
        for (final paragraph in intro.body)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(paragraph, style: AppTheme.bodyLead),
          ),
        if (intro.watchFor.isNotEmpty) ...[
          const SizedBox(height: 6),
          AppCard(
            color: AppTheme.tealTint,
            borderColor: AppTheme.teal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 15,
                      color: AppTheme.tealStrong,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Let hier op',
                      style: AppTheme.bodyStrong.copyWith(
                        color: AppTheme.tealStrong,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final point in intro.watchFor)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('•  $point', style: AppTheme.bodyMuted),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Step 2 - the passage itself.
///
/// Shows only the verses this lesson covers. The chapter comes from the same
/// cached repository the reader uses, so a chapter already read offline needs
/// no network here either.
class LessonWordStep extends ConsumerWidget {
  const LessonWordStep({
    super.key,
    required this.lesson,
    required this.translation,
    required this.onTranslationChanged,
  });

  final LessonPayload lesson;
  final String translation;
  final ValueChanged<String> onTranslationChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passage = lesson.passage;
    final chapter = ref.watch(
      chapterContentProvider(
        ChapterRef(translation, passage.book, passage.chapter),
      ),
    );
    final settings = ref.watch(readingSettingsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const Eyebrow('Lees eerst het bijbelgedeelte'),
        const SizedBox(height: 8),
        Text(passage.reference, style: AppTheme.displaySmall),
        if (lesson.content.readingCue != null) ...[
          const SizedBox(height: 10),
          Text(lesson.content.readingCue!, style: AppTheme.bodyMuted),
        ],
        const SizedBox(height: 14),
        _TranslationRow(
          translations: lesson.translations,
          selected: translation,
          onChanged: onTranslationChanged,
        ),
        const SizedBox(height: 16),
        chapter.when(
          loading: () => const SkeletonText(lines: 8, lineHeight: 14, gap: 12),
          error: (_, _) => AppEmptyState(
            icon: Icons.wifi_off_outlined,
            title: 'Tekst niet geladen',
            description: 'Controleer je verbinding en probeer het opnieuw.',
            action: SiteButton(
              label: 'Opnieuw proberen',
              expand: false,
              onPressed: () => ref.invalidate(
                chapterContentProvider(
                  ChapterRef(translation, passage.book, passage.chapter),
                ),
              ),
            ),
          ),
          data: (content) {
            final verses = content.verses
                .where((verse) => passage.includes(verse.number))
                .toList(growable: false);

            if (verses.isEmpty) {
              return const AppEmptyState(
                icon: Icons.menu_book_outlined,
                title: 'Geen tekst',
                description:
                    'Dit gedeelte is niet beschikbaar in deze vertaling.',
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final verse in verses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _VerseText(verse: verse, settings: settings),
                  ),
                const SizedBox(height: 10),
                Text(content.attribution, style: AppTheme.metaLabel),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _VerseText extends StatelessWidget {
  const _VerseText({required this.verse, required this.settings});

  final Verse verse;
  final ReadingSettings settings;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: AppTheme.serifFontName,
          fontSize: settings.fontSize.points,
          height: settings.lineHeight.factor,
          letterSpacing: settings.letterSpacing.points,
          color: AppTheme.ink,
        ),
        children: [
          if (settings.showVerseNumbers)
            TextSpan(
              text: '${verse.number} ',
              style: TextStyle(
                fontFamily: AppTheme.sansFontName,
                fontSize: settings.fontSize.points * 0.62,
                fontWeight: FontWeight.w600,
                color: AppTheme.teal,
              ),
            ),
          TextSpan(text: verse.text),
        ],
      ),
    );
  }
}

class _TranslationRow extends StatelessWidget {
  const _TranslationRow({
    required this.translations,
    required this.selected,
    required this.onChanged,
  });

  final List<LessonTranslation> translations;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (translations.isEmpty) return const SizedBox.shrink();

    // Dutch first, as everywhere else in the app.
    final ordered = [
      ...translations.where((t) => t.isDutch),
      ...translations.where((t) => !t.isDutch),
    ];

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ordered.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final translation = ordered[index];
          return ChoiceChip(
            label: Text(translation.name),
            selected: translation.id == selected,
            onSelected: (_) => onChanged(translation.id),
          );
        },
      ),
    );
  }
}

/// Step 4 - the reflection.
///
/// Autosaves as the reader types, because the alternative is a Save button
/// nobody presses and an answer lost when the phone rings.
class LessonReflectionStep extends ConsumerStatefulWidget {
  const LessonReflectionStep({
    super.key,
    required this.lesson,
    required this.initialText,
    required this.onChanged,
  });

  final LessonPayload lesson;
  final String initialText;

  /// Reports every keystroke up to the shell so the completing write carries
  /// the latest text even if the debounce has not fired yet.
  final ValueChanged<String> onChanged;

  @override
  ConsumerState<LessonReflectionStep> createState() =>
      _LessonReflectionStepState();
}

class _LessonReflectionStepState extends ConsumerState<LessonReflectionStep> {
  static const _autosaveDelay = Duration(milliseconds: 1500);
  static const _maxChars = 8000;

  late final TextEditingController _controller;
  Timer? _debounce;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Flush on the way out: leaving the step is exactly when an unsaved
    // keystroke would otherwise be lost.
    _save(_controller.text);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    widget.onChanged(text);
    setState(() => _saved = false);
    _debounce?.cancel();
    _debounce = Timer(_autosaveDelay, () => _save(text));
  }

  void _save(String text) {
    final lesson = widget.lesson;
    if (mounted) setState(() => _saving = true);

    ref
        .read(lessonRepositoryProvider)
        .patch(lesson.studyId, lesson.day, reflectionText: text)
        .then((_) {
          if (!mounted) return;
          setState(() {
            _saving = false;
            _saved = true;
          });
        })
        .onError((_, _) {
          if (!mounted) return;
          setState(() => _saving = false);
        });
  }

  @override
  Widget build(BuildContext context) {
    final reflection = widget.lesson.content.reflection;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const Eyebrow('Reflectie'),
        const SizedBox(height: 10),
        Text(reflection.question, style: AppTheme.displaySmall),
        if (reflection.prompts.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (final prompt in reflection.prompts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 5, color: AppTheme.teal),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(prompt, style: AppTheme.bodyMuted)),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          maxLines: 10,
          minLines: 6,
          maxLength: _maxChars,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            hintText: reflection.placeholder ?? 'Schrijf je antwoord op...',
            alignLabelWithHint: true,
          ),
          onChanged: _onChanged,
        ),
        Row(
          children: [
            if (_saving)
              Text('Opslaan...', style: AppTheme.metaLabel)
            else if (_saved)
              Row(
                children: [
                  Icon(Icons.check, size: 12, color: AppTheme.positive),
                  const SizedBox(width: 4),
                  Text(
                    'Bewaard',
                    style: AppTheme.metaLabel.copyWith(
                      color: AppTheme.positive,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Als je de les afrondt wordt dit bewaard als notitie, '
          'terug te vinden bij Notities.',
          style: AppTheme.caption,
        ),
      ],
    );
  }
}
