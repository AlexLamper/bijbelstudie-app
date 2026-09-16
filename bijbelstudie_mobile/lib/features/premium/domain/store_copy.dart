import 'package:flutter/foundation.dart';

/// Store names in customer-facing copy.
///
/// Play review rejects an Android paywall that sends people to "Apple
/// ID-instellingen" or "je App Store-account" (misleading payment disclosure),
/// and App Review does the same the other way round. Every sentence that names
/// a store reads it from here.
class StoreCopy {
  StoreCopy._();

  static bool get isPlay => defaultTargetPlatform == TargetPlatform.android;

  /// "App Store" / "Google Play", for compounds like "je App Store-account".
  static String get storeName => isPlay ? 'Google Play' : 'App Store';

  /// "de App Store" / "Google Play", mid-sentence ("uit de App Store").
  static String get storeInSentence => isPlay ? 'Google Play' : 'de App Store';

  /// Where a subscriber manages or cancels, completing "in je ...".
  static String get manageLocation => isPlay
      ? 'Google Play-account (Play Store > Betalingen en abonnementen)'
      : 'Apple ID-instellingen';

  /// The auto-renewal disclosure under the paywall's buttons. Apple requires
  /// the 24-hour rule; Play subscriptions can be cancelled up to renewal.
  static String get renewalNotice => isPlay
      ? 'Het abonnement wordt automatisch verlengd tot je het opzegt. Opzeggen '
          'kan altijd vóór de verlengdatum, in de Play Store onder Betalingen en '
          'abonnementen.'
      : 'Het abonnement wordt automatisch verlengd tenzij je het minstens 24 uur '
          'voor het einde van de periode opzegt. Beheren en opzeggen doe je in je '
          'Apple ID-instellingen.';
}
