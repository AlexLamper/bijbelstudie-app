import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';

/// "Je mist wat je vrienden lezen" - what the Start tab shows a reader whose
/// contacts are not connected and who has no kring yet.
///
/// Loss-framed on purpose: the old card announced a feature, which reads as
/// something to get around to later. This one names what is already happening
/// without them. It claims no numbers: the app cannot know how many people
/// from the address book are here until the address book is read, and a made-up
/// count would be the one thing that makes the card untrustworthy.
///
/// One way in, "Verbind contacten", and it goes to Vriendenkring rather than
/// to the contacts permission flow directly: that entry point is being
/// replaced, and the screen is the stable address for whatever it becomes.
///
/// The code a friend gave you stays reachable as a single quiet line at the
/// bottom. It used to be a text field and a button here, which made the card
/// about inviting - the opposite of the point.
class MissingFriendsCard extends StatelessWidget {
  const MissingFriendsCard({super.key});

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconChip(icon: Icons.people_outline, size: 40, iconSize: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Je mist wat je vrienden lezen',
                  style: AppTheme.bodyStrong.copyWith(
                    fontSize: 15,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Vrienden uit je contacten gebruiken BijbelStudie al. Zolang je '
            'contacten niet verbonden zijn, zie je niet wat zij lezen en delen.',
            style: AppTheme.bodyMuted.copyWith(fontSize: 13.5),
          ),
          const SizedBox(height: 14),
          SiteButton(
            label: 'Verbind contacten',
            icon: Icons.contacts_outlined,
            onPressed: () => context.push('/vriendenkring'),
          ),
          const SizedBox(height: 4),
          // Small, low-contrast and last: still there for the reader who was
          // given a code, invisible to everyone else.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.push('/vriendenkring'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Ik heb een code van een vriend',
                style: AppTheme.caption.copyWith(
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  decorationColor: AppTheme.ruleStrong,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
