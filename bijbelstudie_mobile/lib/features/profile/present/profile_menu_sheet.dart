import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../admin/present/admin_providers.dart';
import '../../feedback/present/feedback_sheet.dart';
import '../data/profile_model.dart';
import '../data/profile_repository.dart';
import 'profile_provider.dart';

/// The hamburger menu: everything the profile screen used to list as sections.
///
/// The screen itself is now the reader's numbers and activity, so the plain
/// navigation moved in here. Only destinations that exist are listed - Groepen
/// is absent because `/groups` redirects away for the MVP.
Future<void> showProfileMenuSheet(
  BuildContext context,
  WidgetRef ref,
  ProfileModel profile,
) {
  final isAdmin = ref.read(isAdminProvider);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) {
      // Navigating has to outlive the sheet: pop first, then use the screen's
      // context, or go_router rebuilds under a route that is being removed.
      void go(void Function() action) {
        Navigator.of(sheetContext).pop();
        action();
      }

      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Eyebrow('Menu'),
              const SizedBox(height: 14),
              RuleGrid(
                children: [
                  _MenuRow(
                    icon: Icons.auto_stories_outlined,
                    label: 'Bijbelstudies',
                    onTap: () => go(() => context.go('/studies')),
                  ),
                  _MenuRow(
                    icon: Icons.edit_note_outlined,
                    label: 'Notities en markeringen',
                    onTap: () => go(() => context.go('/notes')),
                  ),
                  _MenuRow(
                    icon: Icons.local_library_outlined,
                    label: 'Hulpbronnen',
                    onTap: () => go(() => context.go('/resources')),
                  ),
                  _MenuRow(
                    icon: Icons.search,
                    label: 'Zoeken',
                    showRule: profile.isPro,
                    onTap: () => go(() => context.go('/search')),
                  ),
                  // Guideline 3.1.1: a subscriber - certainly a web
                  // subscriber - is never pointed at the paywall.
                  if (!profile.isPro)
                    _MenuRow(
                      icon: Icons.workspace_premium_outlined,
                      label: 'BijbelStudie Pro',
                      showRule: false,
                      onTap: () =>
                          go(() => context.push('/pro-intro?source=app_profile')),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              RuleGrid(
                children: [
                  // Beheer is invisible to everyone else; /api/v1/admin/*
                  // re-checks the account server-side regardless.
                  if (isAdmin)
                    _MenuRow(
                      icon: Icons.shield_outlined,
                      label: 'Beheer',
                      onTap: () => go(() => context.push('/admin')),
                    ),
                  _MenuRow(
                    icon: Icons.tune,
                    label: 'Lezen en meldingen',
                    onTap: () => go(() => context.push('/settings')),
                  ),
                  _MenuRow(
                    icon: Icons.explore_outlined,
                    label: 'Rondleiding opnieuw bekijken',
                    onTap: () => go(() => context.push('/tour')),
                  ),
                  _MenuRow(
                    icon: Icons.chat_bubble_outline,
                    label: 'Feedback geven',
                    showRule: false,
                    onTap: () => go(() => showFeedbackSheet(context, ref)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              RuleGrid(
                children: [
                  _MenuRow(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacybeleid',
                    onTap: () => go(() => _open(AppConfig.privacyPolicyUrl)),
                  ),
                  _MenuRow(
                    icon: Icons.description_outlined,
                    label: 'Gebruiksvoorwaarden',
                    showRule: false,
                    onTap: () => go(() => _open(AppConfig.termsOfUseUrl)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _open(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showRule = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showRule;

  @override
  Widget build(BuildContext context) {
    return RuleListTile(
      onTap: onTap,
      showRule: showRule,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.inkSoft),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
          Icon(Icons.chevron_right, size: 18, color: AppTheme.inkMuted),
        ],
      ),
    );
  }
}

/// The avatar's edit button.
///
/// `PATCH /api/v1/me` accepts a name and reading preferences; it has no image
/// upload, and neither does any other endpoint this app talks to. So the badge
/// on the avatar edits the one thing that really can be changed from here
/// rather than pretending a photo can be uploaded.
Future<void> showProfileNameDialog(
  BuildContext context,
  WidgetRef ref,
  ProfileModel profile,
) async {
  final controller = TextEditingController(text: profile.name);
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Naam wijzigen'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Je naam'),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Annuleren'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('Opslaan'),
        ),
      ],
    ),
  );
  controller.dispose();

  if (name == null || name.isEmpty || name == profile.name) return;

  try {
    await ref.read(profileRepositoryProvider).updateProfile(name: name);
    ref.invalidate(profileProvider);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Naam opslaan mislukt. Probeer het opnieuw.'),
      ),
    );
  }
}
