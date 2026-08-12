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

    // Stable order in the UI: monthly first, then yearly.
    packages.sort((a, b) {
      int rank(String id) => id == kRcMonthlyProductId ? 0 : (id == kRcYearlyProductId ? 1 : 99);
      return rank(a.storeProduct.identifier).compareTo(rank(b.storeProduct.identifier));
    });

    return packages;
  }

  Package? findMonthlyPackage(List<Package> packages) {
    return _findPackage(
      packages,
      packageId: kRcMonthlyPackageId,
      productId: kRcMonthlyProductId,
    );
  }

  Package? findYearlyPackage(List<Package> packages) {
    return _findPackage(
      packages,
      packageId: kRcYearlyPackageId,
      productId: kRcYearlyProductId,
    );
  }

  Package? _findPackage(
    List<Package> packages, {
    required String packageId,
    required String productId,
  }) {
    for (final pkg in packages) {
      if (pkg.identifier == packageId || pkg.storeProduct.identifier == productId) {
        return pkg;
      }
    }
    return null;
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
