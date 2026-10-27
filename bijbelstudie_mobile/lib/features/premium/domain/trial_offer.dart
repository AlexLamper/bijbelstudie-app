import 'package:purchases_flutter/purchases_flutter.dart';

/// A free trial the store is about to give on a product, read from the
/// product itself rather than assumed.
///
/// The trial is configured in App Store Connect (an introductory offer) and
/// in Play Console (a free-trial offer on the base plan). Nothing in the app
/// promises "7 dagen gratis" unless the store actually returned such an offer
/// for this reader: an advertised trial the store then does not apply is the
/// "misleading trial" case both reviews reject, and a refund besides.
class TrialOffer {
  const TrialOffer({required this.days});

  /// Length of the free period in days.
  final int days;

  /// "7 dagen", "1 week" reads oddly next to a date, so always days.
  String get label => days == 1 ? '1 dag' : '$days dagen';

  /// The day the reminder lands: two days before the first charge, but never
  /// before day 1. Shown in the timeline and used for the local notification.
  int get reminderDay => days <= 2 ? 1 : days - 2;

  /// Reads the free period off a product, or null when it has none.
  ///
  /// iOS reports it as an `introductoryPrice` with price 0 (Apple only returns
  /// an intro the account is eligible for after [isEligible] is checked
  /// separately). Android reports subscription options; Play only returns
  /// offers this account may still redeem, and `defaultOption` is the one the
  /// purchase will use, so its `freePhase` is the trial the reader will get.
  static TrialOffer? fromProduct(StoreProduct product) {
    final intro = product.introductoryPrice;
    if (intro != null && intro.price == 0) {
      final days = _days(intro.periodUnit, intro.periodNumberOfUnits) * (intro.cycles < 1 ? 1 : intro.cycles);
      if (days > 0) return TrialOffer(days: days);
    }
    final free = product.defaultOption?.freePhase;
    final period = free?.billingPeriod;
    if (free != null && period != null) {
      final cycles = free.billingCycleCount ?? 1;
      final days = _days(period.unit, period.value) * (cycles < 1 ? 1 : cycles);
      if (days > 0) return TrialOffer(days: days);
    }
    return null;
  }

  static int _days(PeriodUnit unit, int value) => switch (unit) {
    PeriodUnit.day => value,
    PeriodUnit.week => value * 7,
    PeriodUnit.month => value * 30,
    PeriodUnit.year => value * 365,
    _ => 0,
  };

  @override
  bool operator ==(Object other) => other is TrialOffer && other.days == days;

  @override
  int get hashCode => days.hashCode;
}
