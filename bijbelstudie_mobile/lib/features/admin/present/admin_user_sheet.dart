import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/admin_repository.dart';
import '../domain/admin_entities.dart';
import 'admin_common.dart';
import 'admin_providers.dart';

/// One account as a tappable row — used by both the users tab and the recent
/// signups card on the overview.
class AdminAccountRow extends StatelessWidget {
  const AdminAccountRow({
    super.key,
    required this.account,
    this.trailing,
    this.showRule = true,
  });

  final AdminAccount account;

  /// Small right-hand text: the signup age on the overview, the note count in
  /// the list.
  final String? trailing;

  final bool showRule;

  @override
  Widget build(BuildContext context) {
    return RuleListTile(
      showRule: showRule,
      onTap: () => showAdminUserSheet(context, account),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.teal.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Text(
              account.initial,
              style: AppTheme.bodyStrong.copyWith(color: AppTheme.teal),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        account.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodyStrong,
                      ),
                    ),
                    if (account.isPro) ...[
                      const SizedBox(width: 6),
                      SiteBadge.vermilion('PRO'),
                    ],
                    if (account.isAdmin) ...[
                      const SizedBox(width: 6),
                      SiteBadge.teal('ADMIN'),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  account.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            Text(trailing!, style: AppTheme.caption),
          ],
          if (account.hasBillingIssue || account.needsReconcile) ...[
            const SizedBox(width: 8),
            Icon(Icons.warning_amber_outlined, size: 15, color: AppTheme.flame),
          ],
        ],
      ),
    );
  }
}

/// Opens the account detail sheet: every field the website's user table shows,
/// plus the two flags an admin may flip and the delete action.
Future<void> showAdminUserSheet(BuildContext context, AdminAccount account) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => _AdminUserSheet(account: account),
  );
}

class _AdminUserSheet extends ConsumerStatefulWidget {
  const _AdminUserSheet({required this.account});

  final AdminAccount account;

  @override
  ConsumerState<_AdminUserSheet> createState() => _AdminUserSheetState();
}

class _AdminUserSheetState extends ConsumerState<_AdminUserSheet> {
  late AdminAccount _account = widget.account;
  bool _busy = false;

  /// Runs one write, then refreshes the list so the row shows server truth
  /// rather than an optimistic guess. [describe] builds the success message.
  Future<void> _run(
    Future<void> Function() action, {
    required String describe,
    AdminAccount? next,
    bool close = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (next != null && mounted) setState(() => _account = next);
      ref.invalidate(adminUsersProvider);
      ref.invalidate(adminStatsProvider);
      if (!mounted) return;
      if (close) Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(describe)));
    } catch (error) {
      if (!mounted) return;
      final message = error is AdminException
          ? error.message
          : 'Er ging iets mis. Probeer het opnieuw.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Account verwijderen?'),
        content: Text(
          '${_account.displayName} (${_account.email}) wordt permanent '
          'verwijderd. Notities worden ook gewist.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Verwijderen',
              style: TextStyle(color: AppTheme.destructive),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => ref.read(adminRepositoryProvider).deleteUser(_account.id),
      describe: '${_account.email} verwijderd',
      close: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.teal.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      account.initial,
                      style: AppTheme.displayBase.copyWith(
                        color: AppTheme.teal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.displayName,
                          style: AppTheme.displayBase,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          account.email,
                          style: AppTheme.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (account.isPro) SiteBadge.vermilion('Pro'),
                  if (account.isAdmin) SiteBadge.teal('Beheerder'),
                  if (account.isComped) SiteBadge.neutral('Gratis toegekend'),
                  if (account.storePremium)
                    SiteBadge.neutral(
                      account.storePremiumPlatform == 'apple'
                          ? 'App Store'
                          : account.storePremiumPlatform == 'google'
                          ? 'Play Store'
                          : 'Store',
                    ),
                  if (account.hasBillingIssue)
                    SiteBadge.vermilion('Betaalprobleem'),
                  if (account.needsReconcile)
                    SiteBadge.vermilion('Betaald zonder Pro'),
                  if (account.cancelAtPeriodEnd)
                    SiteBadge.neutral('Zegt op'),
                ],
              ),
              const SizedBox(height: 18),
              AppCard(
                radius: AppTheme.radiusMd,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Column(
                  children: [
                    AdminStatRow(
                      label: 'Aangemeld',
                      value: adminDate(account.createdAt),
                    ),
                    AdminStatRow(
                      label: 'Abonnementsstatus',
                      value: account.subscriptionStatus ?? '—',
                    ),
                    AdminStatRow(
                      label: 'Interval',
                      value: switch (account.subscriptionInterval) {
                        'monthly' => 'Maandelijks',
                        'annual' => 'Jaarlijks',
                        _ => '—',
                      },
                    ),
                    AdminStatRow(
                      label: 'Loopt tot',
                      value: adminDate(account.currentPeriodEnd),
                    ),
                    AdminStatRow(
                      label: 'Stripe-klant',
                      value: account.hasStripe ? 'Ja' : 'Nee',
                    ),
                    AdminStatRow(
                      label: 'Streak',
                      value: '${adminNumber(account.streak)} dagen',
                    ),
                    AdminStatRow(
                      label: 'Laatste streakdag',
                      value: adminDate(account.lastStreakDate),
                    ),
                    AdminStatRow(
                      label: 'Notities',
                      value: adminNumber(account.noteCount),
                    ),
                    AdminStatRow(
                      label: 'Onboarding afgerond',
                      value: account.onboardingCompleted ? 'Ja' : 'Nee',
                      showRule: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text('Beheer', style: AppTheme.bodyStrong),
              const SizedBox(height: 4),
              Text(
                'Pro handmatig aanzetten is een gratis toekenning; de eerste '
                'Stripe-webhook overschrijft hem weer.',
                style: AppTheme.caption,
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pro-toegang'),
                subtitle: Text(
                  account.storePremium
                      ? 'Store-abonnement staat hier los van'
                      : 'Zet `subscribed` aan of uit',
                  style: AppTheme.caption,
                ),
                value: account.subscribed,
                activeColor: AppTheme.teal,
                onChanged: _busy
                    ? null
                    : (value) => _run(
                        () => ref
                            .read(adminRepositoryProvider)
                            .updateUser(account.id, subscribed: value),
                        describe: value
                            ? 'Pro-toegang aangezet'
                            : 'Pro-toegang uitgezet',
                        next: account.copyWith(subscribed: value),
                      ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Beheerder'),
                subtitle: Text(
                  'Je kunt je eigen rechten niet intrekken',
                  style: AppTheme.caption,
                ),
                value: account.isAdmin,
                activeColor: AppTheme.teal,
                onChanged: _busy
                    ? null
                    : (value) => _run(
                        () => ref
                            .read(adminRepositoryProvider)
                            .updateUser(account.id, isAdmin: value),
                        describe: value
                            ? 'Beheerder gemaakt'
                            : 'Beheerdersrechten ingetrokken',
                        next: account.copyWith(isAdmin: value),
                      ),
              ),
              const SizedBox(height: 14),
              SiteOutlineButton(
                label: 'Account verwijderen',
                icon: Icons.delete_outline,
                onPressed: _busy ? null : _confirmDelete,
              ),
              if (_busy) ...[
                const SizedBox(height: 14),
                Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
