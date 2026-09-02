import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_widgets.dart';
import 'admin_insights_tab.dart';
import 'admin_overview_tab.dart';
import 'admin_providers.dart';
import 'admin_users_tab.dart';

/// The beheer screen: the website's `/admin` overview, `/admin/insights` and
/// `/admin/users` as three tabs.
///
/// [isAdminProvider] only decides whether this screen is *shown*. Every call it
/// makes hits `/api/v1/admin/*`, which re-reads the account server-side and
/// answers 403 to anyone else — so reaching this route without the rights
/// yields empty error states, never data.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Beheer')),
        body: const AppEmptyState(
          icon: Icons.lock_outline,
          title: 'Geen toegang',
          description: 'Dit account heeft geen beheerdersrechten.',
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Beheer'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Overzicht'),
              Tab(text: 'Inzichten'),
              Tab(text: 'Gebruikers'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [AdminOverviewTab(), AdminInsightsTab(), AdminUsersTab()],
        ),
      ),
    );
  }
}
