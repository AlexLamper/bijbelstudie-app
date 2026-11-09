/// What the store SDK (RevenueCat) last said about this reader: an active Pro
/// subscription or store trial, or not.
///
/// The server only learns about a store purchase through the RevenueCat sync,
/// and the app's first request of a launch can get there before it does. The
/// account then looks free, and an older account was handed the one-time
/// reverse trial - "Je hebt 3 dagen Pro gekregen" - while it was already on an
/// App Store trial. [ApiClient] sends [header] on every call while [active],
/// and the server (`lib/apiAuth.ts` `claimsStorePro`) then never starts that
/// trial, or takes back one it started. It can only withhold a trial, never
/// grant anything, so a client-side flag is enough.
///
/// Kept outside Riverpod on purpose: the API client is built before any
/// provider, and this is one bool written by the premium controller.
class StoreProSignal {
  StoreProSignal._();

  static const header = 'X-Bs-Store-Pro';

  static bool active = false;
}
