import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../auth/present/auth_controller.dart';
import '../../dashboard/data/dashboard_models.dart';
import '../../dashboard/present/dashboard_providers.dart';
import '../../feedback/present/feedback_sheet.dart';
import '../../onboarding/present/tour_controller.dart';
import '../data/profile_model.dart';
import '../data/profile_repository.dart';
import 'profile_provider.dart';

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
                  description: 'Controleer je verbinding en probeer het opnieuw.',
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        const Eyebrow('Account'),
        const SizedBox(height: 10),
        _AccountHeader(profile: profile),

        // The reading stats used to live on the Start tab, where they competed
        // with the daily verse and the "verder lezen" card. They belong to the
        // account, so this is their home now.
        const SizedBox(height: 26),
        const SectionHeader(title: 'Jouw voortgang'),
        const SizedBox(height: 12),
        const _ProgressSection(),

        const SizedBox(height: 28),
        const SectionHeader(title: 'Abonnement'),
        const SizedBox(height: 12),
        TourAnchor(
          id: TourAnchorIds.profilePro,
          child: _ProStatusCard(profile: profile),
        ),

        // The website's sidebar sections that have no tab of their own.
        const SizedBox(height: 28),
        const SectionHeader(title: 'Ontdekken'),
        const SizedBox(height: 12),
        RuleGrid(
          children: [
            RuleListTile(
              onTap: () => context.go('/resources'),
              child: const _NavRow(
                icon: Icons.local_library_outlined,
                label: 'Hulpbronnen',
              ),
            ),
            RuleListTile(
              showRule: false,
              onTap: () => context.go('/search'),
              child: const _NavRow(icon: Icons.search, label: 'Zoeken'),
            ),
          ],
        ),

        const SizedBox(height: 28),
        const SectionHeader(title: 'Instellingen'),
        const SizedBox(height: 12),
        RuleGrid(
          children: [
            RuleListTile(
              showRule: false,
              onTap: () => context.push('/settings'),
              child: const _NavRow(icon: Icons.tune, label: 'Lezen en meldingen'),
            ),
          ],
        ),

        // "Feedback geven", "Privacybeleid" en "Gebruiksvoorwaarden" zijn geen
        // instellingen — die staan hieronder onder Ondersteuning en Juridisch.
        const SizedBox(height: 28),
        const SectionHeader(title: 'Ondersteuning'),
        const SizedBox(height: 12),
        RuleGrid(
          children: [
            RuleListTile(
              onTap: () => context.push('/tour'),
              child: const _NavRow(
                icon: Icons.explore_outlined,
                label: 'Rondleiding opnieuw bekijken',
              ),
            ),
            RuleListTile(
              showRule: false,
              onTap: () => showFeedbackSheet(context, ref),
              child: const _NavRow(
                icon: Icons.chat_bubble_outline,
                label: 'Feedback geven',
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),
        const SectionHeader(title: 'Juridisch'),
        const SizedBox(height: 12),
        RuleGrid(
          children: [
            RuleListTile(
              onTap: () => _open(AppConfig.privacyPolicyUrl),
              child: const _NavRow(icon: Icons.privacy_tip_outlined, label: 'Privacybeleid'),
            ),
            RuleListTile(
              showRule: false,
              onTap: () => _open(AppConfig.termsOfUseUrl),
              child: const _NavRow(icon: Icons.description_outlined, label: 'Gebruiksvoorwaarden'),
            ),
          ],
        ),

        const SizedBox(height: 28),
        const SectionHeader(title: 'Licenties'),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'De vertalingen en commentaren in deze app zijn publiek domein. '
                'De grondtekst komt van STEPBible (TAHOT/TAGNT) en is beschikbaar '
                'onder CC BY 4.0.',
                style: AppTheme.bodyMuted.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 10),
              Text(
                'Vertalingen die op de website beschikbaar zijn maar niet in de app '
                '(NBG-vertaling 1951, NET Bible, King Comments) vallen onder licenties '
                'die alleen voor www.bijbel-studie.com gelden.',
                style: AppTheme.bodyMuted.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),
        SiteOutlineButton(
          label: 'Uitloggen',
          icon: Icons.logout,
          onPressed: () async {
            await ref.read(authControllerProvider.notifier).logout();
            if (context.mounted) context.go('/login');
          },
        ),
        const SizedBox(height: 12),
        // Guideline 5.1.1(v): deletion must be reachable without leaving the
        // app. Two taps from the main screen, no "mail ons" link.
        TextButton(
          onPressed: () => _confirmDelete(context, ref),
          style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
          child: const Text('Account verwijderen'),
        ),
      ],
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
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
        const SnackBar(content: Text('Verwijderen mislukt. Probeer het opnieuw.')),
      );
    }
  }
}

/// Avatar, name and email as one block, so the top of the screen reads as
/// "this is you" instead of as the first row of a settings list.
class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.profile});

  final ProfileModel profile;

  @override
  Widget build(BuildContext context) {
    final name = profile.name.trim().isEmpty ? 'Gebruiker' : profile.name.trim();
    final initial = name.characters.first.toUpperCase();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.tealTint,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.rule),
          ),
          child: Text(
            initial,
            style: AppTheme.displayTitle.copyWith(color: AppTheme.tealStrong),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: AppTheme.displaySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                profile.email,
                style: AppTheme.bodyMuted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Streak, books and notes — the three numbers the Start tab used to carry —
/// plus the 66-book canon shown as actual progress rather than as a fraction.
class _ProgressSection extends ConsumerWidget {
  const _ProgressSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(dashboardProvider)
        .when(
          loading: () => const SkeletonCard(
            height: 168,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Center(child: Skeleton(height: 30, width: 56))),
                    Expanded(child: Center(child: Skeleton(height: 30, width: 56))),
                    Expanded(child: Center(child: Skeleton(height: 30, width: 56))),
                  ],
                ),
                SizedBox(height: 26),
                Skeleton(height: 12, width: 150),
                SizedBox(height: 12),
                Skeleton(height: 6, radius: 999),
              ],
            ),
          ),
          error: (_, __) => AppCard(
            child: Row(
              children: [
                Icon(Icons.wifi_off_outlined, size: 18, color: AppTheme.inkMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Voortgang niet geladen.',
                    style: AppTheme.bodyMuted,
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(dashboardProvider),
                  child: const Text('Opnieuw'),
                ),
              ],
            ),
          ),
          data: (data) => _ProgressCard(data: data),
        );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.data});

  final DashboardData data;

  /// The whole Protestant canon — the denominator behind "… /66 boeken".
  static const int _canonBooks = 66;

  @override
  Widget build(BuildContext context) {
    final books = data.booksStarted.clamp(0, _canonBooks);
    final chapters = data.readChapters.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Stat(
                    value: '${data.streak}',
                    label: 'dagen reeks',
                    icon: Icons.local_fire_department_outlined,
                    tint: AppTheme.flame,
                  ),
                ),
                _divider(context),
                Expanded(
                  child: _Stat(
                    value: '$books/$_canonBooks',
                    label: 'boeken',
                    icon: Icons.menu_book_outlined,
                    tint: AppTheme.teal,
                  ),
                ),
                _divider(context),
                Expanded(
                  child: _Stat(
                    value: '${data.notesCount}',
                    label: 'notities',
                    icon: Icons.edit_note_outlined,
                    tint: AppTheme.ai,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text('Boeken geopend', style: AppTheme.metaLabel),
              ),
              Text(
                '$books van $_canonBooks',
                style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SiteProgressBar(value: books / _canonBooks),
          const SizedBox(height: 8),
          Text(
            chapters == 0
                ? 'Nog geen hoofdstukken gelezen.'
                : '$chapters ${chapters == 1 ? 'hoofdstuk' : 'hoofdstukken'} gelezen',
            style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
          ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Container(width: 1, color: Theme.of(context).colorScheme.outline),
  );
}

/// One column of [_ProgressCard]'s trio.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.icon,
    required this.tint,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Scales down rather than truncating: "12/66" is wide on a small phone.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: tint),
              const SizedBox(width: 5),
              Text(
                value,
                style: AppTheme.statNumber.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
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
        const Skeleton(height: 10, width: 70),
        const SizedBox(height: 14),
        const Row(
          children: [
            Skeleton.circle(52),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(height: 20, width: 160),
                  SizedBox(height: 9),
                  Skeleton(height: 12, width: 200),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        const Skeleton(height: 14, width: 120),
        const SizedBox(height: 12),
        const SkeletonCard(
          height: 168,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Center(child: Skeleton(height: 30, width: 56))),
                  Expanded(child: Center(child: Skeleton(height: 30, width: 56))),
                  Expanded(child: Center(child: Skeleton(height: 30, width: 56))),
                ],
              ),
              SizedBox(height: 26),
              Skeleton(height: 12, width: 150),
              SizedBox(height: 12),
              Skeleton(height: 6, radius: 999),
            ],
          ),
        ),
        const SizedBox(height: 28),
        SkeletonCard(height: 150, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Skeleton(height: 20, width: 70, radius: 20),
            SizedBox(height: 14),
            Skeleton(height: 16, width: 150),
            SizedBox(height: 10),
            SkeletonText(lines: 2, lineHeight: 11),
          ],
        )),
        const SizedBox(height: 28),
        for (var i = 0; i < 3; i++) ...[
          const Skeleton(height: 14, width: 110),
          const SizedBox(height: 12),
          const SkeletonCard(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: SkeletonText(lines: 2, lineHeight: 12),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

class _ProStatusCard extends StatelessWidget {
  const _ProStatusCard({required this.profile});

  final ProfileModel profile;

  @override
  Widget build(BuildContext context) {
    if (!profile.isPro) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SiteBadge.neutral('Gratis'),
            const SizedBox(height: 10),
            Text('BijbelStudie Pro', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(
              'Onbeperkt offline lezen, alle commentaren en de grondtekst.',
              style: AppTheme.bodyMuted,
            ),
            const SizedBox(height: 14),
            SiteButton(
              label: 'Bekijk Pro',
              onPressed: () => context.push('/premium?source=app_profile'),
            ),
          ],
        ),
      );
    }

    // Guideline 3.1.1 multiplatform exception: a web subscriber keeps access
    // and is never shown a purchase button.
    final label = profile.isProFromWeb ? 'Actief via web' : 'Actief';
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SiteBadge.positive(label),
                const SizedBox(height: 10),
                Text('BijbelStudie Pro', style: Theme.of(context).textTheme.headlineMedium),
                if (profile.proExpiresAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Verlengt op ${_formatDate(profile.proExpiresAt!)}',
                    style: AppTheme.bodyMuted.copyWith(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.inkSoft),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
        Icon(Icons.chevron_right, size: 18, color: AppTheme.inkMuted),
      ],
    );
  }
}

String _formatDate(DateTime date) {
  const months = [
    'januari', 'februari', 'maart', 'april', 'mei', 'juni',
    'juli', 'augustus', 'september', 'oktober', 'november', 'december',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
