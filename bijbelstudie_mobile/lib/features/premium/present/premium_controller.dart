import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../../core/analytics/analytics.dart';
import '../../../core/config/revenuecat_config.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/present/profile_provider.dart';
import '../data/purchase_service.dart';

// ─── State ────────────────────────────────────────────────────────────────────

enum PurchaseStatus { idle, loading, success, error }

/// Whether the paywall has real store prices to show.
///
/// Split out from [PurchaseStatus], which is about a purchase in flight. The
/// prices load once when the paywall is first reached and can fail on their
/// own - no API key in the build, products not approved in App Store Connect,
/// no offering marked current, a simulator with no StoreKit - and every one of
/// those used to render as a bare `-` with nothing else said.
enum PriceStatus { loading, ready, unavailable }

class PremiumState {
  const PremiumState({
    this.status = PurchaseStatus.idle,
    this.packages = const [],
    this.customerInfo,
    this.errorMessage,
    this.priceStatus = PriceStatus.loading,
    this.priceError,
    this.monthlyProduct,
    this.yearlyProduct,
  });

  final PurchaseStatus status;
  final List<Package> packages;
  final CustomerInfo? customerInfo;
  final String? errorMessage;

  final PriceStatus priceStatus;

  /// Why the prices are missing, in Dutch and safe to show. Null unless
  /// [priceStatus] is [PriceStatus.unavailable].
  final String? priceError;

  /// The two products the paywall renders, resolved from the current offering
  /// or, failing that, looked up by product id.
  final StoreProduct? monthlyProduct;
  final StoreProduct? yearlyProduct;

  bool get isPro =>
      customerInfo?.entitlements.active.containsKey(kRcProEntitlement) ??
      false;

  PremiumState copyWith({
    PurchaseStatus? status,
    List<Package>? packages,
    CustomerInfo? customerInfo,
    String? errorMessage,
  }) {
    return PremiumState(
      status: status ?? this.status,
      packages: packages ?? this.packages,
      customerInfo: customerInfo ?? this.customerInfo,
      errorMessage: errorMessage ?? this.errorMessage,
      priceStatus: priceStatus,
      priceError: priceError,
      monthlyProduct: monthlyProduct,
      yearlyProduct: yearlyProduct,
    );
  }

  /// Prices replace themselves wholesale rather than merging: a reload that
  /// found nothing must clear what a previous one found, or the paywall keeps
  /// quoting a price the store no longer offers.
  PremiumState withPrices({
    required PriceStatus priceStatus,
    String? priceError,
    List<Package> packages = const [],
    StoreProduct? monthlyProduct,
    StoreProduct? yearlyProduct,
    CustomerInfo? customerInfo,
  }) {
    return PremiumState(
      status: status,
      errorMessage: errorMessage,
      packages: packages,
      customerInfo: customerInfo ?? this.customerInfo,
      priceStatus: priceStatus,
      priceError: priceError,
      monthlyProduct: monthlyProduct,
      yearlyProduct: yearlyProduct,
    );
  }
}

// ─── Provider (Riverpod 3.x Notifier API) ────────────────────────────────────

final premiumControllerProvider =
    NotifierProvider<PremiumController, PremiumState>(PremiumController.new);

// ─── Controller ───────────────────────────────────────────────────────────────

class PremiumController extends Notifier<PremiumState> {
  void _log(String message) {
    assert(() {
      // ignore: avoid_print
      print('[RevenueCat][PremiumController] $message');
      return true;
    }());
  }

  @override
  PremiumState build() {
    unawaited(loadPrices());
    return const PremiumState();
  }

  PurchaseService get _svc => ref.read(purchaseServiceProvider);

  /// Fetches the prices the paywall renders.
  ///
  /// Public and re-runnable: this provider is not autoDispose, so `build` runs
  /// once for the whole app run. A single failed attempt - the app opened on a
  /// dead network, the store not yet reachable at launch - used to mean the
  /// paywall showed `-` until the app was killed and relaunched, with no way to
  /// try again. The paywall calls this on entry and from its retry button.
  Future<void> loadPrices() async {
    if (kIsWeb) {
      state = state.withPrices(
        priceStatus: PriceStatus.unavailable,
        priceError: 'Aankopen zijn niet beschikbaar in de webversie.',
      );
      return;
    }

    // The SDK is configured in main.dart and only when a key was supplied. No
    // key means no store connection at all, and every call below would throw
    // an opaque platform error - so say what is actually wrong instead.
    if (RevenueCatConfig.sdkPublicApiKey().isEmpty) {
      _log('No RevenueCat SDK key in this build (${RevenueCatConfig.sdkKeySource()}).');
      state = state.withPrices(
        priceStatus: PriceStatus.unavailable,
        priceError:
            'Deze build bevat geen winkelconfiguratie, dus prijzen kunnen niet '
            'worden opgehaald.',
      );
      return;
    }

    state = state.withPrices(
      priceStatus: PriceStatus.loading,
      packages: state.packages,
      monthlyProduct: state.monthlyProduct,
      yearlyProduct: state.yearlyProduct,
    );

    try {
      _log('Loading packages and customer info...');
      final packages = await _svc.getPackages();
      var monthly = _svc.findMonthlyPackage(packages)?.storeProduct;
      var yearly = _svc.findYearlyPackage(packages)?.storeProduct;

      // The offering is the usual source, but it is also the usual thing to be
      // misconfigured. Falling back to a direct product lookup means a missing
      // or empty "current" offering costs the packaging, not the prices.
      if (monthly == null || yearly == null) {
        _log('Offering incomplete (monthly=${monthly != null}, yearly=${yearly != null}); '
            'falling back to a direct product lookup.');
        final direct = await _svc.getProductsById(const [
          kRcMonthlyProductId,
          kRcYearlyProductId,
        ]);
        monthly ??= direct[kRcMonthlyProductId];
        yearly ??= direct[kRcYearlyProductId];
      }

      final info = await _svc.getCustomerInfo();
      final found = monthly != null || yearly != null;
      state = state.withPrices(
        priceStatus: found ? PriceStatus.ready : PriceStatus.unavailable,
        priceError: found
            ? null
            : 'De App Store gaf geen abonnementen terug. Controleer of de '
                  'producten actief en goedgekeurd zijn.',
        packages: packages,
        monthlyProduct: monthly,
        yearlyProduct: yearly,
        customerInfo: info,
      );
      _log(
        'Prices: monthly=${monthly?.priceString ?? '(none)'} '
        'yearly=${yearly?.priceString ?? '(none)'} '
        'from ${packages.length} package(s); '
        'isPro=${info.entitlements.active.containsKey(kRcProEntitlement)}',
      );
    } catch (e) {
      _log('Failed to load prices: $e');
      state = state.withPrices(
        priceStatus: PriceStatus.unavailable,
        priceError: 'Prijzen konden niet worden geladen. Controleer je verbinding.',
      );
    }
  }

  Future<void> purchaseMonthly() => _purchase(kRcMonthlyProductId);
  Future<void> purchaseYearly() => _purchase(kRcYearlyProductId);

  /// Reported on every purchase event so the App Store funnel can be read
  /// separately from the web one.
  String _intervalOf(String productId) =>
      productId == kRcYearlyProductId ? 'annual' : 'monthly';

  Future<void> _purchase(String productId) async {
    _log('Purchase requested for product="$productId"');
    final interval = _intervalOf(productId);
    final analytics = ref.read(analyticsProvider);
    analytics.track(AnalyticsEvents.checkoutStarted, {'interval': interval});
    final package = productId == kRcMonthlyProductId
        ? _svc.findMonthlyPackage(state.packages)
        : _svc.findYearlyPackage(state.packages);
    state = state.copyWith(status: PurchaseStatus.loading);
    try {
      final info = package != null
          ? await _svc.purchasePackage(package)
          : await _svc.purchaseByProductId(productId);
      state = state.copyWith(
        status: PurchaseStatus.success,
        customerInfo: info,
      );
      _log(
        'Purchase success. Active entitlements: ${info.entitlements.active.keys.join(', ')}',
      );
      analytics.track(AnalyticsEvents.checkoutCompleted, {'interval': interval});
      await _syncServerPremium();
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        state = state.copyWith(status: PurchaseStatus.idle);
        _log('Purchase cancelled by user.');
        analytics.track(AnalyticsEvents.purchaseCancelled, {'interval': interval});
        return;
      }
      state = state.copyWith(
        status: PurchaseStatus.error,
        errorMessage: _errorMessage(code),
      );
      analytics.track(AnalyticsEvents.purchaseFailed, {'interval': interval});
      _log('Purchase failed: code=$code message="${e.message}"');
    } on StateError catch (e) {
      final availableProducts = state.packages
          .map((p) => p.storeProduct.identifier)
          .toList(growable: false);
      final availablePackages = state.packages
          .map((p) => p.identifier)
          .toList(growable: false);
      state = state.copyWith(
        status: PurchaseStatus.error,
        errorMessage:
            'Product niet gevonden in App Store/RevenueCat. Controleer of je IAP-producten gekoppeld en beschikbaar zijn.',
      );
      _log(
        'Product lookup failed. Requested="$productId", error="$e". '
        'Available package IDs=$availablePackages '
        'Available product IDs=$availableProducts',
      );
    } catch (e) {
      state = state.copyWith(
        status: PurchaseStatus.error,
        errorMessage: 'Aankoop mislukt: $e',
      );
      _log('Purchase failed with error: $e');
    }
  }

  Future<void> restorePurchases() async {
    _log('Restore purchases requested.');
    state = state.copyWith(status: PurchaseStatus.loading);
    try {
      final info = await _svc.restorePurchases();
      state = state.copyWith(
        status: PurchaseStatus.success,
        customerInfo: info,
      );
      _log(
        'Restore success. Active entitlements: ${info.entitlements.active.keys.join(', ')}',
      );
      ref.read(analyticsProvider).track(AnalyticsEvents.purchasesRestored);
      await _syncServerPremium();
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        state = state.copyWith(status: PurchaseStatus.idle);
        _log('Restore cancelled by user.');
        return;
      }
      state = state.copyWith(
        status: PurchaseStatus.error,
        errorMessage: _errorMessage(code),
      );
      _log('Restore failed: code=$code message="${e.message}"');
    } catch (e) {
      state = state.copyWith(
        status: PurchaseStatus.error,
        errorMessage: 'Herstel mislukt. Probeer het opnieuw.',
      );
      _log('Restore failed: $e');
    }
  }

  void clearStatus() => state = state.copyWith(status: PurchaseStatus.idle);

  /// Premium content is gated on the server profile, and RevenueCat only fires
  /// a webhook for a NEW transaction - never for an already-owned purchase or a
  /// restore. So we actively ask the server to reconcile against RevenueCat,
  /// then refresh the profile. We retry briefly to ride out store propagation.
  Future<void> _syncServerPremium() async {
    final repo = ref.read(profileRepositoryProvider);
    for (var attempt = 0; attempt < 5; attempt++) {
      final synced = await repo.syncPremium();
      ref.invalidate(profileProvider);
      if (synced == true) return;
      if (synced == null) {
        // Endpoint unreachable/undeployed: fall back to reading the profile in
        // case a webhook already updated it.
        try {
          final profile = await ref.read(profileProvider.future);
          if (profile.isPro) return;
        } catch (_) {}
      }
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  String _errorMessage(PurchasesErrorCode code) {
    switch (code) {
      case PurchasesErrorCode.networkError:
      case PurchasesErrorCode.offlineConnectionError:
        return 'Geen internetverbinding. Controleer je verbinding en probeer opnieuw.';
      case PurchasesErrorCode.productAlreadyPurchasedError:
        return 'Je hebt dit product al aangeschaft. Gebruik "Aankopen herstellen".';
      case PurchasesErrorCode.purchaseNotAllowedError:
        return 'Aankopen zijn niet toegestaan op dit apparaat. Controleer je App Store-instellingen.';
      case PurchasesErrorCode.paymentPendingError:
        return 'Je betaling wordt nog verwerkt. Premium wordt geactiveerd zodra dit voltooid is.';
      case PurchasesErrorCode.productNotAvailableForPurchaseError:
        return 'Dit product is momenteel niet beschikbaar in de store. Probeer het later opnieuw.';
      case PurchasesErrorCode.storeProblemError:
        return 'Er is een probleem met de store. Probeer het later opnieuw.';
      case PurchasesErrorCode.insufficientPermissionsError:
        return 'Geen toestemming om aankopen te doen.';
      default:
        return 'Aankoop mislukt. Probeer het opnieuw.';
    }
  }
}
