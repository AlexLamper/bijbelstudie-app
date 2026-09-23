import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/review_prompt.dart';

/// The explicit "Beoordeel de app" action.
///
/// A menu row the reader taps themselves is not a prompt, so this one is
/// allowed to leave the app and open the store listing outright — which is
/// exactly what the automatic path must never do. It is also the only escape
/// hatch for someone whose system quota for the native sheet is spent: the OS
/// silently shows nothing then, and there is no way for the app to find out.
///
/// Opening the listing is treated as terminal for the automatic ask. The
/// reader went to write a review of their own accord; following that up with
/// the native sheet weeks later would be asking twice.
Future<void> openStoreListingForReview(WidgetRef ref) async {
  await ref.read(reviewPromptProvider.notifier).markRated();

  try {
    await InAppReview.instance.openStoreListing(appStoreId: kAppStoreId);
    return;
  } catch (_) {
    // Fall through: on iOS the plugin needs the id, and a build without one
    // still deserves a working row.
  }

  if (defaultTargetPlatform == TargetPlatform.android) return;

  // The App Store page with the review composer already open.
  final uri = Uri.tryParse(appStoreWriteReviewUrl);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // A store that will not open is not worth an error message.
  }
}
