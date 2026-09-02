import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../data/resources_repository.dart';

/// `/hulpbronnen` — the library of public-domain Dutch works.
///
/// Each entry opens on the archive that hosts it (DBNL, Delpher,
/// Archive.org, Gutenberg). Nothing is mirrored into the app, which is both a
/// rights position and the reason the binary stays small.
class ResourcesScreen extends ConsumerStatefulWidget {
  const ResourcesScreen({super.key});

  @override
  ConsumerState<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends ConsumerState<ResourcesScreen> {
  String _category = 'alle';
  bool _lockedImpressionReported = false;

  /// One `paywall_hit` per visit, the first time the loaded library actually
  /// contains something locked.
  ///
  /// The gate here is the row of lock badges, not the tap - by the time someone
  /// taps a locked item they have already decided to look, and counting only
  /// taps would make this surface look far more persuasive than it is. Reported
  /// from a post-frame callback because `build` must stay free of side effects.
  void _reportLockedImpression(ResourceLibrary library) {
    if (_lockedImpressionReported) return;
    if (!library.items.any((item) => item.locked)) return;
    _lockedImpressionReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(analyticsProvider).track(AnalyticsEvents.paywallHit, {
        'surface': 'resources',
      });
    });
  }

  Color _colorFor(String hex) {
    final cleaned = hex.replaceAll('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return AppTheme.teal;
    return Color(cleaned.length == 6 ? 0xFF000000 | value : value);
  }

  Future<void> _open(ResourceItem item) async {
    if (item.locked) {
      if (!mounted) return;
      ref.read(analyticsProvider).track(AnalyticsEvents.paywallCtaClicked, {
        'surface': 'resources',
      });
      context.push('/pro-intro?source=app_resources');
      return;
    }
    final uri = Uri.tryParse(item.sourceUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(resourceLibraryProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                title: 'Hulpbronnen',
                subtitle: 'Bijbels, uitleg, preken en belijdenisgeschriften.',
              ),
            ),
            Expanded(
              child: library.when(
                loading: () => const SkeletonList(rows: 6),
                error: (error, _) => AppEmptyState(
                  icon: Icons.wifi_off_outlined,
                  title: 'Hulpbronnen niet geladen',
                  description: '$error',
                  action: SiteButton(
                    label: 'Opnieuw proberen',
                    expand: false,
                    onPressed: () => ref.invalidate(resourceLibraryProvider),
                  ),
                ),
                data: (data) {
                  _reportLockedImpression(data);

                  final items = _category == 'alle'
                      ? data.items
                      : data.items.where((i) => i.category == _category).toList();

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    children: [
                      SizedBox(
                        height: 34,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: data.categories.length + 1,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final id = index == 0 ? 'alle' : data.categories[index - 1].id;
                            final label =
                                index == 0 ? 'Alle' : data.categories[index - 1].label;
                            final tint = index == 0
                                ? AppTheme.teal
                                : _colorFor(data.categories[index - 1].color);
                            final active = _category == id;

                            return InkWell(
                              onTap: () => setState(() => _category = id),
                              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: active ? tint : scheme.surface,
                                  border: Border.all(
                                    color: active ? tint : scheme.outline,
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(AppTheme.radiusPill),
                                ),
                                child: Text(
                                  label,
                                  style: AppTheme.caption.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: active ? Colors.white : scheme.onSurface,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (items.isEmpty)
                        const AppEmptyState(
                          icon: Icons.search_off,
                          title: 'Geen hulpbronnen',
                          description: 'Er is niets in deze categorie.',
                        )
                      else
                        for (final item in items) ...[
                          _ResourceCard(
                            item: item,
                            tint: _colorFor(
                              data.categories
                                      .where((c) => c.id == item.category)
                                      .firstOrNull
                                      ?.color ??
                                  '#0D9488',
                            ),
                            onOpen: () => _open(item),
                          ),
                          const SizedBox(height: 10),
                        ],
                    ],
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

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.item,
    required this.tint,
    required this.onOpen,
  });

  final ResourceItem item;
  final Color tint;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      radius: AppTheme.radiusMd,
      padding: const EdgeInsets.all(16),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconChip(icon: Icons.menu_book_outlined, color: tint, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: AppTheme.displayBase.copyWith(color: scheme.onSurface),
                    ),
                    if (item.byline.isNotEmpty)
                      Text(item.byline, style: AppTheme.caption),
                  ],
                ),
              ),
              if (item.locked)
                Icon(Icons.lock_outline, size: 15, color: AppTheme.inkFaint)
              else
                Icon(Icons.open_in_new, size: 15, color: AppTheme.inkFaint),
            ],
          ),
          const SizedBox(height: 10),
          Text(item.description, style: AppTheme.bodyMuted),
          const SizedBox(height: 10),
          Row(
            children: [
              SiteBadge.neutral(item.source),
              const Spacer(),
              if (item.locked)
                Text(
                  'Pro',
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.teal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.rightsNote,
            style: AppTheme.caption.copyWith(fontSize: 11, color: AppTheme.inkFaint),
          ),
        ],
      ),
    );
  }
}
