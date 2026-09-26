import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../domain/bronnen_models.dart';
import 'bronnen_providers.dart';
import 'bronnen_toc.dart';

/// `/bronnen/:slug` - one work: what it is, where to start or resume, the
/// table of contents and where the text comes from.
class BronWorkScreen extends ConsumerWidget {
  const BronWorkScreen({super.key, required this.slug});

  final String slug;

  void _openSection(BuildContext context, String sectionId) {
    context.push('/bronnen/$slug/${Uri.encodeComponent(sectionId)}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final work = ref.watch(bronWorkProvider(slug));
    final position = ref.watch(bronPositionProvider(slug)).value;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text(work.value?.shortTitle ?? 'Bronnen')),
      body: work.when(
        loading: () => const SkeletonList(rows: 6),
        error: (error, _) => AppEmptyState(
          icon: Icons.wifi_off_outlined,
          title: 'Tekst niet geladen',
          description: '$error'.replaceFirst('Exception: ', ''),
          action: SiteButton(
            label: 'Opnieuw proberen',
            expand: false,
            onPressed: () => ref.invalidate(bronWorkProvider(slug)),
          ),
        ),
        data: (work) {
          final resume = position == null ? null : work.section(position);
          final heads = [for (final s in work.sections) s.head];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
            children: [
              Text(work.title, style: AppTheme.displayMedium),
              if (work.byline.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(work.byline, style: AppTheme.bodyMuted),
              ],
              const SizedBox(height: 4),
              Text(
                work.countLabel,
                style: AppTheme.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.tealStrong,
                ),
              ),
              if (work.description.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(work.description, style: AppTheme.bodyLead),
              ],
              const SizedBox(height: 20),
              if (resume != null) ...[
                SiteButton(
                  label: 'Verder lezen: ${resume.label}',
                  onPressed: () => _openSection(context, resume.id),
                ),
                const SizedBox(height: 10),
                SiteOutlineButton(
                  label: 'Begin met lezen',
                  onPressed: () => _openSection(context, work.sections.first.id),
                ),
              ] else
                SiteButton(
                  label: 'Begin met lezen',
                  onPressed: () => _openSection(context, work.sections.first.id),
                ),
              const SizedBox(height: 28),
              const Eyebrow('Inhoud'),
              const SizedBox(height: 10),
              BronToc(
                sections: heads,
                currentId: resume?.id,
                onOpen: (id) => _openSection(context, id),
              ),
              const SizedBox(height: 28),
              _AboutText(work: work),
            ],
          );
        },
      ),
    );
  }
}

class _AboutText extends StatelessWidget {
  const _AboutText({required this.work});

  final BronWork work;

  Future<void> _openSource() async {
    final uri = Uri.tryParse(work.source.url);
    if (uri == null || !uri.hasScheme) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final hasUrl = work.source.url.isNotEmpty;
    return AppCard(
      radius: AppTheme.radiusMd,
      padding: const EdgeInsets.all(16),
      color: AppTheme.paperSunken,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Over deze tekst'),
          const SizedBox(height: 8),
          if (work.rights.isNotEmpty) ...[
            Text(work.rights, style: AppTheme.caption),
            const SizedBox(height: 8),
          ],
          if (work.source.name.isNotEmpty)
            InkWell(
              onTap: hasUrl ? _openSource : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Bron: ${work.source.name}',
                        style: AppTheme.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: hasUrl ? AppTheme.teal : AppTheme.inkMuted,
                        ),
                      ),
                    ),
                    if (hasUrl) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.open_in_new, size: 13, color: AppTheme.teal),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text('Schriftteksten uit de Statenvertaling.', style: AppTheme.caption),
        ],
      ),
    );
  }
}
