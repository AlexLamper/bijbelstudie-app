import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible/domain/bible_models.dart';
import '../../bible/present/bible_providers.dart';
import '../../settings/data/reading_settings.dart';
import '../data/study_models.dart';
import '../data/study_plan_store.dart';
import '../data/study_progress_repository.dart';
import 'studies_providers.dart';
import 'study_banner.dart';

/// `/studies/:id` - the screen that stands between a study card and the reader.
///
/// The website has no equivalent: `app/studies/page.tsx` writes the study into
/// `sessionStorage` and pushes straight to `/studie`, so pressing Start there
/// means landing in a chapter with no sense of what the study is or how long it
/// runs. This screen is where the study becomes concrete - what it covers,
/// every lesson in order, and the three choices that shape how it is read
/// (translation, commentary, cadence) - before the reader commits to it.
///
/// The chosen configuration and the lessons ticked off are kept by
/// [studyPlansProvider] on the device; completed lessons are additionally sent
/// to the existing `POST /api/v1/study-progress`, which is what the account's
/// XP and the website's "Voltooid" badge already read.
class StudyDetailScreen extends ConsumerStatefulWidget {
  const StudyDetailScreen({super.key, required this.studyId});

  final String studyId;

  @override
  ConsumerState<StudyDetailScreen> createState() => _StudyDetailScreenState();
}

class _StudyDetailScreenState extends ConsumerState<StudyDetailScreen> {
  /// Null until the reader touches a control; the stored plan, then the study's
  /// own default, answer for it up to that point. Kept as local overrides so
  /// the pickers respond instantly without a disk write per tap.
  String? _versionId;
  String? _commentaryId;
  StudyCadence? _cadence;

  StudyPlan? get _plan => ref.read(studyPlansProvider)[widget.studyId];

  String _effectiveVersion(CuratedStudy study) =>
      _versionId ?? _plan?.versionId ?? study.startVersion;

  String _effectiveCommentary() =>
      _commentaryId ??
      _plan?.commentaryId ??
      ref.read(readingSettingsProvider).lastCommentaryId;

  StudyCadence _effectiveCadence() =>
      _cadence ?? _plan?.cadence ?? StudyCadence.daily;

  Future<void> _saveConfig(CuratedStudy study) {
    return ref
        .read(studyPlansProvider.notifier)
        .saveConfig(
          studyId: study.id,
          versionId: _effectiveVersion(study),
          commentaryId: _effectiveCommentary(),
          cadence: _effectiveCadence(),
        );
  }

  /// Opens [lesson] in the reader with the configuration this screen holds.
  ///
  /// This is what Start used to do from the card, minus the guesswork: the
  /// translation is the one chosen here rather than the study's hardcoded
  /// `startVersion`, and the commentary pane opens on the chosen source.
  Future<void> _open(CuratedStudy study, StudyLesson lesson) async {
    final version = _effectiveVersion(study);
    final commentary = _effectiveCommentary();

    await ref
        .read(studyPlansProvider.notifier)
        .start(
          studyId: study.id,
          versionId: version,
          commentaryId: commentary,
          cadence: _effectiveCadence(),
        );
    await ref
        .read(readingSettingsProvider.notifier)
        .setLastCommentary(commentary);

    ref
        .read(readerLocationProvider.notifier)
        .openChapter(
          versionId: version,
          book: lesson.book,
          chapter: lesson.chapter,
        );

    if (!mounted) return;
    context.go('/study');
  }

  Future<void> _toggleLesson(
    CuratedStudy study,
    StudyLesson lesson,
    bool done,
  ) async {
    await ref
        .read(studyPlansProvider.notifier)
        .setLessonDone(
          studyId: study.id,
          day: lesson.day,
          done: done,
          versionId: _effectiveVersion(study),
          commentaryId: _effectiveCommentary(),
          cadence: _effectiveCadence(),
        );

    // The server has no "undo": `POST /api/v1/study-progress` only records. A
    // tick that is taken back stays taken back on this device, which is the
    // copy this screen renders from.
    if (!done) return;

    final bounds = lesson.verseBounds;
    await ref
        .read(studyProgressRepositoryProvider)
        .recordLesson(
          studyId: study.id,
          lessonDay: lesson.day,
          book: lesson.book,
          chapter: lesson.chapter,
          verseStart: bounds?.$1,
          verseEnd: bounds?.$2,
        );
    ref.invalidate(serverStudyLessonsProvider);
  }

  Future<void> _reset(CuratedStudy study) async {
    await ref.read(studyPlansProvider.notifier).reset(study.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voortgang op dit apparaat gewist.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final study = ref.watch(curatedStudyProvider(widget.studyId));

    // Both are read through `ref.read` by the effective-value helpers, which
    // does not subscribe. Watching them here is what makes the pickers show the
    // stored plan once SharedPreferences has answered, instead of sitting on
    // the study's defaults for the life of the screen.
    ref.watch(studyPlansProvider);
    ref.watch(readingSettingsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text(study.value?.title ?? 'Studie')),
      body: study.when(
        loading: () => const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: SkeletonCardColumn(count: 2),
        ),
        error: (error, _) => AppEmptyState(
          icon: Icons.wifi_off_outlined,
          title: 'Studie niet geladen',
          description: '$error',
        ),
        data: (data) => data == null
            ? const AppEmptyState(
                icon: Icons.search_off,
                title: 'Studie niet gevonden',
                description: 'Deze studie bestaat niet meer.',
              )
            : _Body(
                study: data,
                versionId: _effectiveVersion(data),
                commentaryId: _effectiveCommentary(),
                cadence: _effectiveCadence(),
                onVersion: (id) {
                  setState(() => _versionId = id);
                  _saveConfig(data);
                },
                onCommentary: (id) {
                  setState(() => _commentaryId = id);
                  _saveConfig(data);
                },
                onCadence: (value) {
                  setState(() => _cadence = value);
                  _saveConfig(data);
                },
                onOpen: (lesson) => _open(data, lesson),
                onToggle: (lesson, done) => _toggleLesson(data, lesson, done),
                onReset: () => _reset(data),
              ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.study,
    required this.versionId,
    required this.commentaryId,
    required this.cadence,
    required this.onVersion,
    required this.onCommentary,
    required this.onCadence,
    required this.onOpen,
    required this.onToggle,
    required this.onReset,
  });

  final CuratedStudy study;
  final String versionId;
  final String commentaryId;
  final StudyCadence cadence;
  final ValueChanged<String> onVersion;
  final ValueChanged<String> onCommentary;
  final ValueChanged<StudyCadence> onCadence;
  final ValueChanged<StudyLesson> onOpen;
  final void Function(StudyLesson lesson, bool done) onToggle;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final plans = ref.watch(studyPlansProvider);
    final serverLessons =
        ref.watch(serverStudyLessonsProvider).value ??
        const <String, Set<int>>{};
    final completed = mergedCompletedDays(
      studyId: study.id,
      plans: plans,
      serverLessons: serverLessons,
    );

    final total = study.lessonCount;
    final done = completed.length;
    final finished = total > 0 && done >= total;
    final started = plans[study.id]?.started ?? done > 0;
    final next = _nextLesson(completed);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(AppTheme.radiusMd),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 6,
                  child: StudyBanner(study: study),
                ),
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  SiteBadge.teal(study.type),
                  const SizedBox(width: 8),
                  if (finished)
                    SiteBadge.positive(
                      'Voltooid',
                      icon: Icons.check_circle,
                    )
                  else if (started)
                    SiteBadge.neutral('$done van $total lessen'),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                study.title,
                style: AppTheme.displayLarge.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: 6),
              Text(study.description, style: AppTheme.bodyLead),
              const SizedBox(height: 16),

              StatStrip(
                items: [
                  StatItem(
                    value: '$total',
                    label: total == 1 ? 'les' : 'lessen',
                    icon: Icons.list_alt_outlined,
                  ),
                  StatItem(
                    value: '${study.books.length}',
                    label: study.books.length == 1
                        ? 'bijbelboek'
                        : 'bijbelboeken',
                    icon: Icons.menu_book_outlined,
                  ),
                  StatItem(
                    value: '${study.estimatedMinutes}',
                    label: 'minuten totaal',
                    icon: Icons.schedule,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              const SectionHeader(
                eyebrow: 'Wat je gaat doen',
                title: 'Over deze studie',
              ),
              const SizedBox(height: 10),
              AppCard(
                radius: AppTheme.radiusMd,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AboutLine(
                      icon: Icons.explore_outlined,
                      text: study.typeSummary,
                    ),
                    const SizedBox(height: 10),
                    _AboutLine(
                      icon: Icons.menu_book_outlined,
                      text: 'Je leest ${_booksSentence(study.books)}.',
                    ),
                    const SizedBox(height: 10),
                    _AboutLine(
                      icon: Icons.help_outline,
                      text:
                          'Elke les geeft je een bijbelgedeelte en een vraag om '
                          'over door te denken. Je leest het gedeelte in de '
                          'app, met de uitleg ernaast.',
                    ),
                    const SizedBox(height: 10),
                    _AboutLine(
                      icon: Icons.check_circle_outline,
                      text:
                          'Vink een les af als je klaar bent. Je voortgang '
                          'blijft bewaard, ook als je de app sluit.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              const SectionHeader(
                eyebrow: 'Stel in',
                title: 'Hoe wil je deze studie doen?',
                description:
                    'Deze keuzes gelden voor deze studie en worden bewaard.',
              ),
              const SizedBox(height: 12),
              _SourcePicker(
                label: 'Vertaling',
                sources: ref.watch(bibleVersionsProvider),
                selectedId: versionId,
                fallbackLabel: versionId,
                onChanged: onVersion,
              ),
              const SizedBox(height: 14),
              _SourcePicker(
                label: 'Uitleg ernaast',
                sources: ref.watch(commentarySourcesProvider),
                selectedId: commentaryId,
                fallbackLabel: commentaryId,
                onChanged: onCommentary,
              ),
              const SizedBox(height: 14),
              Text(
                'Hoe vaak kom je terug?',
                style: AppTheme.bodyMuted.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in StudyCadence.values)
                    ChoiceChip(
                      label: Text(value.label),
                      selected: value == cadence,
                      onSelected: (_) => onCadence(value),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _cadenceSummary(cadence, total - done),
                style: AppTheme.caption,
              ),
              const SizedBox(height: 22),

              SectionHeader(
                eyebrow: 'Les voor les',
                title: total == 1 ? '1 les' : '$total lessen',
                description:
                    'Tik een les aan om hem te lezen, of vink hem af als je '
                    'klaar bent.',
              ),
              const SizedBox(height: 10),
              RuleGrid(
                children: [
                  for (final lesson in study.lessons)
                    _LessonTile(
                      lesson: lesson,
                      done: completed.contains(lesson.day),
                      isNext: next != null && next.day == lesson.day,
                      onOpen: () => onOpen(lesson),
                      onToggle: (value) => onToggle(lesson, value),
                    ),
                ],
              ),

              if (started) ...[
                const SizedBox(height: 14),
                Center(
                  child: TextButton(
                    onPressed: onReset,
                    child: const Text('Voortgang wissen'),
                  ),
                ),
              ],
            ],
          ),
        ),

        // The one action the whole screen builds towards, kept in reach no
        // matter how far down the lesson list the reader has scrolled.
        Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outline)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SiteButton(
                label: next == null
                    ? 'Geen lessen beschikbaar'
                    : finished
                    ? 'Opnieuw lezen vanaf les ${study.lessons.first.day}'
                    : started
                    ? 'Verder met les ${next.day}: ${next.title}'
                    : 'Start studie',
                trailingIcon: Icons.arrow_forward,
                onPressed: next == null ? null : () => onOpen(next),
              ),
            ),
          ),
        ),
      ],
    );
  }

  StudyLesson? _nextLesson(Set<int> completed) {
    for (final lesson in study.lessons) {
      if (!completed.contains(lesson.day)) return lesson;
    }
    return study.firstLesson;
  }
}

String _booksSentence(List<String> books) {
  if (books.isEmpty) return 'door de Bijbel';
  if (books.length == 1) return 'in ${books.first}';
  if (books.length == 2) return 'in ${books.first} en ${books.last}';
  return 'in ${books.sublist(0, books.length - 1).join(', ')} en ${books.last}';
}

/// Turns a cadence into the date it lands on, which is the question behind
/// "hoe vaak kom je terug" - a rhythm nobody can picture the end of is not a
/// plan.
String _cadenceSummary(StudyCadence cadence, int remaining) {
  if (remaining <= 0) return 'Je hebt alle lessen van deze studie gedaan.';
  final perWeek = cadence.lessonsPerWeek;
  if (perWeek == null) {
    return '${cadence.description} Nog $remaining '
        '${remaining == 1 ? 'les' : 'lessen'} te gaan.';
  }
  final days = (remaining / perWeek * 7).ceil();
  final finish = DateTime.now().add(Duration(days: days));
  return '${cadence.description} Klaar rond ${_formatDate(finish)}.';
}

const _months = [
  'januari',
  'februari',
  'maart',
  'april',
  'mei',
  'juni',
  'juli',
  'augustus',
  'september',
  'oktober',
  'november',
  'december',
];

String _formatDate(DateTime date) => '${date.day} ${_months[date.month - 1]}';

class _AboutLine extends StatelessWidget {
  const _AboutLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppTheme.teal),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppTheme.caption)),
      ],
    );
  }
}

/// A translation or commentary picker over the same providers the reader uses,
/// so the study opens on a source that actually exists on the server rather
/// than an id typed into a list here.
class _SourcePicker extends StatelessWidget {
  const _SourcePicker({
    required this.label,
    required this.sources,
    required this.selectedId,
    required this.fallbackLabel,
    required this.onChanged,
  });

  final String label;
  final AsyncValue<List<BibleSource>> sources;
  final String selectedId;
  final String fallbackLabel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final list = sources.value ?? const <BibleSource>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.bodyMuted.copyWith(fontSize: 12)),
        const SizedBox(height: 8),
        if (list.isEmpty)
          // Offline or still loading: name what the study will use rather than
          // showing an empty row the reader cannot act on.
          _MutedChip(label: fallbackLabel)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final source in list)
                ChoiceChip(
                  label: Text(source.name),
                  selected: source.id == selectedId,
                  onSelected: (_) => onChanged(source.id),
                ),
            ],
          ),
      ],
    );
  }
}

class _MutedChip extends StatelessWidget {
  const _MutedChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(label, style: AppTheme.caption),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({
    required this.lesson,
    required this.done,
    required this.isNext,
    required this.onOpen,
    required this.onToggle,
  });

  final StudyLesson lesson;
  final bool done;
  final bool isNext;
  final VoidCallback onOpen;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return RuleListTile(
      showRule: false,
      onTap: onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done
                  ? AppTheme.teal
                  : AppTheme.teal.withValues(alpha: isNext ? 0.20 : 0.10),
              shape: BoxShape.circle,
            ),
            child: done
                ? const Icon(Icons.check, size: 13, color: Colors.white)
                : Text(
                    '${lesson.day}',
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.teal,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lesson.title,
                  style: AppTheme.bodyStrong.copyWith(
                    fontSize: 13.5,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  lesson.reference,
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.teal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (lesson.focus.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(lesson.focus, style: AppTheme.caption),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'Les ${lesson.day} afvinken',
            child: Checkbox(
              value: done,
              visualDensity: VisualDensity.compact,
              onChanged: (value) => onToggle(value ?? false),
            ),
          ),
        ],
      ),
    );
  }
}
