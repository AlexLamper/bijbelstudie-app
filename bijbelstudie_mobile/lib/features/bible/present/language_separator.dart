import 'package:flutter/material.dart';

import '../../../core/ui/app_widgets.dart';

/// A hairline with the language name sitting on it, drawn between two
/// language groups in a translation list. Same rule colour and eyebrow type
/// as every other divider in the app, so it reads as structure rather than as
/// another option.
///
/// Shared by the setup wizard's translation step and the reader's translation
/// picker. Both list Dutch translations followed immediately by English ones,
/// and without this the two languages ran together as one undifferentiated
/// column — `Statenvertaling`, `Canisiusbijbel`, `King James Version` with
/// nothing to say where the Dutch stopped.
class LanguageSeparator extends StatelessWidget {
  const LanguageSeparator({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 18),
        child: Row(
          children: [
            const Expanded(child: RuleLine()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              // Eyebrow, not a bare Text: it carries the app's uppercase
              // treatment for section labels, and reusing it keeps this
              // divider looking like every other one.
              child: Eyebrow(label, compact: true),
            ),
            const Expanded(child: RuleLine()),
          ],
        ),
      ),
    );
  }
}
