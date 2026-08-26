import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/notifications/reminder_service.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/config/app_config.dart';
import 'core/config/preview_config.dart';
import 'core/config/revenuecat_config.dart';
import 'core/preview/preview_data.dart';
import 'features/settings/data/reading_settings.dart';

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
Future<void> _initReminders() async {
  if (kIsWeb) return;
  final service = ReminderService(FlutterLocalNotificationsPlugin());
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
    final routerConfig = ref.watch(routerProvider);

    // Light only, deliberately.
    //
    // App review 1.0 (7) was rejected under guideline 4 on an iPad in dark
    // mode: "the font colour used makes it hard to read with the background
    // colour". The cause is structural. `AppTheme` publishes its type ramp as
    // `static const TextStyle`s and a const cannot depend on brightness, so
    // thirteen of the fourteen bake a light colour — `displaySmall` is `ink`
    // (#111827) whatever the theme says. Against the dark scaffold that is
    // near-black on near-black; the paywall headline was invisible.
    //
    // There is no colour that fixes this in place: `inkMuted` clears AA on
    // white and fails it on #212121, so the ramp has to become
    // context-resolved before dark mode can come back. That is a refactor of
    // every call site, and shipping it half-done risks a second guideline 4
    // rejection, which is worse than not offering dark mode at all — Apple
    // does not require it.
    //
    // `darkTheme` is pinned to the light theme as well as `themeMode`, so the
    // app stays readable even if something upstream forces dark. The dark
    // palette in AppTheme is kept, and test/dark_mode_contrast_test.dart holds
    // the conditions that must be met before this is reverted.
    return MaterialApp.router(
      title: 'BijbelStudie',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      routerConfig: routerConfig,
    );
  }
}
