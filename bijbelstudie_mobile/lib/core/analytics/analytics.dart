import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../../features/auth/data/auth_local_storage.dart';
import '../../features/auth/present/auth_controller.dart' show apiClientProvider, authStorageProvider;

/// Funnel event names. These must exist in the server allowlist
/// (`lib/analyticsSchema.ts` in the web repo) or the event is silently dropped.
class AnalyticsEvents {
  AnalyticsEvents._();

  static const pricingViewed = 'pricing_viewed';
  static const planSelected = 'plan_selected';
  static const checkoutStarted = 'checkout_started';
  static const checkoutCompleted = 'checkout_completed';
  static const purchaseCancelled = 'purchase_cancelled';
  static const purchaseFailed = 'purchase_failed';
  static const purchasesRestored = 'purchases_restored';
  static const paywallHit = 'paywall_hit';
  static const paywallCtaClicked = 'paywall_cta_clicked';
}

/// Fire-and-forget funnel tracking for the mobile app.
///
/// Everything here fails silently by design: telemetry must never interrupt a
/// purchase, and a failed analytics call during checkout would be far more
/// costly than the missing data point.
///
/// Events are queued and flushed in small batches to `/api/v1/analytics`, which
/// authenticates with the same bearer token as every other call. Nothing is
/// sent while logged out - there is no anonymous write path from the app.
class Analytics {
  Analytics(this._client, this._storage);

  final ApiClient _client;
  final AuthLocalStorage _storage;

  final List<Map<String, dynamic>> _queue = [];
  bool _flushing = false;

  static const _maxBatch = 20;

  /// Reported on every event so the iOS funnel is never conflated with web.
  static String get platform {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isIOS) return 'ios';
      if (Platform.isAndroid) return 'android';
    } catch (_) {
      // Platform is unavailable on some targets; fall through.
    }
    return 'web';
  }

  void track(String name, [Map<String, String>? props]) {
    final merged = <String, String>{'platform': platform, ...?props};
    _queue.add({'name': name, 'props': merged});
    unawaited(flush());
  }

  /// Sends whatever is queued. Safe to call at any time.
  ///
  /// There is deliberately no debounce timer here. Event volume is a handful
  /// per session, so batching would save nothing measurable - and a pending
  /// `Future.delayed` is a timer that outlives the widget that created it,
  /// which leaks into widget tests and, worse, keeps work scheduled after the
  /// screen is gone. Because `flush` drains the whole queue, several `track`
  /// calls in the same turn still coalesce into one request.
  Future<void> flush() async {
    if (_queue.isEmpty || _flushing) return;
    _flushing = true;

    try {
      // Logged-out users are not tracked: the endpoint requires a user, and
      // queueing indefinitely would leak events across accounts on this device.
      final token = await _storage.getToken();
      if (token == null || token.isEmpty) {
        _queue.clear();
        return;
      }

      final batch = List<Map<String, dynamic>>.from(_queue.take(_maxBatch));
      _queue.removeRange(0, batch.length);

      await _client.dio.post<dynamic>('/analytics', data: batch);
    } catch (_) {
      // Dropped on purpose. Retrying telemetry is not worth the battery, the
      // bandwidth, or the risk of a retry storm on a flaky connection. This
      // also swallows secure-storage failures, which happen on simulators and
      // must never surface to the user.
    } finally {
      _flushing = false;
    }
  }
}

final analyticsProvider = Provider<Analytics>((ref) {
  return Analytics(
    ref.read(apiClientProvider),
    ref.read(authStorageProvider),
  );
});
