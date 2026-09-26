import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/bible_books.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/server_image.dart';
import '../../studies/data/study_models.dart';
import '../../studies/present/studies_providers.dart';
import '../../studies/present/study_banner.dart';
import '../data/dashboard_models.dart';
import '../data/resume_link.dart';
import '../data/resume_models.dart';
import 'resume_providers.dart';

/// "Waar je gebleven was": the one small card that says where the reader is,
/// first on the Start tab.
///
/// Fed by the server's `resume` answer, so web and app agree on the lesson or
/// chapter. A server that predates `resume` gets [buildLocalResume] instead:
/// the most recently active unfinished study (`continueStudyProvider`), else
/// the last chapter read, else the start prompt.
class ContinueStudyCard extends ConsumerWidget {
  const ContinueStudyCard({
    super.key,
    this.resume,
    this.lastRead,
    this.readChapters = const {},
    this.onOpen,
  });

  /// The server's answer; null from an older server.
  final DashboardResume? resume;

  /// The reader's most recent chapter, for the fallback. Null for a new account.
  final LastRead? lastRead;

  /// For the fallback chapter's "12 van 50 hoofdstukken".
  final Map<String, List<int>> readChapters;

  /// Overrides navigation (tests). Defaults to [openResumeHref].
  final void Function(String href)? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = watchResume(
      ref,
      server: resume,
      lastRead: lastRead,
      readChapters: readChapters,
    );
    final catalogue = ref.watch(curatedStudiesProvider).value ?? const <CuratedStudy>[];

    Widget? coverFor(ResumeItem item) {
      if (item.kind != ResumeKind.study) return null;
      for (final study in catalogue) {
        if (study.id == item.studyId) return StudyBanner(study: study);
      }
      final url = item.imageUrl;
      if (url == null) return null;
      return ServerImage(imagePath: url, fallback: const _PaintedCover());
    }

    return ResumeCardView(
      resume: shown,
      cover: coverFor(shown.primary),
      onOpen: onOpen ?? (href) => openResumeHref(context, ref, href),
    );
  }
}

/// The card itself, free of providers so it can be tested on fixed data.
///
/// Deliberately the original compact card: a 56px cover (or icon chip), the
/// "Waar je gebleven was" eyebrow, a title and one muted line, a thin lesson
/// bar for a study, and the whole card tappable. No step bar, schedule chip,
/// "Vandaag gedaan" line or list of other studies - the owner wants this card
/// minimal. The data is the server's `resume.primary`, so web and app agree on
/// which lesson or chapter it names.
class ResumeCardView extends StatelessWidget {
  const ResumeCardView({
    super.key,
    required this.resume,
    required this.onOpen,
    this.cover,
  });

  final DashboardResume resume;
  final void Function(String href) onOpen;

  /// The study's banner, square-cropped. Null for chapters and starts.
  final Widget? cover;

  /// Where the start state opens: the first chapter of the start book, as the
  /// card always did for a reader without progress.
  static final String startHref = Uri(
    path: '/lezen',
    queryParameters: {
      'book': BibleBooks.startBook,
      'chapter': '1',
      'version': 'statenvertaling',
    },
  ).toString();

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final item = resume.primary;
    switch (item.kind) {
      case ResumeKind.study:
        return _study(context, item);
      case ResumeKind.chapter:
        final target = resumeTargetFor(item.href);
        final chapter = target is ResumeChapter ? target : null;
        return _row(
          context,
          icon: Icons.menu_book_outlined,
          eyebrow: 'Waar je gebleven was',
          title: chapter == null ? item.title : BibleBooks.toCanonical(chapter.book),
          line: chapter == null
              ? (item.subtitle ?? '')
              : chapter.version == null
              ? 'Hoofdstuk ${chapter.chapter}'
              : 'Hoofdstuk ${chapter.chapter} · ${chapter.version}',
          onTap: () => onOpen(item.href),
        );
      case ResumeKind.start:
        return _row(
          context,
          icon: Icons.auto_stories,
          eyebrow: 'Begin met lezen',
          title: 'Start je bijbelstudie',
          line: 'Lees dag voor dag door de Bijbel',
          onTap: () => onOpen(startHref),
        );
      case ResumeKind.other:
        // A kind a newer server sends that this build does not know.
        return _row(
          context,
          icon: Icons.menu_book_outlined,
          eyebrow: 'Waar je gebleven was',
          title: item.title,
          line: item.subtitle ?? '',
          onTap: () => onOpen(item.href),
        );
    }
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String eyebrow,
    required String title,
    required String line,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconChip(icon: icon, size: 56, iconSize: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eyebrow, style: AppTheme.metaLabel.copyWith(color: AppTheme.teal)),
                const SizedBox(height: 3),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyStrong.copyWith(fontSize: 14, color: scheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyMuted.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: AppTheme.inkMuted),
        ],
      ),
    );
  }

  Widget _study(BuildContext context, ResumeItem item) {
    final scheme = Theme.of(context).colorScheme;
    final progress = item.progress;
    // "Les 6 van 50 · Gerechtvaardigd door geloof" -> "Les 6 van 50".
    final lessonLine = item.subtitle?.split(' · ').first.trim();

    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => onOpen(item.href),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: SizedBox.square(dimension: 56, child: cover ?? const _PaintedCover()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Waar je gebleven was',
                      style: AppTheme.metaLabel.copyWith(color: AppTheme.teal),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyStrong.copyWith(fontSize: 14, color: scheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lessonLine == null || lessonLine.isEmpty ? 'Verdergaan' : lessonLine,
                      style: AppTheme.bodyMuted.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (progress != null && progress.total > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 5,
                backgroundColor: scheme.outline,
                valueColor: AlwaysStoppedAnimation(AppTheme.teal),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Verder met de les',
                style: AppTheme.caption.copyWith(color: AppTheme.teal, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 3),
              Icon(Icons.arrow_forward, size: 13, color: AppTheme.teal),
            ],
          ),
        ],
      ),
    );
  }
}

/// The banner ground without a picture, for a cover URL that fails to load.
class _PaintedCover extends StatelessWidget {
  const _PaintedCover();

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.tealStrong, AppTheme.bannerEnd],
        ),
      ),
    );
  }
}
