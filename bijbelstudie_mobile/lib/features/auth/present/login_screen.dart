import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/google_sign_in_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/primary_button.dart';
import '../../../core/ui/custom_text_field.dart';
import '../../onboarding/data/onboarding_gate.dart';
import 'auth_controller.dart';
import 'splash_screen.dart' show BijbelStudieWordmark;
import 'widgets/apple_sign_in_button.dart';
import 'widgets/google_sign_in_button.dart';
import 'widgets/user_data_info_link.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.sessionExpired = false});

  /// Set when the router lands here after [ApiClient.onSessionExpired] fired,
  /// so the reader is told why they are suddenly looking at the login screen
  /// instead of assuming the app just lost their session for no reason.
  final bool sessionExpired;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    if (widget.sessionExpired) {
      // Post-frame: a SnackBar needs a ScaffoldMessenger already in the tree.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Je sessie is verlopen. Log opnieuw in.')),
        );
      });
    }
  }

  Future<void> _login() async {
    final auth = ref.read(authControllerProvider.notifier);
    await auth.login(_emailController.text, _passwordController.text);
  }

  Future<void> _loginWithGoogle() async {
    final auth = ref.read(authControllerProvider.notifier);
    await auth.signInWithGoogle();
  }

  Future<void> _loginWithApple() async {
    final auth = ref.read(authControllerProvider.notifier);
    await auth.signInWithApple();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      // `/register` is *pushed* on top of this screen, so this State stays
      // mounted and keeps listening while the user registers. Both screens
      // then saw the same success and both called `context.go`, racing over
      // where a brand-new account lands — and this one resolves the route
      // with `isNewAccount: false`, so when it won, a user who had just
      // created an account was sent to the dashboard instead of the setup
      // wizard. Only the screen actually on top may act.
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;

      if (next.hasValue && next.value != null) {
        // An existing account may already have finished setup and the tour
        // on the website or another device - resolvePostAuthRoute is what
        // checks that before deciding to show them again.
        // `onError` is not optional here. The user is authenticated the
        // moment this listener runs; if route resolution rejects and nothing
        // catches it, the failure disappears into the zone and they are left
        // sitting on this screen, signed in, with no error and no navigation.
        // The dashboard is the safe destination — the wizard and the tour can
        // still be replayed from Profiel.
        resolvePostAuthRoute(ref)
            .then((route) {
              if (context.mounted) context.go(route);
            })
            .catchError((_) {
              if (context.mounted) context.go('/dashboard');
            });
      } else if (next.hasError) {
        final msg = next.error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.replaceAll('Exception: ', ''))),
        );
      }
    });

    final state = ref.watch(authControllerProvider);
    // Guideline 4.8: offering Google on iOS obliges the app to offer Sign in
    // with Apple beside it. Until now neither appeared on iOS, so the rule was
    // satisfied by having nothing to satisfy.
    final showAppleSignIn = isAppleSignInAvailable;

    final googleInit = GoogleSignInConfig.isAvailable
        ? ref.watch(googleSignInInitProvider)
        : const AsyncValue<void>.data(null);
    // A client id that Google rejects makes `initialize` throw. That used to
    // leave `isGoogleInit` false forever, and because the whole screen shared
    // one `isLoading` flag, it disabled the email/password button too - a
    // misconfigured Google client took down the login that does not use it.
    // Google's own readiness is now the Google button's business alone.
    // Config, not platform. iOS used to be excluded outright because no iOS
    // OAuth client existed; the button now appears wherever a client id was
    // actually built in - see GoogleSignInConfig.
    final showGoogleSignIn = GoogleSignInConfig.isAvailable && !googleInit.hasError;
    final isGoogleReady = googleInit.hasValue;

    final hasSocialLoginOption = showGoogleSignIn || showAppleSignIn;
    final isLoading = state.isLoading;

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
          children: [
            const BijbelStudieWordmark(fontSize: 22),
            const SizedBox(height: 44),
            const Eyebrow('Inloggen'),
            const SizedBox(height: 18),
            Text('Welkom terug', style: AppTheme.displayLarge),
            const SizedBox(height: 14),
            Text(
              'Log in om verder te lezen waar je gebleven was en je notities '
              'terug te vinden.',
              style: AppTheme.bodyLead,
            ),
            const SizedBox(height: 36),
            CustomTextField(
              label: 'E-mail',
              hintText: 'jij@voorbeeld.nl',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 18),
            CustomTextField(
              label: 'Wachtwoord',
              hintText: '••••••••',
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: AppTheme.inkMuted,
                ),
                tooltip: _obscurePassword
                    ? 'Wachtwoord tonen'
                    : 'Wachtwoord verbergen',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            const SizedBox(height: 32),
            PrimaryButton(
              text: 'Inloggen',
              isLoading: isLoading,
              onPressed: isLoading ? null : _login,
            ),
            if (hasSocialLoginOption) ...[
              const SizedBox(height: 28),
              // `border-t border-rule` with the label sitting on the rule.
              Row(
                children: [
                  const Expanded(child: RuleLine()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('OF LOG IN MET', style: AppTheme.overline),
                  ),
                  const Expanded(child: RuleLine()),
                ],
              ),
              const SizedBox(height: 20),
              if (showGoogleSignIn)
                buildGoogleSignInButton(
                  context: context,
                  isLoading: isLoading || !isGoogleReady,
                  onPressed: (isLoading || !isGoogleReady) ? null : _loginWithGoogle,
                ),
              if (showGoogleSignIn && showAppleSignIn) const SizedBox(height: 12),
              if (showAppleSignIn)
                buildAppleSignInButton(
                  isLoading: isLoading,
                  onPressed: isLoading ? null : _loginWithApple,
                ),
            ],
            const SizedBox(height: 32),
            const RuleLine(),
            const SizedBox(height: 20),
            Center(
              child: TextButton(
                onPressed: () => context.push('/register'),
                child: Text.rich(
                  TextSpan(
                    style: AppTheme.bodyMuted,
                    children: [
                      TextSpan(text: 'Nog geen account?  '),
                      TextSpan(
                        text: 'Registreren',
                        style: TextStyle(
                          color: AppTheme.lapis,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(child: buildUserDataInfoLink(context)),
          ],
        ),
      ),
    );
  }
}
