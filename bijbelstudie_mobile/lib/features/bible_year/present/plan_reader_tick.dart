import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/preview_config.dart';
import '../../../core/data/payload_cache.dart';
import '../../dashboard/present/dashboard_providers.dart';
import '../data/bible_year_models.dart';
import '../domain/plan_book_codes.dart';
import 'bible_year_providers.dart';

/// The normal reader scrolled [book] [chapter] to its end: ticks it in the
/// running "Bijbel in een jaar" plan, if there is one.
///
/// Takes the container, not a ref: the reader may be gone by the time the
/// plan state has loaded. Most readers have no plan, and building the plan
/// state is a request, so it is only built when something already says a plan
/// runs - the state itself is alive, the Start tab's `/dashboard` said so, or
/// the last plan payload on this device has one.
Future<void> tickPlanChapterAtEnd(ProviderContainer container, String book, int chapter) async {
  if (PreviewConfig.enabled) return;
  final code = planBookCode(book);
  if (code == null) return;
  try {
    if (!container.exists(bibleYearProvider) && !await _planKnown(container)) return;
    await container.read(bibleYearProvider.future);
    await container.read(bibleYearProvider.notifier).chapterReadToEnd(code, chapter);
  } catch (_) {
    // Offline or signed out: the next plan surface refetches anyway.
  }
}

Future<bool> _planKnown(ProviderContainer container) async {
  if (container.exists(dashboardProvider) &&
      container.read(dashboardProvider).value?.bibleYearActive == true) {
    return true;
  }
  final raw = await PayloadCache.read(BibleYearController.cacheKey);
  if (raw == null) return false;
  try {
    return BibleYearState.fromJson(raw).enrollment?.isActive == true;
  } catch (_) {
    return false;
  }
}
