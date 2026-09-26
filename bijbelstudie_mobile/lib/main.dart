import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'core/app_lifecycle.dart';
import 'core/notifications/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/config/app_config.dart';
import 'core/config/preview_config.dart';
import 'core/config/revenuecat_config.dart';
import 'core/preview/preview_data.dart';
import 'core/ui/environment_badge.dart';
import 'features/feedback/present/review_prompt_host.dart';
import 'features/onboarding/present/tour_overlay.dart';
import 'features/settings/present/theme_mode_provider.dart';
import 'core/platform/android_sdk.dart';

Future<void> _initRevenueCat() async {
  if (kIsWeb) return;
  final apiKey = RevenueCatConfig.sdkPublicApiKey();
  assert(() {
    debugPrint(
      '[RevenueCat][Main] key source: ${RevenueCatConfig.sdkKeySource()}',
    );
    return true;
  }());
  if (apiKey.isEmpty) {
    assert(() {
      debugPrint(
        'RevenueCat: no API key. Pass --dart-define=REVENUECAT_TEST_KEY=... '
        'or REVENUECAT_APPLE_KEY / REVENUECAT_GOOGLE_KEY. See revenuecat_config.dart.',
      );
      return true;
    }());
    return;
  }
  await Purchases.setLogLevel(
    AppConfig.isProduction ? LogLevel.error : LogLevel.debug,
  );
  await Purchases.configure(PurchasesConfiguration(apiKey));
  assert(() {
    Purchases.addCustomerInfoUpdateListener((customerInfo) {
      final active = customerInfo.entitlements.active.keys.join(', ');
      debugPrint(
        '[RevenueCat][Main] CustomerInfo updated. Active entitlements: '
        '${active.isEmpty ? '(none)' : active}',
      );
    });
    debugPrint('[RevenueCat][Main] SDK configured with debug listener.');
    return true;
  }());
}

/// Brings the notification service up before anything schedules:
///
/// - sets `tz.local` from the real IANA zone (the old code initialised the
///   zone database but never set `tz.local`, so an 08:00 reminder fired at
///   08:00 **UTC** — `RETENTION_PLAN.md` §1);
/// - registers the new Android channels and deletes the legacy
///   `daily_reading` channel;
/// - reads a cold-start notification tap, which the splash routes to once the
///   session is checked.
///
/// The actual (re)scheduling of the ladder is done by `notificationRecompute`,
/// which runs from `appLifecycleProvider` the moment the app tree builds and on
/// every foreground thereafter.
Future<void> _initNotifications() async {
  if (kIsWeb) return;
  await NotificationService.instance.initialise();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the status bar and the navigation bar. Without this Android
  // reserves both strips and fills them with a colour of its own, which is
  // what put a mismatched band above every header and below every bottom bar.
  // Each screen's header and footer now paint into the inset themselves.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Before the first overlay style is pushed: the API level decides whether
  // the bar colours are sent at all. Android 15 ignores them and deprecated
  // the setters, Android 14 and below still need them. See AndroidSdk.
  await AndroidSdk.load();
  SystemChrome.setSystemUIOverlayStyle(AppTheme.overlayStyle);

  if (PreviewConfig.enabled) {
    // Point image URLs at the live site so artwork resolves without a local
    // backend, then run with canned data and no auth.
    AppConfig.setCustomApiBaseUrl('https://www.bijbelstudie.io/api/v1');
    debugPrint('[Preview] Design-preview mode active - using canned data.');
    runApp(PreviewData.scope(const BijbelStudieApp()));
    return;
  }

  // Both inits are bounded, not just guarded. A `try` only survives a plugin
  // that *fails*; a platform channel that never answers (a store client that
  // cannot reach the device's account, a notification channel registration
  // waiting on a locked keystore) leaves `main` awaiting forever, `runApp` is
  // never called, and the launch screen stays up with no Flutter behind it —
  // the app "not getting past loading". Neither of these is worth the app not
  // starting: RevenueCat re-links on the next entitlement check and the
  // notification scheduler re-runs on the first foreground.
  const initBudget = Duration(seconds: 8);

  try {
    await _initRevenueCat().timeout(initBudget);
  } catch (e, st) {
    // A RevenueCat outage must never stop the app from starting: the reader
    // works without an entitlement check.
    assert(() {
      debugPrint('[RevenueCat][Main] init failed: $e\n$st');
      return true;
    }());
  }

  try {
    await _initNotifications().timeout(initBudget);
  } catch (e, st) {
    // A notifications hiccup must never stop the app from starting either;
    // the settings tile re-checks the real state itself and will not claim
    // the reminder is on if this failed.
    assert(() {
      debugPrint('[Notifications][Main] init failed: $e\n$st');
      return true;
    }());
  }
  runApp(const ProviderScope(child: BijbelStudieApp()));
}

class BijbelStudieApp extends ConsumerWidget {
  const BijbelStudieApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Must be watched before any screen can make an authenticated request -
    // it is what turns a dead refresh token into an actual sign-out instead
    // of tokens quietly vanishing while the app keeps acting logged in.
    ref.watch(sessionExpiryWiringProvider);

    // Registers the lifecycle observer: re-runs the notification scheduler on
    // launch and on every foreground.
    ref.watch(appLifecycleProvider);

    final routerConfig = ref.watch(routerProvider);

    // Dark mode, resolved before anything below this line builds.
    //
    // App review 1.0 (7) was rejected under guideline 4 because `AppTheme`
    // published its type ramp as `static const TextStyle`s: a const cannot
    // depend on brightness, so thirteen of the fourteen baked a light colour
    // and painted near-black on the dark scaffold. The ramp and the semantic
    // palette are getters now, resolved against one app-wide flag, and this
    // is where that flag is set — before `MaterialApp` builds, so the very
    // first frame is already correct.
    final themeMode = ref.watch(themeModeProvider);
    final brightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    if (AppTheme.applyBrightness(brightness)) {
      SystemChrome.setSystemUIOverlayStyle(AppTheme.overlayStyle);
    }

    // Keyed on the brightness on purpose. `AppTheme`'s tokens are read at
    // build time from a static flag, not from an InheritedWidget, so a plain
    // `Theme` swap would only rebuild the widgets that call `Theme.of` and
    // leave every `AppTheme.ink` in the tree painting the old palette. The key
    // discards the subtree instead. go_router holds the route stack in
    // `routerConfig`, so the current location survives.
    return MaterialApp.router(
      key: ValueKey(brightness),
      title: 'BijbelStudie',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: routerConfig,
      // The app is Dutch-only, so the framework's own strings are too: the
      // date and time pickers, "Terug", "Annuleren".
      locale: const Locale('nl', 'NL'),
      supportedLocales: const [Locale('nl', 'NL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // The guided tour paints a spotlight over the running app, so it has to
      // sit above the router's Navigator - including the bottom tab bar, which
      // two of its steps point at. It builds nothing while the tour is off.
      // The rating prompt sits outside the tour host on purpose: it renders
      // nothing until its gate opens, and it refuses to open while the tour is
      // running, so the two can never fight over the same window.
      // The environment badge wraps the lot, so it is visible over the tour
      // spotlight too - "which build is this?" is exactly the question you ask
      // while something else is on screen. Renders nothing on a live build.
      builder: (context, child) => EnvironmentBadge(
        child: ReviewPromptHost(
          enabled: !PreviewConfig.enabled,
          child: TourHost(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
