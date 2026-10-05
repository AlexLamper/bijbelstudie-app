import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../auth/present/auth_controller.dart';
import 'contact_discovery_providers.dart';

/// "Laat vrienden me vinden" - the **second** consent
/// (`VRIENDENKRING_PLAN.md` principle 1 and §6 step 7).
///
/// Reading an address book and being findable in someone else's are two
/// separate decisions and neither implies the other, so this is a switch of
/// its own and it works whether or not the reader ever granted contacts
/// access.
///
/// Turning it on sends the reader's own number and e-mail to
/// `POST /friends/discovery/hashes`, which normalises and hashes them
/// server-side. That is the right way round: the server already knows the
/// account's e-mail, so hashing one's own two identifiers on the phone would
/// buy nothing, while somebody *else's* address book never leaves the phone
/// unhashed. Turning it off is a deletion - `DELETE /friends/discovery` - not
/// a flag.
///
/// Deliberately a standalone widget and not a screen: where this belongs is
/// Instellingen's call, and the settings screen can drop it into whichever
/// section it likes.
class FindableSwitchTile extends ConsumerStatefulWidget {
  const FindableSwitchTile({super.key, this.showCard = true});

  /// Wrapped in an [AppCard] by default. Pass false to drop it into a list
  /// that already draws its own rows.
  final bool showCard;

  @override
  ConsumerState<FindableSwitchTile> createState() => _FindableSwitchTileState();
}

class _FindableSwitchTileState extends ConsumerState<FindableSwitchTile> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Reads the local mirror so the switch renders in the right position
    // before anything comes back from the server.
    Future.microtask(() => ref.read(findableProvider.notifier).load());
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;

    String? phone;
    if (value) {
      phone = await _askForPhone();
      // A dismissed sheet is a cancelled switch, not an empty number.
      if (phone == null || !mounted) return;
    }

    setState(() => _busy = true);
    final ok = await ref
        .read(findableProvider.notifier)
        .setFindable(
          value,
          phone: phone != null && phone.trim().isEmpty ? null : phone,
          email: ref.read(authControllerProvider).value?.email,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dat lukte niet. Probeer het zo nog eens.')),
      );
    }
  }

  /// The number is asked for rather than guessed: nothing in the account
  /// carries one, and reading the device's own number needs a permission this
  /// app has no business holding. Empty is a valid answer - the e-mail alone
  /// already makes someone findable.
  Future<String?> _askForPhone() {
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + media.viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Laat vrienden je vinden', style: AppTheme.displaySmall),
                const SizedBox(height: 8),
                Text(
                  'We bewaren een versleutelde code van je e-mailadres, en van je '
                  'telefoonnummer als je dat hier invult. Iemand die jou in zijn '
                  'contacten heeft, kan je dan vinden. Je nummer zelf is voor niemand '
                  'te zien.',
                  style: AppTheme.bodyMuted,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: const InputDecoration(
                    labelText: 'Telefoonnummer (niet verplicht)',
                    hintText: '06 12345678',
                  ),
                ),
                const SizedBox(height: 18),
                SiteButton(
                  label: 'Vindbaar maken',
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(controller.text.trim()),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Annuleren'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    // Self-gating: a switch that cannot take renders nothing at all. Without
    // this, a build with the dart-define off or a server with no pepper would
    // offer a switch whose only possible outcome is "dat lukte niet". A
    // settings screen that draws a header above this should check
    // `contactDiscoveryOfferedProvider` itself, or the header stands alone.
    if (ref.watch(contactDiscoveryOfferedProvider).value != true) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final findable = ref.watch(findableProvider);

    final row = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Laat vrienden me vinden',
                style: AppTheme.bodyStrong.copyWith(fontSize: 14, color: scheme.onSurface),
              ),
              const SizedBox(height: 3),
              Text(
                'Mensen die jouw nummer of e-mailadres in hun contacten hebben, zien '
                'dat je BijbelStudie gebruikt. Ze kunnen je dan uitnodigen.',
                style: AppTheme.caption.copyWith(fontSize: 12.5, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: findable,
          onChanged: _busy ? null : _toggle,
        ),
      ],
    );

    if (!widget.showCard) return row;
    return AppCard(padding: const EdgeInsets.fromLTRB(16, 14, 12, 14), child: row);
  }
}

/// "Mijn contacten vergeten" - the way out of both consents at once.
///
/// Confirms, then runs `DELETE /friends/discovery` and clears everything the
/// app stored locally (the matched ids, the recorded disclosure, the
/// findability mirror). Leaveable, as principle 5 asks, and it really deletes.
class ForgetContactsTile extends ConsumerStatefulWidget {
  const ForgetContactsTile({super.key});

  @override
  ConsumerState<ForgetContactsTile> createState() => _ForgetContactsTileState();
}

class _ForgetContactsTileState extends ConsumerState<ForgetContactsTile> {
  bool _busy = false;

  Future<void> _forget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Contacten vergeten?'),
        content: const Text(
          'We verwijderen de versleutelde codes van je nummer en e-mailadres, en je '
          'bent niet meer te vinden via contacten. Je vrienden blijven gewoon in je '
          'kring.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Vergeten'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final ok = await ref.read(contactDiscoveryProvider.notifier).forget();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Je contactgegevens zijn verwijderd.'
              : 'Dat lukte niet. Probeer het zo nog eens.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return TextButton(
      onPressed: _busy ? null : _forget,
      child: const Text('Mijn contactgegevens vergeten'),
    );
  }
}
