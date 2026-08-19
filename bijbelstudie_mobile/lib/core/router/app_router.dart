import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/preview_config.dart';
import '../theme/app_theme.dart';
import '../ui/app_widgets.dart';

import '../../features/auth/present/splash_screen.dart';
import '../../features/onboarding/present/onboarding_screen.dart';
import '../../features/auth/present/login_screen.dart';
import '../../features/auth/present/register_screen.dart';
import '../../features/bible/present/read_screen.dart';
import '../../features/commentary/present/commentary_screen.dart';
import '../../features/dashboard/present/dashboard_screen.dart';
import '../../features/groups/present/group_detail_screen.dart';
import '../../features/groups/present/groups_screen.dart';
import '../../features/notes/present/notes_screen.dart';
import '../../features/premium/present/premium_screen.dart';
import '../../features/profile/present/profile_screen.dart';
import '../../features/resources/present/resources_screen.dart';
import '../../features/search/present/search_screen.dart';
import '../../features/settings/present/settings_screen.dart';
import '../../features/studies/present/studies_screen.dart';
import '../../features/study/present/study_screen.dart';

/// Bottom tabs, mirroring the website's sidebar
/// (`components/layout/app-sidebar.tsx`): Dashboard, Bijbelstudie, Studies,
/// Groepen, Notities, Hulpbronnen — trimmed to the five that fit a phone bar,
/// with Hulpbronnen and Groepen reachable from the dashboard's "Snel naar"
/// card and from Profiel.
class MainScaffold extends StatelessWidget {
  const MainScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentIndex = _calculateSelectedIndex(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: child,
      bottomNavigationBar: Container(
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
    );
  }

  static const List<_NavItemData> _items = [
    _NavItemData(Icons.dashboard_outlined, Icons.dashboard, 'Start', '/dashboard'),
    _NavItemData(Icons.menu_book_outlined, Icons.menu_book, 'Bijbel', '/study'),
    _NavItemData(Icons.school_outlined, Icons.school, 'Studies', '/studies'),
    _NavItemData(Icons.sticky_note_2_outlined, Icons.sticky_note_2, 'Notities', '/notes'),
    _NavItemData(Icons.person_outline, Icons.person, 'Profiel', '/profile'),
  ];

  static int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    for (var i = 0; i < _items.length; i++) {
      if (location.startsWith(_items[i].route)) return i;
    }
    // Sections without their own tab still highlight where they belong.
    if (location.startsWith('/read') || location.startsWith('/commentary')) return 1;
    if (location.startsWith('/groups') || location.startsWith('/resources')) return 0;
    if (location.startsWith('/search')) return 1;
    return 0;
  }
}

class _NavItemData {
  const _NavItemData(this.icon, this.activeIcon, this.label, this.route);

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
}

/// The active tab is teal, matching every other active affordance on the site.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

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
            Icon(active ? item.activeIcon : item.icon, size: 21, color: color),
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

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    // Design-preview mode skips splash/onboarding/login and lands on the
    // dashboard so the styling can be reviewed straight away.
    initialLocation: PreviewConfig.enabled ? '/dashboard' : '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(path: '/study', builder: (context, state) => const StudyScreen()),
          GoRoute(
            path: '/studies',
            builder: (context, state) => const StudiesScreen(),
          ),
          GoRoute(path: '/notes', builder: (context, state) => const NotesScreen()),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          // Reachable from the dashboard and Profiel rather than the tab bar.
          GoRoute(
            path: '/resources',
            builder: (context, state) => const ResourcesScreen(),
          ),
          GoRoute(path: '/groups', builder: (context, state) => const GroupsScreen()),
          GoRoute(path: '/read', builder: (context, state) => const ReadScreen()),
          GoRoute(
            path: '/commentary',
            builder: (context, state) => const CommentaryScreen(),
          ),
          GoRoute(path: '/search', builder: (context, state) => const SearchScreen()),
        ],
      ),
      GoRoute(
        path: '/groups/:id',
        builder: (context, state) =>
            GroupDetailScreen(groupId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/premium',
        // ?source= records which surface sent the user to the paywall.
        builder: (context, state) =>
            PremiumScreen(source: state.uri.queryParameters['source']),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
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
                const Text('Deze pagina bestaat niet', style: AppTheme.displayLarge),
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
