import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import 'contact_discovery_providers.dart';
import 'contact_matches_screen.dart';

/// The prominent in-app disclosure, shown **before** the OS contacts prompt.
///
/// This screen is not decoration and not a nicety: Play's "Personal and
/// sensitive data" policy requires a prominent in-app disclosure before the
/// runtime contacts permission is requested, and App Store Review 5.1.1(i)
/// and 5.1.2 require that contacts are optional and that nothing is shared
/// without consent. So it says the three things that have to be said - what is
/// read, what is sent, what is kept - and it is the only route to the prompt:
/// `ContactDiscoveryController.startMatch` refuses to call [ContactsSource]
/// until this screen has recorded that it was passed.
///
/// The copy is `VRIENDENKRING_PLAN.md` §6, verbatim. It is also the existing
/// "explain, then ask" pattern from `core/notifications/permission_moment.dart`
/// applied a second time, rather than a new idea: in-app sheet first, OS dialog
/// only after an explicit yes, and "Nu niet" costs the reader nothing.
class ContactsDisclosureScreen extends ConsumerStatefulWidget {
  const ContactsDisclosureScreen({super.key});

  /// The route-ready name, for `core/router/app_router.dart`.
  static const routePath = '/vriendenkring/contacten';
  static const routeName = 'vriendenkring-contacten';

  @override
  ConsumerState<ContactsDisclosureScreen> createState() =>
      _ContactsDisclosureScreenState();
}

/// Opens the disclosure as a full-screen page without needing a route.
///
/// Returns true when the reader accepted and the matching run was started.
/// Nothing is read, asked or sent before that.
Future<bool> showContactsDisclosure(BuildContext context) async {
  final accepted = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => const ContactsDisclosureScreen(),
      settings: const RouteSettings(name: ContactsDisclosureScreen.routePath),
    ),
  );
  return accepted ?? false;
}

class _ContactsDisclosureScreenState extends ConsumerState<ContactsDisclosureScreen> {
  bool _accepting = false;

  Future<void> _accept() async {
    if (_accepting) return;
    setState(() => _accepting = true);

    // Records that the disclosure was passed and only then asks the OS. The
    // two steps live together in the controller, so no caller can do the
    // second without the first.
    final run = ref.read(contactDiscoveryProvider.notifier).acceptDisclosureAndStart();

    // The results screen goes up first, deliberately not awaited: the OS
    // dialog then appears over "Vrienden gevonden" rather than over a
    // disclosure the reader has already answered, and the run's own stages
    // are what that screen renders.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const ContactMatchesScreen(),
        settings: const RouteSettings(name: ContactMatchesScreen.routePath),
      ),
    );

    await run;
    // Normally gone by now; the guard is for a run that finished before the
    // route swap did.
    if (mounted) setState(() => _accepting = false);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Vrienden vinden')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.tealTint,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      child: Icon(Icons.contacts_outlined, size: 26, color: AppTheme.teal),
                    ),
                    const SizedBox(height: 18),
                    // The plan's §6 heading and paragraph, word for word.
                    Text('Vind je vrienden', style: AppTheme.displaySmall),
                    const SizedBox(height: 10),
                    Text(
                      'BijbelStudie kan in je contacten kijken om te zien wie de app al '
                      'gebruikt. We versturen alleen versleutelde codes, nooit namen of '
                      'nummers, en bewaren ze niet. Je bepaalt zelf wie je uitnodigt.',
                      style: AppTheme.bodyLead,
                    ),
                    const SizedBox(height: 22),
                    const _DisclosurePoint(
                      icon: Icons.visibility_outlined,
                      title: 'Wat we lezen',
                      body:
                          'De telefoonnummers en e-mailadressen in je contacten. Namen '
                          'vragen we niet op en lezen we niet.',
                    ),
                    const _DisclosurePoint(
                      icon: Icons.lock_outline,
                      title: 'Wat we versturen',
                      body:
                          'Alleen een versleutelde code per nummer en adres, berekend op '
                          'je telefoon. Een nummer of adres zelf verlaat je telefoon nooit.',
                    ),
                    const _DisclosurePoint(
                      icon: Icons.delete_outline,
                      title: 'Wat we bewaren',
                      body:
                          'Niets. De codes worden gebruikt om te vergelijken en daarna '
                          'direct weggegooid. We slaan je contacten nergens op.',
                    ),
                    const _DisclosurePoint(
                      icon: Icons.handshake_outlined,
                      title: 'Wat jij beslist',
                      body:
                          'Je ziet wie er gevonden is en nodigt zelf uit wie je wilt. We '
                          'versturen nooit automatisch een verzoek.',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Je kunt dit altijd weer intrekken. De Vriendenkring werkt ook '
                      'zonder je contacten - met een uitnodigingslink of code.',
                      style: AppTheme.caption.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            // Pinned, so "Doorgaan" is reachable at any text scale. The OS
            // dialog is behind this button and nowhere else.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                children: [
                  SiteButton(
                    label: 'Doorgaan',
                    loading: _accepting,
                    onPressed: _accept,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _accepting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Nu niet'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisclosurePoint extends StatelessWidget {
  const _DisclosurePoint({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppTheme.teal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.bodyStrong.copyWith(fontSize: 14, color: scheme.onSurface),
                ),
                const SizedBox(height: 3),
                Text(body, style: AppTheme.caption.copyWith(fontSize: 13, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
