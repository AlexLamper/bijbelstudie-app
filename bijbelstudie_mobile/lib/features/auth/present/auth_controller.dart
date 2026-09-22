import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart' as google_auth;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../../core/config/apple_sign_in_config.dart';
import '../../../core/config/google_sign_in_config.dart';
import '../data/auth_repository.dart';
import '../../../core/data/payload_cache.dart';
import '../../../core/api/api_client.dart';
import '../data/auth_local_storage.dart';
import '../domain/user.dart';
import '../../levensboom/data/levensboom_repository.dart';
import '../../levensboom/present/levensboom_providers.dart';
import '../../notes/data/notes_repository.dart';
import '../../premium/present/premium_controller.dart';
import '../../profile/data/profile_repository.dart';

// Provides shared access
final authStorageProvider = Provider((ref) => AuthLocalStorage());
final apiClientProvider = Provider(
  (ref) => ApiClient(ref.watch(authStorageProvider)),
);
final authRepositoryProvider = Provider(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(authStorageProvider),
  ),
);

// State management
final authControllerProvider = AsyncNotifierProvider<AuthController, User?>(() {
  return AuthController();
});

final googleSignInInitProvider = FutureProvider<void>((ref) async {
  return ref
      .read(authControllerProvider.notifier)
      .ensureGoogleSignInInitialized();
});

class AuthController extends AsyncNotifier<User?> {
  bool _googleSignInInitialized = false;

  /// Per-platform client ids live in [GoogleSignInConfig]; nothing is
  /// hardcoded here.
  Future<void> ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    await google_auth.GoogleSignIn.instance.initialize(
      clientId: GoogleSignInConfig.clientId,
      serverClientId: GoogleSignInConfig.serverClientId,
    );
    _googleSignInInitialized = true;
  }

  @override
  FutureOr<User?> build() {
    return null;
  }

  /// Link RevenueCat to the authenticated user so subscription status
  /// is correctly attributed across devices.
  Future<void> _linkRevenueCat(User? user) async {
    if (user == null || kIsWeb) return;
    try {
      // Bounded. The sign-in screens keep their button in the loading state
      // until the auth state settles, so anything awaited between a successful
      // credential check and `state = AsyncValue.data(user)` is a spinner the
      // user cannot escape. `Purchases.logIn` is a network identity switch and
      // carries no deadline of its own; on a stalled connection it is the
      // difference between a slow login and one that never finishes.
      await Purchases.logIn(user.id).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Non-fatal: RC linking failure shouldn't block auth. The next launch
      // re-links in `restoreSession`.
    }
  }

  /// Pushes anything queued while signed out.
  ///
  /// Without this, only [restoreSession] ever flushed the queue - a device
  /// that writes a note offline, then logs out and straight back in (or logs
  /// into a second account), would leave that write stuck until the next app
  /// launch. `listNotes`/`listBookmarks`/etc. already merge the local queue in
  /// so nothing is invisible meanwhile, but the server itself, and any other
  /// device on the same account, should not have to wait for a relaunch.
  Future<void> _flushPendingAfterSignIn() async {
    try {
      await ref.read(notesRepositoryProvider).flushPendingChanges();
    } catch (_) {
      // Best-effort: a fresh login is not blocked on this, and the next
      // successful write or app launch will try again.
    }
  }

  /// The single "you are signed in now" step for every sign-in path.
  ///
  /// Two rules, both learned from a login that appeared to do nothing:
  ///
  ///  1. A null user is an error, not a success. `state = AsyncValue.data(null)`
  ///     reads as "signed out" to every listener, so the screens neither
  ///     navigated nor showed a message — the button just stopped spinning.
  ///  2. Nothing best-effort runs *before* the state is published. Queue
  ///     flushing is a whole sync round trip whose size depends on how much
  ///     the device wrote while offline; awaiting it here held an
  ///     already-authenticated user on the login screen for its duration.
  ///     That is also the asymmetry that made login look broken while
  ///     registration looked fine: a brand-new account has an empty queue.
  Future<void> _completeSignIn(User? user) async {
    if (user == null) {
      throw Exception(
        'Inloggen gelukt, maar de server stuurde geen accountgegevens terug. '
        'Probeer het opnieuw.',
      );
    }
    await _linkRevenueCat(user);
    state = AsyncValue.data(user);
    // The tree is per account. Whatever was loaded before this sign-in
    // belonged to someone else (or to this address before it was deleted and
    // re-created), so it is fetched again rather than shown as if it were
    // this reader's.
    ref.invalidate(treeStateProvider);
    // Likewise the RevenueCat CustomerInfo, which hides every upsell while it
    // reports Pro - it must describe this account, not the previous one.
    ref.invalidate(premiumControllerProvider);
    unawaited(_flushPendingAfterSignIn());
  }

  /// Restore a persisted session on app launch.
  ///
  /// Without this, a returning user (token already stored) reaches the app
  /// without RevenueCat being logged in, so a purchase is attributed to an
  /// anonymous RevenueCat id and the store webhook can't attach premium to
  /// their account.
  Future<void> restoreSession() async {
    final token = await ref.read(authStorageProvider).getToken();
    if (token == null || token.isEmpty) {
      state = const AsyncValue.data(null);
      return;
    }
    try {
      final profile = await ref.read(profileRepositoryProvider).getProfile();
      final user = User(
        id: profile.id,
        name: profile.name,
        email: profile.email,
        image: profile.image,
        isPro: profile.isPro,
        proSource: profile.proSource,
        proExpiresAt: profile.proExpiresAt,
        isAdmin: profile.isAdmin,
      );
      await _linkRevenueCat(user);
      // Self-heal accounts whose purchase webhook never landed: ask the server
      // to reconcile against RevenueCat once RC is linked. Best-effort.
      try {
        await ref.read(profileRepositoryProvider).syncPremium();
      } catch (_) {}
      // Push anything written while the device was offline. The profile fetch
      // above just succeeded, so the connection is known good.
      try {
        await ref.read(notesRepositoryProvider).flushPendingChanges();
      } catch (_) {}
      state = AsyncValue.data(user);
    } catch (_) {
      // Best-effort: keep the token-based session even if profile fetch fails
      // (e.g. offline). RevenueCat linking retries on the next launch.
    }
  }

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final repository = ref.read(authRepositoryProvider);
      final user = await repository.login(email, password);
      await _completeSignIn(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> register(String name, String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final repository = ref.read(authRepositoryProvider);
      final user = await repository.register(name, email, password);
      await _completeSignIn(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Signs in with Google — and registers the account when there isn't one.
  ///
  /// This is deliberately a single entry point for both: `/api/v1/auth/google`
  /// finds, links or creates (see [AuthRepository.loginWithGoogle]), exactly
  /// like the website. So the button on `/login` and the one on `/register`
  /// call this same method and a first-time user needs no second step.
  Future<void> signInWithGoogle() async {
    try {
      await ensureGoogleSignInInitialized();
      final google_auth.GoogleSignInAccount account = await google_auth
          .GoogleSignIn
          .instance
          .authenticate(scopeHint: ['email', 'profile']);
      await _completeGoogleSignIn(account);
    } on google_auth.GoogleSignInException catch (e, st) {
      if (e.code == google_auth.GoogleSignInExceptionCode.canceled) {
        return; // User dismissed the Google dialog: not an error.
      }
      if (e.code == google_auth.GoogleSignInExceptionCode.interrupted &&
          await _retryGoogleAfterInterrupt()) {
        return;
      }
      // `GoogleSignInException.toString()` is English and names the plugin's
      // own enum; it was going straight into the snackbar.
      state = AsyncValue.error(Exception(_googleErrorMessage(e)), st);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// One silent retry after Android reports `interrupted`.
  ///
  /// Credential Manager reports that when its sheet closes unexpectedly even
  /// though a credential is available, and retrying the lightweight path
  /// recovers it. Returns whether this method has dealt with the failure.
  ///
  /// What it must *not* do is swallow a failure that happened after the retry
  /// found a credential. That is no longer an interrupted dialog — it is the
  /// server or the network answering — and it used to be caught and replaced
  /// with "controleer SHA-1/SHA-256 van de release key in Google Cloud", which
  /// is advice about signing certificates aimed at a developer. A first-time
  /// user reading that had no idea their account simply had not been created.
  Future<bool> _retryGoogleAfterInterrupt() async {
    google_auth.GoogleSignInAccount? current;
    try {
      current = await google_auth.GoogleSignIn.instance
          .attemptLightweightAuthentication();
    } catch (_) {
      return false; // Nothing recovered; report the original interruption.
    }
    if (current == null) return false;
    try {
      await _completeGoogleSignIn(current);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
    return true;
  }

  /// Dutch copy for every way `google_sign_in` can fail, in words that say
  /// what the reader can do next.
  static String _googleErrorMessage(google_auth.GoogleSignInException e) {
    switch (e.code) {
      case google_auth.GoogleSignInExceptionCode.canceled:
        return 'Inloggen met Google is geannuleerd.';
      case google_auth.GoogleSignInExceptionCode.interrupted:
        return 'Inloggen met Google werd onderbroken. Probeer het opnieuw.';
      case google_auth.GoogleSignInExceptionCode.clientConfigurationError:
      case google_auth.GoogleSignInExceptionCode.providerConfigurationError:
        return 'Inloggen met Google is op dit apparaat niet beschikbaar. '
            'Maak een account met je e-mailadres en wachtwoord.';
      case google_auth.GoogleSignInExceptionCode.uiUnavailable:
        return 'Het Google-venster kon niet worden geopend. Probeer het opnieuw.';
      case google_auth.GoogleSignInExceptionCode.userMismatch:
        return 'Dit is een ander Google-account dan het vorige. Log uit bij '
            'Google en probeer het opnieuw.';
      case google_auth.GoogleSignInExceptionCode.unknownError:
        // The Android plugin reports "no Google account on this device" as an
        // unknownError with this description, and it is the one case a reader
        // can actually fix themselves.
        if (e.description?.contains('No credential available') ?? false) {
          return 'Er is geen Google-account op dit apparaat. Voeg er een toe '
              'bij Instellingen, of maak een account met je e-mailadres.';
        }
        return 'Inloggen met Google mislukt. Probeer het opnieuw of gebruik je '
            'e-mailadres en wachtwoord.';
    }
  }

  Future<void> _completeGoogleSignIn(google_auth.GoogleSignInAccount account) async {
    final google_auth.GoogleSignInAuthentication auth = account.authentication;
    final String? idToken = auth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception(
        'Google gaf geen inlogtoken terug. Probeer het opnieuw of kies een '
        'ander Google-account.',
      );
    }

    state = const AsyncValue.loading();
    final repository = ref.read(authRepositoryProvider);
    // Registration and login are the same request: the server creates the
    // account when it does not recognise this Google identity yet.
    final user = await repository.loginWithGoogle(
      idToken: idToken,
      email: account.email,
      name: account.displayName,
    );
    await _completeSignIn(user);
  }

  Future<void> signInWithApple() async {
    try {
      var useWebFallback = false;
      final isAvailable = await SignInWithApple.isAvailable();
      if (!isAvailable && !AppleSignInConfig.hasWebFallbackConfig) {
        throw Exception(
          'Apple-login is niet beschikbaar op dit apparaat. Voeg web fallback toe met APPLE_SERVICE_ID en APPLE_REDIRECT_URI of controleer je Apple ID/provisioning.',
        );
      }
      if (!isAvailable && AppleSignInConfig.hasWebFallbackConfig) {
        useWebFallback = true;
      }

      final credential = await _getAppleCredentialWithFallback(
        forceWebFallback: useWebFallback,
      );

      final identityToken = credential.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        throw Exception('Apple gaf geen identityToken terug. Probeer opnieuw.');
      }

      state = const AsyncValue.loading();
      final repository = ref.read(authRepositoryProvider);
      final user = await repository.loginWithApple(
        identityToken: identityToken,
        authorizationCode: credential.authorizationCode,
        givenName: credential.givenName,
        familyName: credential.familyName,
        email: credential.email,
      );
      await _completeSignIn(user);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return;
      }
      if (e.code == AuthorizationErrorCode.unknown) {
        state = AsyncValue.error(
          Exception(
            'Apple-login kon niet worden gestart (AuthorizationError 1000). Dit is meestal een iOS-device/provisioning probleem: gebruik een echte iPhone (of iOS-simulator met Apple ID), vernieuw signing/provisioning in Xcode voor bundle ID com.bijbel-studie.app en installeer de app opnieuw.',
          ),
          StackTrace.current,
        );
        return;
      }
      state = AsyncValue.error(e, StackTrace.current);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<AuthorizationCredentialAppleID> _getAppleCredentialWithFallback({
    required bool forceWebFallback,
  }) async {
    const scopes = [
      AppleIDAuthorizationScopes.email,
      AppleIDAuthorizationScopes.fullName,
    ];

    if (forceWebFallback) {
      final credential = await _getAppleCredentialViaWeb(scopes);
      if (credential != null) return credential;
      throw Exception(
        'Apple web-fallback is niet geconfigureerd. Stel APPLE_SERVICE_ID en APPLE_REDIRECT_URI in.',
      );
    }

    try {
      return await SignInWithApple.getAppleIDCredential(scopes: scopes);
    } on SignInWithAppleAuthorizationException catch (e) {
      // AuthorizationError 1000 is often entitlement/provisioning related.
      if (e.code == AuthorizationErrorCode.unknown) {
        final viaWeb = await _getAppleCredentialViaWeb(scopes);
        if (viaWeb != null) return viaWeb;
      }
      rethrow;
    }
  }

  Future<AuthorizationCredentialAppleID?> _getAppleCredentialViaWeb(
    List<AppleIDAuthorizationScopes> scopes,
  ) async {
    if (!AppleSignInConfig.hasWebFallbackConfig) return null;
    final redirectUri = AppleSignInConfig.redirectUri;
    if (redirectUri == null) return null;

    return SignInWithApple.getAppleIDCredential(
      scopes: scopes,
      webAuthenticationOptions: WebAuthenticationOptions(
        clientId: AppleSignInConfig.serviceId,
        redirectUri: redirectUri,
      ),
    );
  }

  /// Called when [ApiClient.onSessionExpired] fires - the refresh token is
  /// dead and `_storage.clear()` already ran. Only the in-memory state needs
  /// to catch up: without this the app kept rendering as if the account were
  /// still signed in while every authenticated request 401'd and every write
  /// was silently queued as if it were an offline blip.
  void signOutExpiredSession() {
    if (state.value == null) return; // already signed out
    state = const AsyncValue.data(null);
  }

  Future<void> logout() async {
    state = const AsyncValue.loading();
    final repository = ref.read(authRepositoryProvider);
    await repository.logout();
    // Per-account state that lives on the device goes with the session.
    await LevensboomRepository.clearCache();
    await PayloadCache.clearAll();

    if (GoogleSignInConfig.isAvailable) {
      // Never fatal: a user who cannot sign out is far worse than a Google
      // session that outlives the app's own.
      try {
        await ensureGoogleSignInInitialized();
        await google_auth.GoogleSignIn.instance.signOut();
      } catch (_) {}
    }

    if (!kIsWeb) {
      try {
        await Purchases.logOut();
      } catch (_) {}
    }
    ref.invalidate(premiumControllerProvider);

    state = const AsyncValue.data(null);
  }
}
