import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../auth/present/auth_controller.dart';
import '../../notes/present/notes_providers.dart';
import '../../onboarding/present/tour_controller.dart';
import '../data/profile_model.dart';
import '../data/profile_repository.dart';
import '../domain/profile_stats.dart';
import 'profile_activity_feed.dart';
import 'profile_menu_sheet.dart';
import 'profile_provider.dart';
import 'profile_stats_provider.dart';

/// Profiel: who you are, what you have read, and what you have done with it.
///
/// The plain navigation this screen used to list lives in the hamburger sheet
/// now ([showProfileMenuSheet]); the screen itself carries the account's own
/// numbers - streak, books, notities, badges - and the activity they produced.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: profileAsync.when(
          loading: () => const _ProfileSkeleton(),
          error: (error, __) => _signedOut(error)
              // A dead session is not a network failure: "opnieuw proberen"
              // would just fail again, so offer the only thing that helps.
              ? AppEmptyState(
                  icon: Icons.lock_outline,
                  title: 'Je bent uitgelogd',
                  description:
                      'Log opnieuw in om je profiel en voortgang te zien.',
                  action: SiteOutlineButton(
                    label: 'Inloggen',
                    expand: false,
                    onPressed: () => context.go('/login'),
                  ),
                )
              : AppEmptyState(
                  icon: Icons.wifi_off_outlined,
                  title: 'Profiel niet geladen',
                  description:
                      'Controleer je verbinding en probeer het opnieuw.',
                  action: SiteOutlineButton(
                    label: 'Opnieuw proberen',
                    expand: false,
                    onPressed: () => ref.invalidate(profileProvider),
                  ),
                ),
          data: (profile) => _ProfileBody(profile: profile),
        ),
      ),
    );
  }

  /// True when the profile request came back as "no valid session" rather than
  /// as a transport failure.
  static bool _signedOut(Object error) =>
      error is DioException && error.response?.statusCode == 401;
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile});

  final ProfileModel profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        _HeaderBar(profile: profile),
        const SizedBox(height: 14),
        _ProfileHeader(profile: profile),

        const SizedBox(height: 22),
        const _QuickActions(),

        const SizedBox(height: 28),
        const SectionHeader(title: 'Badges'),
        const SizedBox(height: 12),
        const _BadgesCard(),

        const SizedBox(height: 28),
        const SectionHeader(title: 'Activiteit'),
        const SizedBox(height: 12),
        ProfileActivityFeed(profile: profile),

        const SizedBox(height: 20),
        Text(
          'De vertalingen en commentaren in deze app zijn publiek domein. De '
          'grondtekst komt van STEPBible (TAHOT/TAGNT) en is beschikbaar onder '
          'CC BY 4.0.',
          style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
        ),

        const SizedBox(height: 24),
        SiteOutlineButton(
          label: 'Uitloggen',
          icon: Icons.logout,
          onPressed: () async {
            await ref.read(authControllerProvider.notifier).logout();
            if (context.mounted) context.go('/login');
          },
        ),
        const SizedBox(height: 8),
        // Guideline 5.1.1(v): deletion must be reachable without leaving the
        // app, so it stays on the screen itself rather than in the menu sheet.
        TextButton(
          onPressed: () => _confirmDelete(context, ref),
          style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
          child: const Text('Account verwijderen'),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Account verwijderen'),
        content: const Text(
          'Je account, notities, markeringen, bladwijzers en leesgeschiedenis worden '
          'definitief verwijderd. Dit kan niet ongedaan worden gemaakt.\n\n'
          'Heb je een abonnement via de App Store? Zeg dat apart op in je '
          'Apple ID-instellingen - Apple staat niet toe dat een app dat voor je doet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
            child: const Text('Definitief verwijderen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(profileRepositoryProvider).deleteAccount();
      await ref.read(authControllerProvider.notifier).logout();
      if (context.mounted) context.go('/login');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verwijderen mislukt. Probeer het opnieuw.'),
        ),
      );
    }
  }
}

/// The top bar: the section label on the left, the two icons that lead
/// somewhere real on the right.
///
/// A scan / QR button belongs here in the layout being followed, but this app
/// has nothing to scan - no invite codes in the UI, no plan-sharing links - so
/// it is left out rather than shipped as a dead control.
class _HeaderBar extends ConsumerWidget {
  const _HeaderBar({required this.profile});

  final ProfileModel profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        const Expanded(child: Eyebrow('Profiel')),
        IconButton(
          tooltip: 'Instellingen',
          icon: const Icon(Icons.settings_outlined, size: 22),
          color: AppTheme.inkSoft,
          onPressed: () => context.push('/settings'),
        ),
        IconButton(
          tooltip: 'Menu',
          icon: const Icon(Icons.menu, size: 22),
          color: AppTheme.inkSoft,
          onPressed: () => showProfileMenuSheet(context, ref, profile),
        ),
      ],
    );
  }
}

/// Name and status pills on the left, the avatar on the right.
class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.profile});

  final ProfileModel profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = profile.name.trim().isEmpty
        ? 'Gebruiker'
        : profile.name.trim();
    final stats = ref.watch(profileStatsProvider).value;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: AppTheme.displayMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                profile.email,
                style: AppTheme.bodyMuted.copyWith(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (profile.isPro)
                    SiteBadge.positive(
                      profile.isProFromWeb ? 'Pro via web' : 'Pro actief',
                      icon: Icons.workspace_premium_outlined,
                    )
                  else
                    // Guideline 3.1.1: only a non-subscriber is offered the
                    // purchase route.
                    //
                    // The tour anchor sits on this pill alone. On the row that
                    // holds it - where it used to be - the spotlight also took
                    // in the streak badge beside it, so the step about Pro
                    // pointed at two unrelated things. The step is filtered out
                    // for a subscriber, so the branch that has no pill needs no
                    // anchor.
                    TourAnchor(
                      id: TourAnchorIds.profilePro,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusPill,
                        ),
                        onTap: () =>
                            context.push('/pro-intro?source=app_profile'),
                        child: SiteBadge.teal(
                          'Bekijk Pro',
                          icon: Icons.workspace_premium_outlined,
                        ),
                      ),
                    ),
                  if (stats != null)
                    SiteBadge.vermilion(
                      '${stats.streak} ${stats.streak == 1 ? 'dag' : 'dagen'} reeks',
                      icon: Icons.local_fire_department_outlined,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _AvatarWithEdit(profile: profile),
      ],
    );
  }
}

/// The avatar with its edit badge.
///
/// The badge carries a pencil rather than a camera on purpose: `PATCH /me`
/// takes a name and reading preferences and there is no image-upload endpoint
/// anywhere in `/api/v1`, so the control opens the profile edit that really
/// exists instead of a picker that could never save anything.
class _AvatarWithEdit extends ConsumerWidget {
  const _AvatarWithEdit({required this.profile});

  final ProfileModel profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        children: [
          ProfileAvatar(profile: profile, size: 84),
          Positioned(
            right: 0,
            bottom: 0,
            child: Material(
              color: AppTheme.teal,
              shape: CircleBorder(
                side: BorderSide(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => showProfileNameDialog(context, ref, profile),
                child: const SizedBox(
                  width: 30,
                  height: 30,
                  child: Icon(
                    Icons.edit_outlined,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of four compact cards, each to a destination or figure this app
/// really has.
///
/// Bladwijzers and Notities both land on `/notes`, which is where both lists
/// live; there is no route parameter to preselect a tab. The icons are kept
/// to the theme's neutral ink tones - no per-tile colour palette - so the row
/// reads as one restrained unit rather than a set of clashing chips.
class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarksProvider).value?.length;
    final stats = ref.watch(profileStatsProvider).value;

    // IntrinsicHeight, not `CrossAxisAlignment.stretch`: inside a ListView the
    // Row has no bounded height to stretch into, and the four cards still
    // have to end level even when one label wraps.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _QuickCard(
              icon: Icons.bookmark_border,
              label: 'Bladwijzers',
              value: bookmarks?.toString(),
              onTap: () => context.go('/notes'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickCard(
              icon: Icons.edit_note_outlined,
              label: 'Notities',
              value: stats?.notesCount.toString(),
              onTap: () => context.go('/notes'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickCard(
              icon: Icons.menu_book_outlined,
              label: 'Bijbelboeken',
              value: stats == null
                  ? null
                  : '${stats.booksRead}/${ProfileStats.canonBooks}',
              onTap: () => context.go('/dashboard'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickCard(
              icon: Icons.local_fire_department_outlined,
              label: 'Leesreeks',
              value: stats?.streak.toString(),
              onTap: () => context.go('/dashboard'),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Null while the figure has not loaded yet.
  final String? value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppTheme.inkSoft),
          const SizedBox(height: 6),
          Text(
            value ?? '-',
            style: AppTheme.statNumber.copyWith(
              fontSize: 15,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTheme.caption.copyWith(fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// The badge shelf: how many are unlocked, then the shelf itself.
class _BadgesCard extends ConsumerWidget {
  const _BadgesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(profileBadgesProvider);
    final unlocked = badges.where((badge) => badge.unlocked).length;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.teal.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.military_tech_outlined,
                    size: 20,
                    color: AppTheme.teal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Badges', style: AppTheme.metaLabel),
                      const SizedBox(height: 2),
                      Text(
                        badges.isEmpty
                            ? 'Nog niets te tonen'
                            : '$unlocked van ${badges.length} behaald',
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$unlocked',
                  style: AppTheme.statNumber.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (badges.isEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                'Zodra je voortgang is geladen, verschijnen je badges hier.',
                style: AppTheme.bodyMuted,
              ),
            )
          else
            SizedBox(
              height: 108,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 16),
                itemCount: badges.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) =>
                    _BadgeTile(badge: badges[index]),
              ),
            ),
        ],
      ),
    );
  }
}

/// One badge on the shelf, with the progress line underneath it.
class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge});

  final BadgeProgress badge;

  @override
  Widget build(BuildContext context) {
    final tint = badge.definition.tone.color;
    final earned = badge.unlocked;

    return Tooltip(
      message: badge.definition.description,
      child: SizedBox(
        width: 76,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: earned
                    ? tint.withValues(alpha: 0.14)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
                border: Border.all(
                  color: earned ? tint.withValues(alpha: 0.4) : AppTheme.rule,
                ),
              ),
              child: Icon(
                badge.definition.icon,
                size: 24,
                color: earned ? tint : AppTheme.inkFaint,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              badge.definition.label,
              style: AppTheme.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: earned ? null : AppTheme.inkMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            SiteProgressBar(
              value: badge.fraction,
              height: 3,
              color: earned ? tint : AppTheme.inkFaint,
            ),
            const SizedBox(height: 4),
            Text(
              badge.unlocked ? 'Behaald' : badge.progressLabel,
              style: AppTheme.caption.copyWith(
                fontSize: 10,
                color: AppTheme.inkFaint,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgesSkeleton extends StatelessWidget {
  const _BadgesSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonCard(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Skeleton.circle(40),
              SizedBox(width: 12),
              Expanded(child: Skeleton(height: 12, width: 100)),
            ],
          ),
          SizedBox(height: 18),
          Row(
            children: [
              Skeleton.circle(52),
              SizedBox(width: 12),
              Skeleton.circle(52),
              SizedBox(width: 12),
              Skeleton.circle(52),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        const Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(height: 22, width: 170),
                  SizedBox(height: 10),
                  Skeleton(height: 12, width: 190),
                  SizedBox(height: 14),
                  Skeleton(height: 22, width: 130, radius: 999),
                ],
              ),
            ),
            SizedBox(width: 16),
            Skeleton.circle(84),
          ],
        ),
        const SizedBox(height: 22),
        const Skeleton(height: 48, radius: 12),
        const SizedBox(height: 14),
        const Row(
          children: [
            Expanded(
              child: SkeletonCard(height: 84, child: SizedBox.shrink()),
            ),
            SizedBox(width: 8),
            Expanded(
              child: SkeletonCard(height: 84, child: SizedBox.shrink()),
            ),
            SizedBox(width: 8),
            Expanded(
              child: SkeletonCard(height: 84, child: SizedBox.shrink()),
            ),
            SizedBox(width: 8),
            Expanded(
              child: SkeletonCard(height: 84, child: SizedBox.shrink()),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Skeleton(height: 16, width: 120),
        const SizedBox(height: 12),
        const _BadgesSkeleton(),
        const SizedBox(height: 28),
        const Skeleton(height: 16, width: 100),
        const SizedBox(height: 12),
        const SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Skeleton.circle(34),
                  SizedBox(width: 10),
                  Expanded(child: Skeleton(height: 12, width: 160)),
                ],
              ),
              SizedBox(height: 14),
              SkeletonText(lines: 3, lineHeight: 11),
            ],
          ),
        ),
      ],
    );
  }
}
