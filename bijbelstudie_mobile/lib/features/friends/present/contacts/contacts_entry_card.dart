import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import 'contact_discovery_providers.dart';
import 'contacts_disclosure_screen.dart';

/// The one entry point into contact matching: a card for the Vrienden tab.
///
/// It renders **nothing at all** when the feature is not on - the build's
/// dart-define off, or the server's pepper unset
/// ([contactDiscoveryOfferedProvider]). That is the point of asking the cheap
/// question first: a feature that is simply off must never show an error card
/// for something nobody asked for, and `isContactDiscoveryAvailable()` never
/// throws, so an offline reader sees no entry point rather than a failure.
///
/// Tapping opens [ContactsDisclosureScreen] and nothing else. No permission is
/// requested and no contact is read from here.
class ContactsEntryCard extends ConsumerWidget {
  const ContactsEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final offered = ref.watch(contactDiscoveryOfferedProvider);
    // Both the loading and the error case render nothing: there is no honest
    // placeholder for "we are finding out whether this feature exists".
    if (offered.value != true) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      onTap: () => showContactsDisclosure(context),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.tealTint,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Icon(Icons.contacts_outlined, size: 19, color: AppTheme.teal),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vind je vrienden',
                  style: AppTheme.bodyStrong.copyWith(fontSize: 14, color: scheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  'Kijk wie uit je contacten de app al gebruikt',
                  maxLines: 2,
                  style: AppTheme.caption.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: AppTheme.inkMuted),
        ],
      ),
    );
  }
}
