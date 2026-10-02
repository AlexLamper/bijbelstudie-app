import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/retention_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible/present/bible_providers.dart';
import '../../bible_year/present/bible_year_providers.dart';
import '../../friends/present/friends_providers.dart';
import '../../onboarding/present/tour_controller.dart';
import '../../study/present/study_pane_controller.dart';
import '../data/daily_verse_store.dart';
import '../data/dashboard_models.dart';
import 'daily_verse_card.dart';
import 'dashboard_providers.dart';
import 'friends_section.dart';
import 'home_main_card.dart';
import 'widgets/home_header_actions.dart';
import 'widgets/streak_ring.dart';

/// `/dashboard`, folded into one column: header, one main card, the tekst van
/// de dag, then "Bij je vrienden".
///
/// The verse card is the point of the screen and has to be fully in view
/// without scrolling, so at most one card sits above it and that card is
/// compact. Aanbevolen studies, the book map and "Deze week" moved off this
/// tab - the book map lives on `/profile/bijbel`, the week strip in the streak
/// detail sheet.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);

    // The server streak is authoritative; feed it to the local mirror so a
    // later "streak broke" guess can be corrected (RETENTION_PLAN §2).
    ref.listen(dashboardProvider, (_, next) {
      final data = next.value;
      if (data != null) {
        ref.read(retentionStoreProvider.notifier).reconcileServerStreak(data.streak);
      }
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // The greeting header paints its own `scheme.surface` block full-bleed to
      // the very top of the screen (see `_DashboardBody`'s header `Container`,
      // which adds the status-bar inset itself), so only the loading / error
      // states - which have no header of their own - keep the top SafeArea.
      body: dashboard.when(
        loading: () => const DashboardSkeleton(),
        error: (error, _) => SafeArea(
          child: AppEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Dashboard niet geladen',
            description: '$error',
            action: SiteButton(
              label: 'Opnieuw proberen',
              expand: false,
              onPressed: () => ref.invalidate(dashboardProvider),
            ),
          ),
        ),
        data: (data) => SafeArea(
          top: false,
          bottom: false,
          child: RefreshIndicator(
            color: AppTheme.teal,
            onRefresh: () async {
              ref.invalidate(dashboardProvider);
              await ref.read(friendsFeedProvider.notifier).refresh();
              if (ref.exists(bibleYearProvider)) {
                await ref.read(bibleYearProvider.notifier).refresh();
              }
            },
            child: _DashboardBody(data: data),
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.data});

  final DashboardData data;

  void _openChapter(
    BuildContext context,
    WidgetRef ref, {
    required String book,
    required int chapter,
    String version = 'statenvertaling',
  }) {
    ref
        .read(readerLocationProvider.notifier)
        .openChapter(versionId: version, book: book, chapter: chapter);
    // The split screen remembers which half the reader left it on, so someone
    // who was last in "Studie" would land there instead of on the verse they
    // just asked to read. Naming a chapter is a request to read it.
    ref.read(studyPaneProvider.notifier).showReader();
    context.go('/study');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final hasArchivedVerse =
        ref.watch(dailyVerseStoreProvider).history.isNotEmpty;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── Header: greeting, date, streak pill ──────────────────────────
        // Paints full-bleed under the status bar; the outer Scaffold has no
        // top SafeArea for this branch, so the status-bar inset is added here
        // instead of letting the scaffold background show through above it.
        Container(
          padding: EdgeInsets.fromLTRB(
            20,
            20 + MediaQuery.of(context).padding.top,
            20,
            18,
          ),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(bottom: BorderSide(color: scheme.outline)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greetingFor(data.name, email: data.email),
                      style: AppTheme.displaySmall.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(dutchLongDate(), style: AppTheme.bodyMuted),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: HomeHeaderActions(
                  streak: HomeStreakIndicator(
                    serverStreak: data.streak,
                    freezes: data.freezes,
                    weekDays: data.weekDays,
                  ),
                ),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // One main card, never two: the reading plan while a plan runs
              // and today is unfinished, else "Waar je gebleven was", else
              // nothing. Together with the verse card it is "je startpunt",
              // which is what the tour's first step points at.
              TourAnchor(
                id: TourAnchorIds.dashboardHero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HomeMainCard(data: data),

                    // The tekst van de dag has to be fully in view without
                    // scrolling; everything above it is compact for its sake.
                    // The card renders today's verse, or - offline - the
                    // newest one in its local archive, which is why the
                    // archive is consulted here too.
                    if (data.dailyVerse != null || hasArchivedVerse)
                      DailyVerseCard(
                        verse: data.dailyVerse,
                        onOpenChapter: (book, chapter) => _openChapter(
                          context,
                          ref,
                          book: book,
                          chapter: chapter,
                        ),
                      ),
                  ],
                ),
              ),

              // Below the fold on purpose: the reader scrolls to their
              // vriendenkring, never past the verse to reach it.
              const SizedBox(height: 28),
              const FriendsSection(),
            ],
          ),
        ),
      ],
    );
  }
}
