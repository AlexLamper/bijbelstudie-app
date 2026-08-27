import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../bible/present/bible_providers.dart';
import '../../onboarding/data/onboarding_gate.dart';
import '../../onboarding/data/onboarding_storage.dart';
import '../present/auth_controller.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Artificial delay to show logo
    await Future.delayed(const Duration(seconds: 2));

    final storage = ref.read(authStorageProvider);
    final token = await storage.getToken();
    final hasSession = token != null && token.isNotEmpty;

    if (hasSession) {
      // Links RevenueCat to the account so store purchases attach to this
      // user instead of an anonymous RevenueCat id.
      await ref.read(authControllerProvider.notifier).restoreSession();

      // A dead refresh token during restoreSession already triggered
      // ApiClient.onSessionExpired, which clears storage and sends the router
      // to /login itself. Falling through to the dashboard route below would
      // immediately clobber that redirect for an account that is no longer
      // signed in. Re-reading the token (rather than the controller's state)
      // is what tells the two failure modes apart: a generic offline hiccup
      // in restoreSession leaves the token alone and must still reach the
      // dashboard for offline reading, same as before.
      final stillHasToken = await storage.getToken();
      if (stillHasToken == null || stillHasToken.isEmpty) return;

      // A signed-in user never sees the pre-login marketing intro again - it
      // is a first-run pitch for visitors who still have to create an
      // account. Mark it seen so signing out later also skips it. This is
      // independent of the setup wizard and the tour below, which track
      // whether *this* account has been configured and shown around.
      await ref.read(onboardingStorageProvider).markSeen();

      // Starts the reader working out where it was left. It hydrates itself on
      // first read anyway, but doing it here means it happens behind the splash
      // and the auth call rather than behind a spinner in the reader. It has to
      // come after restoreSession so the request goes out signed in.
      ref.read(readerLocationProvider);

      final route = await resolvePostAuthRoute(ref);
      if (mounted) context.go(route);
      return;
    }

    final hasSeenOnboarding = await ref
        .read(onboardingStorageProvider)
        .hasSeen();
    if (!mounted) return;
    context.go(hasSeenOnboarding ? '/login' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    // Paper background with the site wordmark — the site has no dark hero.
    return const Scaffold(
      backgroundColor: AppTheme.paper,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BijbelStudieWordmark(fontSize: 34),
            SizedBox(height: 18),
            Text('LEES EN BESTUDEER DE BIJBEL', style: AppTheme.overline),
            SizedBox(height: 44),
            AppLoader(size: 20),
          ],
        ),
      ),
    );
  }
}

/// `<span class="font-display text-xl font-semibold tracking-[-0.02em]
///   text-ink">Bijbel<span class="text-teal">Studie</span></span>`
class BijbelStudieWordmark extends StatelessWidget {
  const BijbelStudieWordmark({super.key, this.fontSize = 20});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: AppTheme.displayFontName,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: fontSize * -0.02,
          color: AppTheme.ink,
        ),
        children: const [
          TextSpan(text: 'Bijbel'),
          TextSpan(
            text: 'Studie',
            style: TextStyle(color: AppTheme.lapis),
          ),
        ],
      ),
    );
  }
}
