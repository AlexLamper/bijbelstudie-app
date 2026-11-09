import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../progress_tree/present/progress_tree_providers.dart';
import 'tour_controller.dart';

/// `/tour` - the entry point to the onboarding guide.
///
/// This used to *be* the walkthrough: six full-screen pages, each an icon and
/// a paragraph. Then it was a spotlight tour over the real app. Now it starts
/// the hands-on guide (`tour_controller.dart`), which has the reader mark a
/// verse, swipe to Studie, ask the assistant and open the commentary on the
/// Bijbel tab itself - so this route's whole job is to turn it on and get out
/// of the way ([TourHost] paints the guide above every route).
///
/// The route is kept rather than removed because its call sites depend on it:
/// [resolvePostAuthRoute] and the end of setup send a fresh account here, and
/// Profiel's "Rondleiding opnieuw bekijken" pushes it.
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

    // Reached by push (a replay from Profiel) or by go (straight after setup,
    // with no back stack). Either way the guide happens on the Bijbel tab, and
    // `go` replaces the whole stack, this route included: popping back to it
    // would land on a blank launcher.
    final replay = context.canPop();
    startGuidedTour(ref, replay: replay);
    context.go('/study');
  }

  @override
  Widget build(BuildContext context) {
    // Never seen for more than a frame. It exists so the route has something
    // to build, and it is on brand rather than blank in case a slow frame
    // makes it visible.
    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: Center(child: AppLoader()),
    );
  }
}

/// Starts the guide without going through the `/tour` route.
///
/// Kept next to the route so both ways in agree about what "start the guide"
/// means. The guide puts the app on its first step's screen itself.
void startGuidedTour(WidgetRef ref, {bool replay = false}) {
  // Warms the tree, so the guide can note where it stood and the reward
  // card can grow it from there.
  ref.read(treeStateProvider);
  ref.read(tourControllerProvider.notifier).start(replay: replay);
}
