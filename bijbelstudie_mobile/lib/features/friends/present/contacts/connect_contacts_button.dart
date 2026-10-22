import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import 'contact_discovery_providers.dart';
import 'contact_matches_screen.dart';

/// "Verbind Contacten": the card at the top of Vriendenkring, and the one
/// route to the OS contacts prompt.
///
/// There used to be a full page between the two - "Vind je vrienden", with the
/// disclosure on it and a "Doorgaan" - and the tap now goes straight to the OS
/// dialog instead. The disclosure did not go away: Play's "Personal and
/// sensitive data" policy requires a prominent in-app disclosure **before** the
/// runtime permission is requested, and App Store Review 5.1.1(i) and 5.1.2
/// require that contacts stay optional. So the three facts that have to be
/// said - what is read, what is sent, what is kept - are printed inside this
/// card, under the button, where they are on screen at the moment of the tap
/// rather than one page behind it.
///
/// The card also nags a little on purpose ([_AttentionIcon]): it is the way
/// into the whole feature and a reader who never notices it never finds
/// anybody. A slow teal breath, nothing that moves across the screen, and the
/// static tinted state when the reader asked for less motion.

/// The three disclosure lines, short enough for a card and complete enough for
/// review. `VRIENDENKRING_PLAN.md` §6 says the same at length; these are the
/// same three facts in one line each, and all three have to stay.
const contactsDisclosureLines = [
  'We lezen alleen de nummers en e-mailadressen in je contacten, geen namen.',
  'Er gaat alleen een versleutelde code naar onze server, nooit een nummer zelf.',
  'We bewaren niets: de codes worden vergeleken en daarna weggegooid.',
];

/// [contactsDisclosureLines] as the quiet text under a "verbind contacten"
/// tap target. Wherever the tap can reach the OS prompt, this has to be in
/// view beside it.
class ContactsDisclosureLines extends StatelessWidget {
  const ContactsDisclosureLines({super.key, this.fontSize = 12});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in contactsDisclosureLines)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              line,
              style: AppTheme.caption.copyWith(fontSize: fontSize, height: 1.4),
            ),
          ),
      ],
    );
  }
}

/// Record that the disclosure was shown and accepted, ask the OS, and put the
/// results screen up for the answer to land on.
///
/// The one path from a tap to the permission prompt. The controller keeps the
/// gate: it will not touch the address book until
/// [ContactDiscoveryController.acceptDisclosureAndStart] has written down that
/// the disclosure was passed, and this is the only caller of that.
Future<void> startContactsMatch(BuildContext context, WidgetRef ref) async {
  final run = ref.read(contactDiscoveryProvider.notifier).acceptDisclosureAndStart();

  // The results screen goes up first, deliberately not awaited: the OS dialog
  // then appears over "Vrienden gevonden" rather than over the page the reader
  // just tapped, and that screen renders the run's own stages - including the
  // refusals, which now say so instead of showing an empty list.
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const ContactMatchesScreen(),
      settings: const RouteSettings(name: ContactMatchesScreen.routePath),
    ),
  );
  await run;
}

class ConnectContactsButton extends StatelessWidget {
  const ConnectContactsButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  static const label = 'Verbind Contacten';

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final platform = Theme.of(context).platform;
    final apple = platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

    return Semantics(
      button: true,
      label: label,
      // The disclosure is read out after the button's own label, so a reader
      // on a screen reader hears what is read and sent before they tap.
      hint: contactsDisclosureLines.join(' '),
      excludeSemantics: true,
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 15, 12, 13),
        borderColor: AppTheme.teal,
        // The quiet half of the attention state, and the whole of it when the
        // reader asked for less motion.
        color: AppTheme.tealTint,
        onTap: onPressed,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _AttentionIcon(
                  icon: apple ? CupertinoIcons.person_crop_circle : Icons.contacts,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: AppTheme.bodyStrong.copyWith(
                      fontSize: 16,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  apple ? CupertinoIcons.chevron_right : Icons.chevron_right,
                  size: apple ? 18 : 22,
                  color: AppTheme.inkMuted,
                ),
              ],
            ),
            const SizedBox(height: 11),
            Divider(height: 1, thickness: 1, color: AppTheme.rule),
            const SizedBox(height: 9),
            const ContactsDisclosureLines(),
          ],
        ),
      ),
    );
  }
}

/// The contacts mark, breathing.
///
/// A teal halo behind it that fades in and out over [_breath] and a scale that
/// moves by 6%: enough to catch the eye on a page the reader is scrolling
/// past, not enough to read as a notification. No travel, no bounce, nothing
/// that competes with the text beside it.
///
/// With `MediaQuery.disableAnimations` on, the ticker never starts and the
/// halo sits at its own resting opacity, so the card still looks deliberate
/// rather than unfinished. The controller is created once and disposed with
/// the state.
class _AttentionIcon extends StatefulWidget {
  const _AttentionIcon({required this.icon});

  final IconData icon;

  @override
  State<_AttentionIcon> createState() => _AttentionIconState();
}

/// Slow enough to read as breathing rather than as a pulse.
const Duration _breath = Duration(milliseconds: 1700);

class _AttentionIconState extends State<_AttentionIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _breath,
  );

  late final Animation<double> _breathing = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here rather than in build: starting or stopping a ticker is not a
    // thing to do while laying out, and this is the one place that learns the
    // reader turned reduce-motion on or off.
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _breathing,
      builder: (context, child) {
        final t = _breathing.value;
        return Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.teal.withValues(alpha: 0.08 + 0.10 * t),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          child: Transform.scale(scale: 1 + 0.06 * t, child: child),
        );
      },
      child: Icon(widget.icon, size: 24, color: AppTheme.teal),
    );
  }
}
