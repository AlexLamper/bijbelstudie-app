import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../bible/present/bible_providers.dart';
import '../../onboarding/data/onboarding_gate.dart';
import '../../onboarding/data/onboarding_storage.dart';
import '../present/auth_controller.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  /// Fills the loading bar. Runs once over ~1.6s and is what the reader
  /// watches instead of a spinner. The real auth work usually finishes before
  /// it does; [_leave] waits for the bar to land so the hand-off looks
  /// deliberate rather than cut short.
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..forward();

  /// The short "into the app" move: the wordmark scales up a touch and the
  /// whole splash fades out, so the first real screen is dived into rather
  /// than swapped in.
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  @override
  void dispose() {
    _progress.dispose();
    _exit.dispose();
    super.dispose();
  }

  /// Plays the exit animation, then routes on. Every navigation in
  /// [_checkAuth] goes through here so the transition is never skipped.
  Future<void> _leave(String route) async {
    if (_leaving || !mounted) return;
    _leaving = true;
    // Let the bar finish if it has not yet, then dive in.
    if (_progress.value < 1) await _progress.forward();
    if (!mounted) return;
    await _exit.forward();
    if (mounted) context.go(route);
  }

  Future<void> _checkAuth() async {
    // Hold on the wordmark while the loading bar fills.
    await Future.delayed(const Duration(milliseconds: 900));

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
      await _leave(route);
      return;
    }

    final hasSeenOnboarding = await ref
        .read(onboardingStorageProvider)
        .hasSeen();
    if (!mounted) return;
    await _leave(hasSeenOnboarding ? '/login' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    // Paper background with the site wordmark — the site has no dark hero.
    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: Center(
        child: AnimatedBuilder(
          animation: Listenable.merge([_progress, _exit]),
          builder: (context, _) {
            final exit = Curves.easeIn.transform(_exit.value);
            return Opacity(
              opacity: 1 - exit,
              child: Transform.scale(
                scale: 1 + exit * 0.12,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BijbelStudieWordmark(fontSize: 34),
                    const SizedBox(height: 18),
                    Text(
                      'LEES EN BESTUDEER DE BIJBEL',
                      style: AppTheme.overline,
                    ),
                    const SizedBox(height: 44),
                    _LoadingBar(value: Curves.easeOut.transform(_progress.value)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A slim determinate bar — the professional stand-in for the old spinner on
/// the launch screen.
class _LoadingBar extends StatelessWidget {
  const _LoadingBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: 4,
          backgroundColor: AppTheme.paperSunkenStrong,
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.lapis),
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
    // Read through Theme rather than straight off AppTheme.ink. Every call
    // site builds this widget `const`, and an identical const widget is never
    // rebuilt when its parent rebuilds - so on a light/dark switch the wordmark
    // kept the colour it was first painted in, which on light mode left
    // "Bijbel" in near-white on paper. Depending on an inherited widget is what
    // makes it repaint: the dependency schedules the rebuild regardless of the
    // const identity.
    final ink = Theme.of(context).colorScheme.onSurface;

    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: AppTheme.displayFontName,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: fontSize * -0.02,
          color: ink,
        ),
        children: [
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
