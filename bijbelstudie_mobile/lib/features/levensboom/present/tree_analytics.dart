import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';

/// Sends one of the tree's funnel events (`AnalyticsEvents.tree*`).
///
/// Telemetry never gets to break the tree: a scope without an analytics
/// client (a widget test, a preview) or a ref that is already gone simply
/// sends nothing.
void trackTree(WidgetRef ref, String name, [Map<String, String>? props]) {
  try {
    ref.read(analyticsProvider).track(name, props);
  } catch (_) {
    /* measurement only */
  }
}
