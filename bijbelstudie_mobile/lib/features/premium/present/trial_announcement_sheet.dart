import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';

/// What there is to try, kept to four lines. Each one is Pro in the app.
const _kTry = [
  'Matthew Henry, Calvijn en Dachsel bij elk hoofdstuk',
  'De grondtekst in het Hebreeuws en Grieks',
  'Tot 200 vragen per dag aan de AI-assistent',
  'Rustige muziek terwijl je leest',
];

/// "Je hebt 3 dagen Pro gekregen": once, when an account from before the
/// reverse trial is given it on its next open (website
/// `isExistingFreeAccount`). New accounts never see it - for them the Pro days
/// are how the app starts. Opened by `ProPromoTrigger`, which also tells the
/// server it was shown, so the website does not show it again.
///
/// No purchase button: the reader has Pro now, and this only says so.
Future<void> showTrialAnnouncementSheet(BuildContext context, {required int daysTotal, required int daysUsed}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.paperRaised,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => TrialAnnouncementSheet(daysTotal: daysTotal, daysUsed: daysUsed),
  );
}

class TrialAnnouncementSheet extends StatelessWidget {
  const TrialAnnouncementSheet({super.key, required this.daysTotal, required this.daysUsed});

  final int daysTotal;
  final int daysUsed;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final today = daysUsed <= 1 ? 'Vandaag is de eerste.' : 'Vandaag is dag ${daysUsed.clamp(1, daysTotal)}.';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: AppTheme.rule, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            SiteBadge.teal('BijbelStudie Pro', icon: Icons.workspace_premium_outlined),
            const SizedBox(height: 12),
            Semantics(
              header: true,
              child: Text(
                'Je hebt $daysTotal dagen Pro gekregen',
                style: AppTheme.displaySmall.copyWith(fontSize: 24, height: 1.2, letterSpacing: -0.4),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Op de eerste $daysTotal dagen waarop je BijbelStudie opent, kun je alles van Pro gebruiken. '
              '$today Probeer bijvoorbeeld:',
              style: AppTheme.bodyMuted.copyWith(color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 14),
            for (final line in _kTry) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.check, size: 18, color: AppTheme.teal),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(line, style: AppTheme.bodyMuted.copyWith(color: AppTheme.ink))),
                ],
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 6),
            Text(
              'Daarna ga je vanzelf verder met de gratis versie. Van wat je het meest gebruikte, '
              'houd je dan een klein dagelijks deel.',
              style: AppTheme.caption.copyWith(fontSize: 12.5, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 18),
            SiteButton(label: 'Aan de slag', onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}
