import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/preview_config.dart';
import '../notifications/notification_service.dart';
import '../theme/app_theme.dart';
import '../ui/app_widgets.dart';

import '../../features/admin/present/admin_screen.dart';
import '../../features/premium/present/paywall_funnel_screen.dart';
import '../../features/study/present/lesson/lesson_screen.dart';
import '../../features/auth/present/auth_controller.dart';
import '../../features/auth/present/splash_screen.dart';
import '../../features/onboarding/present/onboarding_screen.dart';
import '../../features/onboarding/present/tour_controller.dart';
import '../../features/onboarding/present/setup_flow_screen.dart';
import '../../features/onboarding/present/tour_screen.dart';
import '../../features/auth/present/login_screen.dart';
import '../../features/auth/present/register_screen.dart';
import '../../features/bible/present/read_screen.dart';
import '../../features/bible/present/reader_chrome.dart';
import '../../features/commentary/present/commentary_screen.dart';
import '../../features/dashboard/present/dashboard_screen.dart';
import '../../features/notes/present/notes_screen.dart';
import '../../features/premium/present/premium_screen.dart';
import '../../features/profile/present/profile_screen.dart';
import '../../features/resources/present/resources_screen.dart';
import '../../features/search/present/search_screen.dart';
import '../../features/settings/present/settings_screen.dart';
import '../../features/studies/present/studies_screen.dart';
import '../../features/studies/present/study_detail_screen.dart';
import '../../features/study/present/study_pane_controller.dart';
import '../../features/study/present/study_screen.dart';

/// Bottom tabs, mirroring the website's sidebar
/// (`components/layout/app-sidebar.tsx`): Dashboard, Bijbelstudie, Studies,
/// Notities, Hulpbronnen — trimmed to the five that fit a phone bar, with
/// Hulpbronnen reachable from the dashboard's "Snel naar" card and from
/// Profiel. Groepen is hidden for the MVP: no tab, no links, and `/groups`
/// redirects to the dashboard so a stale deep link cannot strand anyone.
class MainScaffold extends ConsumerWidget {
  const MainScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final currentIndex = _calculateSelectedIndex(context);

    // The reader hides the tab bar while the user scrolls down through the
    // chapter. Only the reader may: every other tab reads `true` regardless of
    // what the provider holds, so a missed reset can never strand a screen
    // without a way out.
    //
    // "The reader" is two routes, not one. `/read` is the standalone reader,
    // but the reader people actually use is the left pane of `/study`, and
    // matching `/read` alone meant the top bar (owned by ReadScreen, which does
    // not care about the route) slid away there while the tab bar stayed put.
    // `/study` only counts while its reader pane is the one showing, so the
    // study materials keep their tab bar; `/studies` is excluded on purpose -
    // `startsWith('/study')` would swallow it.
    final path = GoRouterState.of(context).uri.path;
    final inStudyReader =
        (path == '/study' || path.startsWith('/study/')) &&
        !ref.watch(studyPaneProvider.select((pane) => pane.showMaterials));
    final inReader = path.startsWith('/read') || inStudyReader;
    final chromeVisible = !inReader || ref.watch(readerChromeVisibleProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: child,
      bottomNavigationBar: ReaderChromeReveal(
        visible: chromeVisible,
        axisAlignment: 1,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outline)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 60,
              child: Row(
                children: [
                  for (var i = 0; i < _items.length; i++)
                    Expanded(
                      child: _NavItem(
                        item: _items[i],
                        active: currentIndex == i,
                        onTap: () => context.go(_items[i].route),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const List<_NavItemData> _items = [
    _NavItemData(Icons.home_outlined, Icons.home_rounded, 'Start', '/dashboard', 'nav-dashboard'),
    _NavItemData(
      Icons.auto_stories_outlined,
      Icons.auto_stories,
      'Bijbel',
      '/study',
      TourAnchorIds.navStudy,
    ),
    _NavItemData(
      Icons.school_outlined,
      Icons.school,
      'Studies',
      '/studies',
      TourAnchorIds.navStudies,
    ),
    _NavItemData(
      Icons.sticky_note_2_outlined,
      Icons.sticky_note_2,
      'Notities',
      '/notes',
      TourAnchorIds.navNotes,
    ),
    _NavItemData(
      Icons.person_outline,
      Icons.person,
      'Profiel',
      '/profile',
      TourAnchorIds.navProfile,
    ),
  ];

  static int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    // Longest route first, or `/studies` would match `/study` and light up the
    // Bijbel tab instead of Studies.
    final byLength = List<int>.generate(_items.length, (i) => i)
      ..sort((a, b) => _items[b].route.length.compareTo(_items[a].route.length));
    for (final i in byLength) {
      final route = _items[i].route;
      if (location == route || location.startsWith('$route/')) return i;
    }
    // Sections without their own tab still highlight where they belong.
    if (location.startsWith('/read') || location.startsWith('/commentary')) return 1;
    if (location.startsWith('/resources')) return 0;
    if (location.startsWith('/search')) return 1;
    return 0;
  }
}

class _NavItemData {
  const _NavItemData(this.icon, this.activeIcon, this.label, this.route, this.tourAnchorId);

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;

  /// See [TourAnchorIds]. Every tab carries one even where no step points at
  /// it yet, so adding a step is a change to the step list alone.
  final String tourAnchorId;
}

/// The active tab is teal, matching every other active affordance on the site.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.item, required this.active, required this.onTap});

  final _NavItemData item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.teal : AppTheme.inkMuted;
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The tour's spotlight is cut around whatever this wraps. It sits
            // on the icon alone rather than on the whole tab cell: a cell is a
            // fifth of the bar wide and the full bar high, so spotlighting it
            // highlighted mostly empty space and the neighbouring tabs' margins.
            TourAnchor(
              id: item.tourAnchorId,
              child: Icon(
                active ? item.activeIcon : item.icon,
                size: 21,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontFamily: AppTheme.sansFontName,
                fontSize: 10.5,
                height: 1,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "into the app" transition: the screen fades up from a hair under full
/// size, so arriving from the splash reads as a move inward rather than a cut.
/// Used for the three routes the splash can hand off to.
Page<void> _diveInPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 440),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: Transform.scale(scale: 0.96 + 0.04 * curved.value, child: child),
      );
    },
    child: child,
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    // Design-preview mode skips splash/onboarding/login and lands on the
    // dashboard so the styling can be reviewed straight away.
    initialLocation: PreviewConfig.enabled ? '/dashboard' : '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => _diveInPage(state, const OnboardingScreen()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _diveInPage(
          state,
          LoginScreen(sessionExpired: state.uri.queryParameters['expired'] == '1'),
        ),
      ),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      // Post-registration setup and the guided tour - see
      // `resolvePostAuthRoute` for who is sent here and when. Both sit outside
      // the shell (full screen, no bottom nav) like `/onboarding`; `/tour` is
      // also reachable later via push from Profiel, hence no bottom nav there
      // either even on a replay.
      GoRoute(path: '/setup', builder: (context, state) => const SetupFlowScreen()),
      GoRoute(path: '/tour', builder: (context, state) => const TourScreen()),
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => _diveInPage(state, const DashboardScreen()),
          ),
          GoRoute(path: '/study', builder: (context, state) => const StudyScreen()),
          GoRoute(path: '/studies', builder: (context, state) => const StudiesScreen()),
          GoRoute(path: '/notes', builder: (context, state) => const NotesScreen()),
          GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
          // Reachable from the dashboard and Profiel rather than the tab bar.
          GoRoute(path: '/resources', builder: (context, state) => const ResourcesScreen()),
          // Groepen is out for the MVP. The route stays as a redirect so any
          // persisted route or old deep link resolves instead of hitting the
          // not-found page.
          GoRoute(path: '/groups', redirect: (context, state) => '/dashboard'),
          GoRoute(path: '/read', builder: (context, state) => const ReadScreen()),
          GoRoute(path: '/commentary', builder: (context, state) => const CommentaryScreen()),
          // ?book= carries the caller's current book so the "alleen dit boek"
          // scope is right; ?scope=book preselects it.
          GoRoute(
            path: '/search',
            builder: (context, state) => SearchScreen(
              initialBook: state.uri.queryParameters['book'],
              scopeToBook: state.uri.queryParameters['scope'] == 'book',
            ),
          ),
        ],
      ),
      GoRoute(path: '/groups/:id', redirect: (context, state) => '/dashboard'),
      // Outside the shell: a study is configured and then left for the reader,
      // so it gets a back arrow rather than a tab bar.
      GoRoute(
        path: '/studies/:id',
        builder: (context, state) => StudyDetailScreen(studyId: state.pathParameters['id']!),
      ),
      // The pre-sell: goal, then problem and proof, then what that means for
      // this reader. Ends by replacing itself with /premium, so the price is
      // still the one App Store-reviewed screen and backing out of it leaves
      // rather than walking the pitch backwards.
      GoRoute(
        path: '/pro-intro',
        builder: (context, state) =>
            PaywallFunnelScreen(source: state.uri.queryParameters['source']),
      ),
      GoRoute(
        path: '/premium',
        // ?source= records which surface sent the user to the paywall.
        builder: (context, state) => PremiumScreen(source: state.uri.queryParameters['source']),
      ),
      // One lesson of a guided study, full screen and outside the tab shell:
      // a lesson is a sitting, and a bottom bar inviting you elsewhere works
      // against it. `?stap=` resumes on the step the reader left off on.
      GoRoute(
        path: '/studie/:studyId/:day',
        builder: (context, state) => LessonScreen(
          studyId: state.pathParameters['studyId']!,
          day: int.tryParse(state.pathParameters['day'] ?? '') ?? 1,
          initialStep: state.uri.queryParameters['stap'],
        ),
      ),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      // Beheer. The screen hides itself for a non-admin and every call it
      // makes is re-checked server-side, so the route needs no redirect guard.
      GoRoute(path: '/admin', builder: (context, state) => const AdminScreen()),
      // `/home` was this app's post-login destination before the tab shell
      // landed and the target became `/dashboard`. App review 1.0(5) was
      // rejected because four call sites still pointed here and every one of
      // them dead-ended on the error page. The call sites are fixed; this
      // redirect stays so a stale deep link or a persisted route can never
      // reproduce it.
      GoRoute(path: '/home', redirect: (context, state) => '/dashboard'),
    ],
    // Never strand the user on go_router's default error page: its only
    // affordance is a link to `/`, which bounces through the splash screen and
    // can land straight back here. Apple's reviewer read that loop as the app
    // being unresponsive.
    errorBuilder: (context, state) => _RouteNotFound(location: state.uri.path),
  );
  // Let a tapped notification deep-link through this router (and flush a route
  // a cold-start tap left pending).
  NotificationService.attachRouter(router);
  return router;
});

/// Wires [ApiClient.onSessionExpired] to actually sign the user out.
///
/// `ApiClient` clears the stored tokens itself the moment a refresh fails, but
/// nothing used to be listening: the in-memory auth state stayed "signed in"
/// and the user kept looking at an app that worked, while every authenticated
/// request 401'd and every note, highlight, bookmark or reading position
/// written from then on was silently queued as if it were an offline blip.
/// `main.dart` reads this provider once, before the splash screen can make
/// its first authenticated request, so the hook is always set in time.
final sessionExpiryWiringProvider = Provider<void>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final router = ref.watch(routerProvider);
  apiClient.onSessionExpired = () {
    ref.read(authControllerProvider.notifier).signOutExpiredSession();
    router.go('/login?expired=1');
  };
});

class _RouteNotFound extends StatelessWidget {
  const _RouteNotFound({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Deze pagina bestaat niet', style: AppTheme.displayLarge),
                const SizedBox(height: 14),
                Text(
                  'We konden "$location" niet vinden. Ga terug naar je dashboard '
                  'om verder te lezen.',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyLead,
                ),
                const SizedBox(height: 32),
                SiteButton(
                  label: 'Naar dashboard',
                  trailingIcon: Icons.arrow_forward,
                  onPressed: () => context.go('/dashboard'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
