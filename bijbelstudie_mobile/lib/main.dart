import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/notifications/reminder_copy.dart';
import 'core/notifications/reminder_service.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/config/app_config.dart';
import 'core/config/preview_config.dart';
import 'core/config/revenuecat_config.dart';
import 'core/preview/preview_data.dart';
import 'features/feedback/present/review_prompt_host.dart';
import 'features/onboarding/present/tour_overlay.dart';
import 'features/settings/data/reading_settings.dart';
import 'features/settings/present/theme_mode_provider.dart';

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

/// Re-arms the daily reading reminder with the OS on every launch.
///
/// The alarm does not survive a reinstall, and Android can drop it on a
/// force-stop; `scheduleDaily` cancels before it sets, so calling it again
/// with the stored time is a no-op when the reminder is already in place and
/// a fix when it is not. Nothing runs when no reminder is stored.
///
/// It also re-arms the rolling batch of reminders, which is now a fortnight of
/// one-shot notifications rather than one repeating alarm. Someone who does not
/// open the app for two weeks therefore stops being reminded - which is the
/// behaviour we want anyway: a nudge nobody has acted on in a fortnight should
/// go quiet rather than repeat forever.
Future<void> _initReminders() async {
  if (kIsWeb) return;
  // Cache-only: a cold start must not wait on a network call. The batch is
  // refreshed from the server once the app is running and signed in.
  final service = ReminderService(
    FlutterLocalNotificationsPlugin(),
    const ReminderCopySource.cacheOnly(),
  );
  await service.initialise();

  final prefs = await SharedPreferences.getInstance();
  final minutes = prefs.getInt(kDailyReminderMinutesKey);
  if (minutes != null) {
    await service.scheduleDaily(hour: minutes ~/ 60, minute: minutes % 60);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Paper-coloured system chrome, matching --paper on www.bijbel-studie.com.
  SystemChrome.setSystemUIOverlayStyle(AppTheme.overlayStyle);

  if (PreviewConfig.enabled) {
    // Point image URLs at the live site so artwork resolves without a local
    // backend, then run with canned data and no auth.
    AppConfig.setCustomApiBaseUrl('https://www.bijbel-studie.com/api/v1');
    debugPrint('[Preview] Design-preview mode active - using canned data.');
    runApp(PreviewData.scope(const BijbelStudieApp()));
    return;
  }

  try {
    await _initRevenueCat();
  } catch (e, st) {
    // A RevenueCat outage must never stop the app from starting: the reader
    // works without an entitlement check.
    assert(() {
      debugPrint('[RevenueCat][Main] init failed: $e\n$st');
      return true;
    }());
  }

  try {
    await _initReminders();
  } catch (e, st) {
    // A notifications hiccup must never stop the app from starting either;
    // the settings tile re-checks the real state itself and will not claim
    // the reminder is on if this failed.
    assert(() {
      debugPrint('[Reminders][Main] init failed: $e\n$st');
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
      // The guided tour paints a spotlight over the running app, so it has to
      // sit above the router's Navigator - including the bottom tab bar, which
      // two of its steps point at. It builds nothing while the tour is off.
      // The rating prompt sits outside the tour host on purpose: it renders
      // nothing until its gate opens, and it refuses to open while the tour is
      // running, so the two can never fight over the same window.
      builder: (context, child) => ReviewPromptHost(
        enabled: !PreviewConfig.enabled,
        child: TourHost(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
