import 'package:purchases_flutter/purchases_flutter.dart';

/// Derives the per-week framing and the annual saving from the **real** store
/// prices.
///
/// Nothing here is hardcoded, and it deliberately does not reuse the web app's
/// `lib/pricing.ts` numbers. App Store prices are set per storefront by Apple's
/// price tiers, they differ from the web tariff, and the user may be in any
/// currency. Quoting a euro figure that the App Store is not about to charge
/// would be both wrong and a review risk, so every number below is computed
/// from `StoreProduct.price` and rendered in that product's own currency.
class PriceFraming {
  const PriceFraming._();

  /// Number of weeks used to annualise. Matches the web calculation so the two
  /// funnels stay comparable.
  static const int _weeksPerYear = 52;
  static const int _monthsPerYear = 12;

  /// Formats [amount] using the currency symbol and layout of [template]'s own
  /// localized price string.
  ///
  /// This avoids adding `intl` and, more importantly, avoids guessing: whatever
  /// Apple decided the price looks like in this storefront - symbol before or
  /// after, comma or point decimals, non-breaking space - is preserved, and
  /// only the digits are swapped out.
  static String formatLike(StoreProduct template, double amount) {
    final priceString = template.priceString;

    // Locate the numeric run inside the localized string.
    final match = RegExp(r'[\d]+(?:[.,][\d]+)*(?:[.,][\d]{1,2})?').firstMatch(priceString);
    if (match == null) {
      // No recognisable number: fall back to the raw amount rather than
      // rendering something misleading.
      return amount.toStringAsFixed(2);
    }

    final numeric = match.group(0)!;
    // Infer the decimal separator from the template's own last separator.
    final usesComma = numeric.contains(',') &&
        (!numeric.contains('.') || numeric.lastIndexOf(',') > numeric.lastIndexOf('.'));

    var rendered = amount.toStringAsFixed(2);
    if (usesComma) rendered = rendered.replaceAll('.', ',');

    return priceString.replaceRange(match.start, match.end, rendered);
  }

  /// What this product costs per week, formatted in its own currency.
  ///
  /// [isAnnual] tells us how to annualise: a monthly product is multiplied by
  /// twelve first, so both plans are compared over the same span.
  static String perWeek(StoreProduct product, {required bool isAnnual}) {
    final yearly = isAnnual ? product.price : product.price * _monthsPerYear;
    return formatLike(product, yearly / _weeksPerYear);
  }

  /// Effective monthly cost of an annual product, formatted in its currency.
  static String effectivePerMonth(StoreProduct annual) {
    return formatLike(annual, annual.price / _monthsPerYear);
  }

  /// What a year of the monthly plan costs - the honest anchor for the annual
  /// plan, because it is a tariff we genuinely charge rather than a former price.
  static String monthlyEquivalentPerYear(StoreProduct monthly) {
    return formatLike(monthly, monthly.price * _monthsPerYear);
  }

  /// Absolute saving of annual versus twelve months of monthly.
  ///
  /// Returns null when the two products are priced in different currencies -
  /// subtracting across currencies would produce a meaningless number, and it
  /// is better to show nothing than a wrong saving.
  static String? annualSaving(StoreProduct monthly, StoreProduct annual) {
    if (monthly.currencyCode != annual.currencyCode) return null;
    final saving = (monthly.price * _monthsPerYear) - annual.price;
    if (saving <= 0) return null;
    return formatLike(annual, saving);
  }

  /// How much cheaper annual is than monthly, as a whole percent.
  ///
  /// Null when the currencies differ or annual is not actually cheaper - the
  /// badge must never appear unless it is true of the prices being shown.
  static int? annualDiscountPercent(StoreProduct monthly, StoreProduct annual) {
    if (monthly.currencyCode != annual.currencyCode) return null;
    final yearlyAtMonthlyRate = monthly.price * _monthsPerYear;
    if (yearlyAtMonthlyRate <= 0) return null;
    final saving = yearlyAtMonthlyRate - annual.price;
    if (saving <= 0) return null;
    return ((saving / yearlyAtMonthlyRate) * 100).round();
  }

  /// Whole months of the monthly plan covered by the annual saving.
  ///
  /// Floored, never rounded: a "3 maanden gratis" badge on a saving worth 2,99
  /// months is a claim the prices do not support.
  static int? freeMonthsOnAnnual(StoreProduct monthly, StoreProduct annual) {
    if (monthly.currencyCode != annual.currencyCode) return null;
    if (monthly.price <= 0) return null;
    final saving = (monthly.price * _monthsPerYear) - annual.price;
    if (saving <= 0) return null;
    return (saving / monthly.price).floor();
  }
}
