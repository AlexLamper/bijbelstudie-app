import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart' as google_auth;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../../core/config/apple_sign_in_config.dart';
import '../../../core/config/google_sign_in_config.dart';
import '../data/auth_repository.dart';
import '../../../core/api/api_client.dart';
import '../data/auth_local_storage.dart';
import '../domain/user.dart';
import '../../notes/data/notes_repository.dart';
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
        return; // User canceled the sign in dialog.
      }
      if (e.code == google_auth.GoogleSignInExceptionCode.interrupted) {
        // Android can report interrupted when UI flow closed unexpectedly.
        final current = await google_auth.GoogleSignIn.instance
            .attemptLightweightAuthentication();
        if (current != null) {
          try {
            await _completeGoogleSignIn(current);
            return;
          } catch (_) {}
        }
        state = AsyncValue.error(
          Exception(
            'Google-login onderbroken op Android. Controleer SHA-1/SHA-256 van de release key in Google Cloud OAuth client.',
          ),
          st,
        );
        return;
      }
      state = AsyncValue.error(e, st);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> _completeGoogleSignIn(google_auth.GoogleSignInAccount account) async {
    final google_auth.GoogleSignInAuthentication auth = account.authentication;
    final String? idToken = auth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception(
        'Google gaf geen idToken terug. Probeer opnieuw of kies een ander account.',
      );
    }

    state = const AsyncValue.loading();
    final repository = ref.read(authRepositoryProvider);
    final user = await repository.loginWithGoogle(idToken);
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

    state = const AsyncValue.data(null);
  }
}
