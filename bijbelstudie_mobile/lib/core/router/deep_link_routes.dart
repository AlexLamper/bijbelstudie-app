/// Incoming https://bijbelstudie.io links (Android App Links).
///
/// A cold start from a web link hands the router the deep path as its initial
/// location, which would skip the splash and land a signed-out reader on a
/// screen that needs a session. So the router holds the path here and goes to
/// the splash instead; the splash takes it once the auth check is done. This
/// mirrors what `NotificationService` does with a cold-start notification tap.
library;

/// The website paths the app is registered for, as prefixes. Keep this in step
/// with the `<data android:pathPrefix>` entries in `AndroidManifest.xml`: a
/// path Android hands over but this list rejects would open the app and then
/// sit on the dashboard, which reads as a broken link.
const _handledPrefixes = <String>[
  '/studie',
  '/studies',
  '/bronnen',
  '/bijbel',
];

class DeepLinkRoutes {
  DeepLinkRoutes._();

  static String? _pending;

  /// False until the splash has resolved where the reader goes. Until then an
  /// incoming link waits; after that the router navigates to it directly.
  static bool _splashDone = false;

  static bool get splashDone => _splashDone;

  /// Translates a website path to the app route that shows the same thing, or
  /// returns null when the app has no screen for it. The website and the app
  /// share most of their paths, so most of this is a pass-through; `/bijbel`
  /// is the one shape that differs.
  static String? appRouteFor(Uri uri) {
    final path = uri.path;
    if (!_handledPrefixes.any((p) => path == p || path.startsWith('$p/'))) {
      return null;
    }
    // The site reads a chapter at /bijbel/<boek>/<hoofdstuk>; the app shows the
    // same chapter with its study panel at /studie/hoofdstuk/<boek>/<nummer>.
    final segments = uri.pathSegments;
    if (segments.length == 3 && segments.first == 'bijbel') {
      return '/studie/hoofdstuk/${segments[1]}/${segments[2]}';
    }
    if (segments.length == 1 && segments.first == 'bijbel') return '/read';
    return uri.hasQuery ? '$path?${uri.query}' : path;
  }

  /// Holds [route] until the splash is done with its auth check.
  static void hold(String route) => _pending = route;

  /// The link the reader followed to open the app, if any. Called by the
  /// splash; from then on links navigate straight through.
  static String? take() {
    _splashDone = true;
    final pending = _pending;
    _pending = null;
    return pending;
  }
}
