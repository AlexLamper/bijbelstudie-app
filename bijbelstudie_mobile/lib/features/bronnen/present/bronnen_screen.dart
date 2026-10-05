import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../domain/bronnen_models.dart';
import 'bronnen_providers.dart';

/// `/bronnen` - the confessions, catechism booklets and liturgical forms of
/// the Dutch Reformed tradition, read in the app itself rather than linked
/// out to. Grouped as the server groups them.
class BronnenScreen extends ConsumerWidget {
  const BronnenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final index = ref.watch(bronnenIndexProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // No top SafeArea: the header paints behind the status bar and pads its
      // own content down, the same way the leesplan header does.
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(bottom: BorderSide(color: scheme.outline)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: IconButton(
                      tooltip: 'Terug',
                      onPressed: () =>
                          context.canPop() ? context.pop() : context.go('/dashboard'),
                      icon: Icon(Icons.arrow_back_ios_new, size: 20, color: AppTheme.inkSoft),
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 2, 20, 14),
                    child: GradientHeader(
                      title: 'Bronnen',
                      subtitle: 'Belijdenis, catechismus en formulieren',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: index.when(
                loading: () => const SkeletonList(rows: 6),
                error: (error, _) => AppEmptyState(
                  icon: Icons.wifi_off_outlined,
                  title: 'Bronnen niet geladen',
                  description: '$error'.replaceFirst('Exception: ', ''),
                  action: SiteButton(
                    label: 'Opnieuw proberen',
                    expand: false,
                    onPressed: () => ref.invalidate(bronnenIndexProvider),
                  ),
                ),
                data: (data) {
                  final groups = data.grouped;
                  if (groups.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.menu_book_outlined,
                      title: 'Nog geen bronnen',
                      description: 'Er zijn nog geen teksten beschikbaar.',
                    );
                  }
                  return RefreshIndicator(
                    color: AppTheme.teal,
                    onRefresh: () => ref.refresh(bronnenIndexProvider.future),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                      children: [
                        for (final (group, works) in groups) ...[
                          Text(group.label.toUpperCase(), style: AppTheme.groupLabel),
                          if (group.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(group.description, style: AppTheme.caption),
                          ],
                          const SizedBox(height: 12),
                          for (final work in works) ...[
                            BronWorkCard(
                              work: work,
                              onOpen: () => context.push('/bronnen/${work.slug}'),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 18),
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

class BronWorkCard extends StatelessWidget {
  const BronWorkCard({super.key, required this.work, required this.onOpen});

  final BronWorkSummary work;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return AppCard(
      radius: AppTheme.radiusMd,
      padding: const EdgeInsets.all(16),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(work.title, style: AppTheme.displayTitle),
          if (work.byline.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(work.byline, style: AppTheme.caption),
          ],
          if (work.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              work.description,
              style: AppTheme.bodyMuted,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            work.countLabel,
            style: AppTheme.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.tealStrong,
            ),
          ),
        ],
      ),
    );
  }
}
