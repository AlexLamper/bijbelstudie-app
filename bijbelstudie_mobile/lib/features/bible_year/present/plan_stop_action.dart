import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'bible_year_parts.dart';
import 'bible_year_providers.dart';

/// The confirm text behind "Plan stoppen". Word for word the website's
/// `PLAN_STOP_CONFIRM` (lib/bibleYear/display.ts) - keep the two in step.
///
/// It has to be exact, because stopping is not reversible in place: the run
/// goes to `abandoned` and a later "Opnieuw beginnen" creates a new run, which
/// starts on day 1. Nothing is deleted - the read chapters, the streak and the
/// tree hang off the user, not off the plan, so none of them move.
const String kPlanStopConfirm =
    'Weet je zeker dat je wilt stoppen met Bijbel in een jaar? Wat je gelezen hebt blijft bewaard: '
    'je leesgeschiedenis, je streak en je boom veranderen niet. Begin je later opnieuw, dan start je '
    'plan weer op dag 1.';

/// "Plan stoppen": the way out of a running "Bijbel in een jaar", behind a
/// confirm dialog. The mirror of the website's button in the "Je voortgang"
/// card (components/bibleYear/BibleYearProgress.tsx), and deliberately as
/// quiet as that one - it sits under the day, not beside it.
///
/// On success the plan state answers with an abandoned enrollment and no
/// today, so every plan surface (this screen, the Start tab's card, the
/// dashboard) falls back to its "begin een leesplan" state by itself.
class PlanStopButton extends ConsumerStatefulWidget {
  const PlanStopButton({super.key});

  @override
  ConsumerState<PlanStopButton> createState() => _PlanStopButtonState();
}

class _PlanStopButtonState extends ConsumerState<PlanStopButton> {
  bool _pending = false;

  Future<void> _confirmStop() async {
    if (_pending) return;
    final ok = await showBibleYearConfirm(
      context,
      title: 'Plan stoppen',
      confirmLabel: 'Stoppen',
      destructive: true,
      content: const Text(kPlanStopConfirm),
    );
    if (!ok || !mounted) return;
    // The screen swaps this button out for the invitation card the moment the
    // plan stops, so the messenger is taken while the context is still good.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pending = true);
    final error = await ref.read(bibleYearProvider.notifier).stop();
    if (mounted) setState(() => _pending = false);
    messenger.showSnackBar(SnackBar(content: Text(error ?? 'Je leesplan is gestopt.')));
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Align(
      child: TextButton(
        onPressed: _pending ? null : _confirmStop,
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.inkMuted,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(
          _pending ? 'Bezig...' : 'Plan stoppen',
          style: AppTheme.bodyStrong.copyWith(fontSize: 14, color: AppTheme.inkMuted),
        ),
      ),
    );
  }
}
