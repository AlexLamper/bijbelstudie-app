import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

// ─── RevenueCat identifiers ──────────────────────────────────────────────────
// Product IDs must match App Store Connect / Play exactly.
const kRcMonthlyProductId = 'bijbelstudie_pro_monthly';
const kRcYearlyProductId = 'bijbelstudie_pro_yearly';
// RevenueCat package IDs are the standard ones for a subscription group.
const kRcMonthlyPackageId = '\$rc_monthly';
const kRcYearlyPackageId = '\$rc_annual';

// RevenueCat entitlement identifier (configured in the RC dashboard).
const kRcProEntitlement = 'pro';

// SDK is configured once in main.dart (see RevenueCatConfig).

final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  return PurchaseService();
});

class PurchaseService {
  void _log(String message) {
    assert(() {
      debugPrint('[RevenueCat][PurchaseService] $message');
      return true;
    }());
  }

  /// Returns the current offering's packages.
  ///
  /// Reads the **current offering** rather than hardcoded product ids, so
  /// pricing and packaging can change in the RevenueCat dashboard without an
  /// app release. The hardcoded ids exist only as a fallback for when the
  /// offering is momentarily unavailable.
  Future<List<Package>> getPackages() async {
    if (kIsWeb) return [];
    _log('Fetching offerings...');
    final offerings = await Purchases.getOfferings();
    final current = offerings.current;
    if (current == null) {
      _log('No current offering found.');
      return [];
    }

    final packages = <Package>[...current.availablePackages];
    _log('Current offering="${current.identifier}" with ${packages.length} package(s).');
    for (final pkg in packages) {
      _log(
        'Package="${pkg.identifier}" product="${pkg.storeProduct.identifier}" '
        'price="${pkg.storeProduct.priceString}"',
      );
    }

    // Stable order in the UI: yearly first, then monthly. Annual is the plan
    // worth selling - it collects a year of cash up front and removes eleven
    // future opportunities to churn - so it leads rather than trails.
    packages.sort((a, b) {
      int rank(Package pkg) {
        if (pkg.storeProduct.identifier == kRcYearlyProductId) return 0;
        if (pkg.packageType == PackageType.annual) return 1;
        if (pkg.storeProduct.identifier == kRcMonthlyProductId) return 2;
        if (pkg.packageType == PackageType.monthly) return 3;
        return 99;
      }

      return rank(a).compareTo(rank(b));
    });

    return packages;
  }

  /// Store products looked up by id, keyed by id.
  ///
  /// The offering is the right source of truth for packaging, but it is also
  /// the part most likely to be misconfigured: an offering that is not marked
  /// "current", or one whose packages were never attached, yields zero
  /// packages and therefore no prices at all. Asking the store for the two
  /// product ids directly is a second, independent route to the same numbers,
  /// and it works as long as the products themselves exist and are approved.
  Future<Map<String, StoreProduct>> getProductsById(List<String> ids) async {
    if (kIsWeb) return const {};
    _log('Fetching products directly: ${ids.join(', ')}');
    final products = await Purchases.getProducts(ids);
    _log('Store returned ${products.length} product(s) for ${ids.length} id(s).');
    return {for (final product in products) product.identifier: product};
  }

  Package? findMonthlyPackage(List<Package> packages) {
    return _findPackage(
      packages,
      packageId: kRcMonthlyPackageId,
      productId: kRcMonthlyProductId,
      packageType: PackageType.monthly,
      annual: false,
    );
  }

  Package? findYearlyPackage(List<Package> packages) {
    return _findPackage(
      packages,
      packageId: kRcYearlyPackageId,
      productId: kRcYearlyProductId,
      packageType: PackageType.annual,
      annual: true,
    );
  }

  /// Find the annual or monthly package, in order of how sure the match is.
  ///
  /// Matching only on the two hardcoded ids was too strict: an offering built
  /// in the RevenueCat dashboard with custom package identifiers - or with the
  /// product renamed - returns perfectly good packages that matched neither,
  /// so the paywall rendered "-" while holding the prices it needed. The last
  /// two rules read the package's own type and billing period instead, which
  /// are set by the store rather than by our naming.
  Package? _findPackage(
    List<Package> packages, {
    required String packageId,
    required String productId,
    required PackageType packageType,
    required bool annual,
  }) {
    Package? firstWhere(bool Function(Package) test) {
      for (final pkg in packages) {
        if (test(pkg)) return pkg;
      }
      return null;
    }

    return firstWhere((pkg) => pkg.identifier == packageId) ??
        firstWhere((pkg) => pkg.storeProduct.identifier == productId) ??
        firstWhere((pkg) => pkg.packageType == packageType) ??
        firstWhere((pkg) => _isPeriod(pkg.storeProduct.subscriptionPeriod, annual: annual));
  }

  /// Whether an ISO-8601 billing period is a year (`P1Y`, `P12M`) or a month
  /// (`P1M`). Anything else - weekly, six-monthly, lifetime - matches neither,
  /// so an unrelated package is never mistaken for one of these two.
  static bool _isPeriod(String? period, {required bool annual}) {
    if (period == null) return false;
    final normalised = period.toUpperCase();
    return annual
        ? normalised == 'P1Y' || normalised == 'P12M'
        : normalised == 'P1M';
  }

  /// Purchase a RevenueCat package from the current offering.
  Future<CustomerInfo> purchasePackage(Package package) async {
    _log(
      'Purchasing package="${package.identifier}" product="${package.storeProduct.identifier}"',
    );
    return Purchases.purchasePackage(package);
  }

  /// Fallback for when offering packages are temporarily unavailable.
  Future<CustomerInfo> purchaseByProductId(String productId) async {
    _log('Fallback purchase requested for product="$productId"');
    final products = await Purchases.getProducts([productId]);
    if (products.isEmpty) {
      throw StateError('Store product niet gevonden voor id: $productId');
    }
    final product = products.first;
    _log('Fallback product found id="${product.identifier}" price="${product.priceString}"');
    return Purchases.purchaseStoreProduct(product);
  }

  /// Restore previous purchases. Required by App Store review — the paywall
  /// must expose this as a visible button.
  Future<CustomerInfo> restorePurchases() async {
    _log('Restoring purchases...');
    return Purchases.restorePurchases();
  }

  /// Whether the local CustomerInfo carries an active Pro entitlement.
  ///
  /// This is the fast signal, not the authority: `/api/v1/me.isPro` is. On a
  /// mismatch the app calls /api/v1/sync-premium and re-reads the server.
  Future<bool> hasProAccess() async {
    if (kIsWeb) return false;
    final info = await Purchases.getCustomerInfo();
    final hasPro = info.entitlements.active.containsKey(kRcProEntitlement);
    _log('hasProAccess=$hasPro');
    return hasPro;
  }

  Future<CustomerInfo> getCustomerInfo() async {
    final info = await Purchases.getCustomerInfo();
    final activeIds = info.entitlements.active.keys.join(', ');
    _log('CustomerInfo active entitlements: ${activeIds.isEmpty ? '(none)' : activeIds}');
    return info;
  }
}
