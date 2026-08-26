import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../auth/present/auth_controller.dart';
import '../../feedback/present/feedback_sheet.dart';
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
          loading: () => const AppLoader(),
          error: (_, __) => AppEmptyState(
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
        Text(profile.name.isEmpty ? 'Gebruiker' : profile.name, style: AppTheme.displaySmall),
        const SizedBox(height: 4),
        Text(profile.email, style: AppTheme.bodyMuted),
        const SizedBox(height: 20),
        _ProStatusCard(profile: profile),

        // The website's sidebar sections that have no tab of their own.
        const SizedBox(height: 28),
        const SectionHeader(title: 'Ontdekken'),
        const SizedBox(height: 12),
        RuleGrid(
          children: [
            RuleListTile(
              onTap: () => context.go('/groups'),
              child: const _NavRow(icon: Icons.groups_outlined, label: 'Groepen'),
            ),
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
              onTap: () => context.push('/settings'),
              child: const _NavRow(icon: Icons.tune, label: 'Lezen en meldingen'),
            ),
            RuleListTile(
              onTap: () => showFeedbackSheet(context, ref),
              child: const _NavRow(
                icon: Icons.chat_bubble_outline,
                label: 'Feedback geven',
              ),
            ),
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
            const SiteBadge.neutral('Gratis'),
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
        const Icon(Icons.chevron_right, size: 18, color: AppTheme.inkMuted),
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
