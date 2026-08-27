import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../profile/present/profile_provider.dart';
import 'tour_controller.dart';

/// `/tour` — the entry point to the guided walkthrough.
///
/// This used to *be* the walkthrough: six full-screen pages, each an icon and
/// a paragraph, describing parts of the app the reader could not see while
/// being told about them. The tour now runs over the real app, the way
/// `guided-tour.tsx` does on the website — a spotlight on the live widget with
/// a card beside it — so this route's whole job is to turn it on and get out
/// of the way ([TourHost] paints it above every route).
///
/// The route is kept rather than removed because two call sites depend on it:
/// [resolvePostAuthRoute] sends a freshly set-up account here, and Profiel's
/// "Rondleiding opnieuw bekijken" pushes it.
class TourScreen extends ConsumerStatefulWidget {
  const TourScreen({super.key});

  @override
  ConsumerState<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends ConsumerState<TourScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _launch());
  }

  void _launch() {
    if (!mounted) return;

    // The first step lives on the dashboard, and the overlay navigates from
    // there. Reached by push (a replay from Profiel) or by go (straight after
    // setup, with no back stack) — this route must not survive either way, or
    // the reader would end up back on a blank launcher when they pop.
    ref.read(tourControllerProvider.notifier).start();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Never seen for more than a frame. It exists so the route has something
    // to build, and it is on brand rather than blank in case a slow frame
    // makes it visible.
    return const Scaffold(
      backgroundColor: AppTheme.paper,
      body: Center(child: AppLoader()),
    );
  }
}

/// Starts the tour without going through the `/tour` route.
///
/// Useful anywhere the reader is already where the tour begins. Kept next to
/// the route so both ways in agree about what "start the tour" means.
void startGuidedTour(WidgetRef ref) {
  // Warms the Pro check the step list is filtered on, so the paywall step is
  // not briefly offered to a subscriber before the profile lands.
  ref.read(profileProvider);
  ref.read(tourControllerProvider.notifier).start();
}
