import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible/present/bible_providers.dart';
import '../../notes/domain/note_models.dart';
import '../../notes/present/notes_providers.dart';
import '../../studies/present/study_banner.dart';
import '../data/profile_model.dart';
import '../domain/profile_activity.dart';
import '../domain/profile_stats.dart';
import 'profile_activity_provider.dart';

/// The filter bar plus the stack of activity cards.
class ProfileActivityFeed extends ConsumerWidget {
  const ProfileActivityFeed({super.key, required this.profile});

  final ProfileModel profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(profileActivityFilterProvider);
    final entries = ref
        .watch(profileActivityProvider)
        .where((entry) => filter.matches(entry.kind))
        .toList(growable: false);

    // The feed is folded together from two list requests; while either is in
    // flight the section stands in rather than claiming the account is empty.
    final loading =
        ref.watch(notesListProvider).isLoading ||
        ref.watch(highlightsListProvider).isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FilterBar(),
        const SizedBox(height: 14),
        if (loading && entries.isEmpty)
          const _FeedSkeleton()
        else if (entries.isEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconChip(icon: filter.icon, color: AppTheme.inkMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        filter.emptyTitle,
                        style: AppTheme.bodyStrong,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(filter.emptyLine, style: AppTheme.bodyMuted),
              ],
            ),
          )
        else
          for (final entry in entries) ...[
            _ActivityCard(entry: entry, profile: profile),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

/// Horizontally scrolling pills, each with a leading icon.
class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(profileActivityFilterProvider);

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: ProfileActivityFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = ProfileActivityFilter.values[index];
          final isSelected = filter == selected;
          final scheme = Theme.of(context).colorScheme;

          return Material(
            color: isSelected ? AppTheme.teal : scheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              onTap: () => ref
                  .read(profileActivityFilterProvider.notifier)
                  .select(filter),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  border: Border.all(
                    color: isSelected ? AppTheme.teal : scheme.outline,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      filter.icon,
                      size: 14,
                      color: isSelected ? Colors.white : AppTheme.inkMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      filter.label,
                      style: AppTheme.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : AppTheme.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ActivityCard extends ConsumerWidget {
  const _ActivityCard({required this.entry, required this.profile});

  final ProfileActivity entry;
  final ProfileModel profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetaRow(entry: entry, profile: profile),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                _ActivityBody(entry: entry),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _InteractionRow(entry: entry),
        ],
      ),
    );
  }
}

/// Avatar, name, what happened, when, and who can see it.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.entry, required this.profile});

  final ProfileActivity entry;
  final ProfileModel profile;

  @override
  Widget build(BuildContext context) {
    final name = profile.name.trim().isEmpty ? 'Jij' : profile.name.trim();
    final at = entry.at;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileAvatar(profile: profile, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: name,
                      style: AppTheme.bodyStrong.copyWith(fontSize: 13),
                    ),
                    TextSpan(
                      text: ' ${entry.actionLabel}',
                      style: AppTheme.bodyMuted.copyWith(fontSize: 13),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  if (at != null) ...[
                    Text(
                      formatActivityTimestamp(at),
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.inkFaint,
                      ),
                    ),
                    Text(
                      '  ·  ',
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.inkFaint,
                      ),
                    ),
                  ],
                  Icon(Icons.lock_outline, size: 11, color: AppTheme.inkFaint),
                  const SizedBox(width: 4),
                  // Nothing in this app is published anywhere, so the privacy
                  // mark is a statement of fact, not a setting.
                  Text(
                    'Alleen jij',
                    style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
                  ),
                ],
              ),
            ],
          ),
        ),
        _OverflowMenu(entry: entry),
      ],
    );
  }
}

class _ActivityBody extends StatelessWidget {
  const _ActivityBody({required this.entry});

  final ProfileActivity entry;

  @override
  Widget build(BuildContext context) {
    return switch (entry.kind) {
      ProfileActivityKind.highlight => _VerseBody(
        note: entry.note!,
        highlighted: true,
      ),
      ProfileActivityKind.note => _VerseBody(
        note: entry.note!,
        highlighted: false,
      ),
      ProfileActivityKind.study => _StudyBody(entry: entry),
      ProfileActivityKind.badge => _BadgeBody(badge: entry.badge!),
    };
  }
}

/// The scripture itself - tinted with the highlight colour for a marking,
/// quoted behind a rule for a note.
class _VerseBody extends StatelessWidget {
  const _VerseBody({required this.note, required this.highlighted});

  final StudyNote note;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final swatch = note.color.swatch;
    final verse = note.verseText.trim();
    final body = note.noteText.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          note.reference,
          style: AppTheme.caption.copyWith(
            color: AppTheme.teal,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (verse.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: highlighted
                  ? swatch.withValues(alpha: 0.35)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border(
                left: BorderSide(
                  color: highlighted ? swatch : AppTheme.rule,
                  width: 3,
                ),
              ),
            ),
            child: Text(
              verse,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        if (body.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            body,
            style: AppTheme.bodyMuted,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// The study banner with its progress track underneath.
class _StudyBody extends StatelessWidget {
  const _StudyBody({required this.entry});

  final ProfileActivity entry;

  @override
  Widget build(BuildContext context) {
    final study = entry.study!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: AspectRatio(
            aspectRatio: 16 / 6,
            child: StudyBanner(study: study),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          study.title,
          style: AppTheme.bodyStrong,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        SiteProgressBar(value: entry.studyProgress),
        const SizedBox(height: 6),
        Text(
          entry.lessonsTotal == 0
              ? 'Nog geen lessen'
              : '${entry.lessonsDone} van ${entry.lessonsTotal} lessen afgerond',
          style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
        ),
      ],
    );
  }
}

class _BadgeBody extends StatelessWidget {
  const _BadgeBody({required this.badge});

  final BadgeProgress badge;

  @override
  Widget build(BuildContext context) {
    final tint = badge.definition.tone.color;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: tint.withValues(alpha: 0.35)),
          ),
          child: Icon(badge.definition.icon, size: 22, color: tint),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(badge.definition.label, style: AppTheme.bodyStrong),
              const SizedBox(height: 2),
              Text(badge.definition.description, style: AppTheme.bodyMuted),
            ],
          ),
        ),
      ],
    );
  }
}

/// Heart and comment are marks, not buttons.
///
/// Nothing in this app can like or comment on anything - there is no endpoint
/// and no audience - so they are drawn without an `onTap` rather than as
/// controls that would do nothing when pressed.
class _InteractionRow extends StatelessWidget {
  const _InteractionRow({required this.entry});

  final ProfileActivity entry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.favorite_border, size: 17, color: AppTheme.inkFaint),
        const SizedBox(width: 18),
        Icon(Icons.mode_comment_outlined, size: 16, color: AppTheme.inkFaint),
        const Spacer(),
        if (entry.kind == ProfileActivityKind.badge)
          Text(
            'Behaald',
            style: AppTheme.caption.copyWith(color: AppTheme.positive),
          ),
        const SizedBox(width: 8),
      ],
    );
  }
}

/// The three-dot menu. Only listed where a real action exists.
class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({required this.entry});

  final ProfileActivity entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = entry.note;
    final study = entry.study;
    if (note == null && study == null) {
      // A badge has nowhere to go and nothing to share as text.
      return const SizedBox(width: 40, height: 24);
    }

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, size: 20, color: AppTheme.inkMuted),
      tooltip: 'Meer',
      position: PopupMenuPosition.under,
      onSelected: (value) {
        switch (value) {
          case 'read':
            ref
                .read(readerLocationProvider.notifier)
                .openChapter(book: note!.book, chapter: note.chapter);
            context.go('/read');
          case 'share':
            final parts = [
              note!.verseText.trim(),
              note.noteText.trim(),
              note.reference,
            ].where((part) => part.isNotEmpty);
            Share.share(parts.join('\n\n'), subject: note.reference);
          case 'study':
            context.push('/studies/${study!.id}');
        }
      },
      itemBuilder: (context) => [
        if (note != null) ...[
          const PopupMenuItem(value: 'read', child: Text('Openen in de lezer')),
          const PopupMenuItem(value: 'share', child: Text('Delen')),
        ],
        if (study != null)
          const PopupMenuItem(
            value: 'study',
            child: Text('Bijbelstudie openen'),
          ),
      ],
    );
  }
}

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 2; i++) ...[
          const SkeletonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Skeleton.circle(34),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Skeleton(height: 12, width: 170),
                          SizedBox(height: 7),
                          Skeleton(height: 9, width: 110),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),
                SkeletonText(lines: 3, lineHeight: 11),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// The reader's picture, or the first letter of their name when there is none.
///
/// `GET /me` returns `image` for accounts that signed in with Google or Apple;
/// there is no upload endpoint, so an account without one keeps the initial.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.profile, this.size = 84});

  final ProfileModel profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final name = profile.name.trim();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final image = profile.image?.trim();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.tealTint,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.rule),
      ),
      child: image == null || image.isEmpty
          ? Text(
              initial,
              style: AppTheme.displayTitle.copyWith(
                color: AppTheme.tealStrong,
                fontSize: size * 0.4,
              ),
            )
          : Image.network(
              image,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) => Text(
                initial,
                style: AppTheme.displayTitle.copyWith(
                  color: AppTheme.tealStrong,
                  fontSize: size * 0.4,
                ),
              ),
            ),
    );
  }
}
