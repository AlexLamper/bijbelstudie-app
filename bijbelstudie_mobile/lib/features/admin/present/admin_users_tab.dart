import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../domain/admin_entities.dart';
import 'admin_common.dart';
import 'admin_providers.dart';
import 'admin_user_sheet.dart';

/// Which slice of the account list is on screen.
enum _AccountFilter { all, pro, admins, billing }

/// The users tab — the website's `/admin/users` table as a searchable list.
///
/// Searching and filtering run over the already-loaded page (the repository
/// fetches up to 500 at once), so typing never waits on the network. Tapping a
/// row opens the same sheet the overview's recent-signups list uses.
class AdminUsersTab extends ConsumerStatefulWidget {
  const AdminUsersTab({super.key});

  @override
  ConsumerState<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends ConsumerState<AdminUsersTab> {
  final _controller = TextEditingController();
  _AccountFilter _filter = _AccountFilter.all;
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<AdminAccount> _visible(List<AdminAccount> accounts) {
    final needle = _query.trim().toLowerCase();
    return accounts.where((account) {
      final matchesFilter = switch (_filter) {
        _AccountFilter.all => true,
        _AccountFilter.pro => account.isPro,
        _AccountFilter.admins => account.isAdmin,
        _AccountFilter.billing => account.hasBillingIssue,
      };
      if (!matchesFilter) return false;
      if (needle.isEmpty) return true;
      return account.name.toLowerCase().contains(needle) ||
          account.email.toLowerCase().contains(needle);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(adminUsersProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(
            children: [
              TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Zoek op naam of e-mailadres',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Wissen',
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final entry in const {
                      _AccountFilter.all: 'Alle accounts',
                      _AccountFilter.pro: 'Pro',
                      _AccountFilter.admins: 'Beheerders',
                      _AccountFilter.billing: 'Betaalproblemen',
                    }.entries) ...[
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _filter == entry.key,
                        onSelected: (_) => setState(() => _filter = entry.key),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.teal,
            onRefresh: () async {
              ref.invalidate(adminUsersProvider);
              await ref.read(adminUsersProvider.future);
            },
            child: users.when(
              loading: () => ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
                children: const [
                  SkeletonCard(height: 220, child: SkeletonText(lines: 6)),
                  SizedBox(height: 12),
                  SkeletonCard(height: 220, child: SkeletonText(lines: 6)),
                ],
              ),
              error: (error, _) => ListView(
                padding: const EdgeInsets.symmetric(vertical: 24),
                children: [
                  AdminErrorState(
                    error: error,
                    onRetry: () => ref.invalidate(adminUsersProvider),
                  ),
                ],
              ),
              data: (accounts) {
                final visible = _visible(accounts);
                if (visible.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    children: const [
                      AppEmptyState(
                        icon: Icons.person_search_outlined,
                        title: 'Geen accounts',
                        description:
                            'Geen account voldoet aan deze zoekopdracht of '
                            'dit filter.',
                      ),
                    ],
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        visible.length == accounts.length
                            ? '${adminNumber(accounts.length)} accounts'
                            : '${adminNumber(visible.length)} van '
                                  '${adminNumber(accounts.length)} accounts',
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.inkMuted,
                        ),
                      ),
                    ),
                    AppCard(
                      child: Column(
                        children: [
                          for (var i = 0; i < visible.length; i++)
                            AdminAccountRow(
                              account: visible[i],
                              trailing: adminNumber(visible[i].noteCount),
                              showRule: i < visible.length - 1,
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
