import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/groups_repository.dart';

/// `/groepen` — the study groups the reader is in, plus the public ones.
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nieuwe groep'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Naam'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Omschrijving'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Aanmaken'),
          ),
        ],
      ),
    );

    if (created != true || nameController.text.trim().isEmpty) return;

    await ref
        .read(groupsRepositoryProvider)
        .createGroup(
          name: nameController.text.trim(),
          description: descriptionController.text.trim(),
        );
    ref.invalidate(groupsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider(null));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        onPressed: () => _createGroup(context, ref),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(bottom: BorderSide(color: scheme.outline)),
              ),
              child: const GradientHeader(
                title: 'Groepen',
                subtitle: 'Lees samen en deel wat je opvalt.',
              ),
            ),
            Expanded(
              child: groups.when(
                loading: () => const AppLoader(),
                error: (error, _) => AppEmptyState(
                  icon: Icons.wifi_off_outlined,
                  title: 'Groepen niet geladen',
                  description: '$error',
                  action: SiteButton(
                    label: 'Opnieuw proberen',
                    expand: false,
                    onPressed: () => ref.invalidate(groupsProvider),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.groups_outlined,
                      title: 'Nog geen groepen',
                      description:
                          'Maak een groep aan en nodig anderen uit met de '
                          'uitnodigingscode.',
                    );
                  }

                  final mine = list.where((g) => g.isMember).toList();
                  final others = list.where((g) => !g.isMember).toList();

                  return RefreshIndicator(
                    color: AppTheme.teal,
                    onRefresh: () async => ref.invalidate(groupsProvider),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      children: [
                        if (mine.isNotEmpty) ...[
                          Text('MIJN GROEPEN', style: AppTheme.eyebrow),
                          const SizedBox(height: 10),
                          for (final group in mine) ...[
                            _GroupCard(group: group),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 12),
                        ],
                        if (others.isNotEmpty) ...[
                          Text('OPENBARE GROEPEN', style: AppTheme.eyebrow),
                          const SizedBox(height: 10),
                          for (final group in others) ...[
                            _GroupCard(group: group),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCard extends ConsumerWidget {
  const _GroupCard({required this.group});

  final StudyGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      radius: AppTheme.radiusMd,
      padding: const EdgeInsets.all(16),
      onTap: group.isMember
          ? () => context.push('/groups/${group.id}')
          : () async {
              final failure = await ref
                  .read(groupsRepositoryProvider)
                  .join(group.id);
              if (!context.mounted) return;
              if (failure != null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(failure)));
                return;
              }
              ref.invalidate(groupsProvider);
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconChip(icon: Icons.groups_outlined, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: AppTheme.displayBase.copyWith(color: scheme.onSurface),
                    ),
                    Text(
                      '${group.memberCount} '
                      '${group.memberCount == 1 ? 'lid' : 'leden'}'
                      '${group.isPublic ? '' : ' · besloten'}',
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
              if (group.isLeader) SiteBadge.teal('Leider'),
              if (!group.isMember)
                Text(
                  'Deelnemen',
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.teal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          if (group.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(group.description, style: AppTheme.bodyMuted),
          ],
          if (group.assignment != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.assignment_outlined, size: 13, color: AppTheme.teal),
                const SizedBox(width: 6),
                Text(
                  'Deze week: ${group.assignment}',
                  style: AppTheme.caption.copyWith(color: AppTheme.teal),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
