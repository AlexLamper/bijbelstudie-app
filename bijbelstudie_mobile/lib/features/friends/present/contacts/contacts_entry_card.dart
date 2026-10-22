import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import 'connect_contacts_button.dart';
import 'contact_discovery_providers.dart';

/// A second, compact entry point into contact matching, for a page that has no
/// room for [ConnectContactsButton].
///
/// It renders **nothing at all** when the feature is not on - the build's
/// dart-define off, or the server's pepper unset
/// ([contactDiscoveryOfferedProvider]). That is the point of asking the cheap
/// question first: a feature that is simply off must never show an error card
/// for something nobody asked for, and `isContactDiscoveryAvailable()` never
/// throws, so an offline reader sees no entry point rather than a failure.
///
/// Tapping asks the OS straight away, through [startContactsMatch] - the same
/// one route the big card uses - so the disclosure has to be on this card too,
/// and it is: the three facts sit under the title, where the reader's thumb is.
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
      borderColor: AppTheme.teal,
      onTap: () => startContactsMatch(context, ref),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 4),
                const ContactsDisclosureLines(),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 20, color: AppTheme.inkMuted),
        ],
      ),
    );
  }
}
