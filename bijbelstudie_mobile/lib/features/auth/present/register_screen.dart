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
import 'widgets/apple_sign_in_button.dart';
import 'widgets/google_sign_in_button.dart';
import 'widgets/user_data_info_link.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  /// Whether the in-flight auth call is the plain register form rather than
  /// "Verder met Google" below - the latter can just as well sign an
  /// *existing* Google-linked account back in, so only this form is a
  /// guaranteed-new account that can skip straight to the setup wizard
  /// without asking the server first.
  bool _isRegisterAction = false;

  Future<void> _register() async {
    _isRegisterAction = true;
    final auth = ref.read(authControllerProvider.notifier);
    await auth.register(
      _nameController.text,
      _emailController.text,
      _passwordController.text,
    );
  }

  Future<void> _registerWithGoogle() async {
    _isRegisterAction = false;
    final auth = ref.read(authControllerProvider.notifier);
    await auth.signInWithGoogle();
  }

  Future<void> _registerWithApple() async {
    // Same reasoning as Google: this can sign an existing Apple-linked
    // account back in, so the server decides where they land.
    _isRegisterAction = false;
    final auth = ref.read(authControllerProvider.notifier);
    await auth.signInWithApple();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      // See the matching guard in `login_screen.dart`: whichever of the two
      // auth screens is on top is the one that decides where the user goes.
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;

      if (next.hasValue && next.value != null) {
        // `onError` is not optional here. The user is authenticated the
        // moment this listener runs; if route resolution rejects and nothing
        // catches it, the failure disappears into the zone and they are left
        // sitting on this screen, signed in, with no error and no navigation.
        // The dashboard is the safe destination — the wizard and the tour can
        // still be replayed from Profiel.
        resolvePostAuthRoute(ref, isNewAccount: _isRegisterAction)
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
      appBar: AppBar(
        backgroundColor: AppTheme.paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          color: AppTheme.inkSoft,
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            const Eyebrow('Registreren'),
            const SizedBox(height: 18),
            const Text('Account aanmaken', style: AppTheme.displayLarge),
            const SizedBox(height: 14),
            const Text(
              'Maak een account aan om je leesvoortgang, notities en '
              'markeringen op te slaan en te synchroniseren met de website.',
              style: AppTheme.bodyLead,
            ),
            const SizedBox(height: 36),
            CustomTextField(
              label: 'Naam',
              hintText: 'Je naam',
              controller: _nameController,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 18),
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
              text: 'Registreren',
              isLoading: isLoading,
              onPressed: isLoading ? null : _register,
            ),
            if (hasSocialLoginOption) ...[
              const SizedBox(height: 28),
              Row(
                children: [
                  const Expanded(child: RuleLine()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('OF GA VERDER MET', style: AppTheme.overline),
                  ),
                  const Expanded(child: RuleLine()),
                ],
              ),
              const SizedBox(height: 20),
              if (showGoogleSignIn)
                buildGoogleSignInButton(
                  context: context,
                  isLoading: isLoading || !isGoogleReady,
                  onPressed: (isLoading || !isGoogleReady) ? null : _registerWithGoogle,
                ),
              if (showGoogleSignIn && showAppleSignIn) const SizedBox(height: 12),
              if (showAppleSignIn)
                buildAppleSignInButton(
                  isLoading: isLoading,
                  onPressed: isLoading ? null : _registerWithApple,
                ),
            ],
            const SizedBox(height: 32),
            const RuleLine(),
            const SizedBox(height: 20),
            Center(
              child: TextButton(
                onPressed: () => context.pop(),
                child: Text.rich(
                  TextSpan(
                    style: AppTheme.bodyMuted,
                    children: const [
                      TextSpan(text: 'Heb je al een account?  '),
                      TextSpan(
                        text: 'Inloggen',
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
