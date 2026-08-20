import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';

Future<void> _open(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Data-handling disclosure shown under the login and register forms.
///
/// The plain-language summary is the part a user actually reads, but a summary
/// is not a policy: app review expects the real, hosted documents to be
/// reachable from the screen that collects the account details. So the dialog
/// links out to both rather than paraphrasing them and stopping there.
Widget buildUserDataInfoLink(BuildContext context) {
  final theme = Theme.of(context);

  return Opacity(
    opacity: 0.72,
    child: TextButton(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Hoe we met je gegevens omgaan'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Bij het inloggen of registreren gebruiken we alleen gegevens die '
                  'nodig zijn om je account te laten werken, zoals je naam, e-mailadres '
                  'en inloggegevens.\n\n'
                  'Je gegevens worden via beveiligde verbindingen verzonden en we delen '
                  'ze niet voor advertenties zonder jouw toestemming.\n\n'
                  'Je kunt je account op elk moment zelf verwijderen in de app, via '
                  'Profiel → Account verwijderen. Dat verwijdert je account en je '
                  'gegevens volgens ons privacybeleid. Lukt het niet, dan kun je ons '
                  'bereiken via info@bijbel-studie.com.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                const Divider(height: 1, color: AppTheme.rule),
                const SizedBox(height: 6),
                _LegalLink(
                  label: 'Lees het privacybeleid',
                  url: AppConfig.privacyPolicyUrl,
                ),
                _LegalLink(
                  label: 'Lees de algemene voorwaarden',
                  url: AppConfig.termsOfServiceUrl,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Sluiten'),
            ),
          ],
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        'Meer over gegevensgebruik',
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: AppTheme.inkMuted,
          decoration: TextDecoration.underline,
          decorationColor: AppTheme.ruleStrong,
        ),
      ),
    ),
  );
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: () => _open(url),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 6),
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: AppTheme.teal,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: AppTheme.sansFontName,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AppTheme.teal,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.open_in_new, size: 14, color: AppTheme.teal),
          ],
        ),
      ),
    );
  }
}
