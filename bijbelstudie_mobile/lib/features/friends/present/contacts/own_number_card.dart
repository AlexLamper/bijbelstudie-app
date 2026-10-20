import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import 'contact_discovery_providers.dart';

/// "Laat vrienden jou ook vinden" - the reader's own number, asked for inside
/// the contacts flow.
///
/// Contact matching only ever finds accounts that registered a number of their
/// own. Without this step the flow read the address book, matched it against
/// nobody, and never asked the one thing that would let the *other* phone
/// find this one - so two people with each other's number never met. The
/// switch in Instellingen could do it, but nobody went looking there.
///
/// Still the second consent (plan principle 1): a separate card with its own
/// button, never implied by having shared contacts. Renders nothing once the
/// reader is findable with a number.
class OwnNumberCard extends ConsumerStatefulWidget {
  const OwnNumberCard({super.key});

  @override
  ConsumerState<OwnNumberCard> createState() => _OwnNumberCardState();
}

class _OwnNumberCardState extends ConsumerState<OwnNumberCard> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref.read(findableProvider.notifier).saveOwnPhone(_controller.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok == null) {
        _error = 'Dit lijkt geen telefoonnummer. Bijvoorbeeld 06 12345678.';
      } else if (!ok) {
        _error = 'Dat lukte niet. Probeer het zo nog eens.';
      } else {
        _done = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;

    if (_done) {
      return AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppTheme.teal, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Je bent vindbaar. Wie jouw nummer heeft, ziet je nu bij '
                '"Mensen die je misschien kent".',
                style: AppTheme.caption.copyWith(fontSize: 13, height: 1.45),
              ),
            ),
          ],
        ),
      );
    }

    // Loading and error both read as "do not ask": a card that flickers in
    // and out is worse than one that waits for the store.
    if (ref.watch(ownPhoneNeededProvider).value != true) return const SizedBox.shrink();

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Laat vrienden jou ook vinden',
            style: AppTheme.bodyStrong.copyWith(fontSize: 15, color: scheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Vul je eigen nummer in. Wie jou in zijn contacten heeft, ziet dan dat je '
            'BijbelStudie gebruikt. We bewaren alleen een versleutelde code, je nummer '
            'zelf is voor niemand te zien.',
            style: AppTheme.caption.copyWith(fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Je telefoonnummer',
              hintText: '06 12345678',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          SiteButton(
            label: 'Vindbaar maken',
            loading: _busy,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}
