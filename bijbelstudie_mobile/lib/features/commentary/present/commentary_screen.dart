import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../bible/present/bible_providers.dart';
import '../../settings/data/reading_settings.dart';
import 'commentary_pane.dart';

/// Standalone commentary view.
///
/// The website only reaches this content through the study page's materials
/// pane, which is what [StudyMaterialsPane] mirrors. This screen keeps the
/// same two panes available on their own, for deep links and for the reader
/// who wants the commentary full width.
class CommentaryScreen extends ConsumerStatefulWidget {
  const CommentaryScreen({super.key});

  @override
  ConsumerState<CommentaryScreen> createState() => _CommentaryScreenState();
}

class _CommentaryScreenState extends ConsumerState<CommentaryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(readerLocationProvider);
    final settings = ref.watch(readingSettingsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Verdieping'),
                  const SizedBox(height: 8),
                  Text(
                    '${location.book} ${location.chapter}',
                    style: AppTheme.displaySmall.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelStyle: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
              tabs: const [Tab(text: 'Commentaar'), Tab(text: 'Grondtekst')],
            ),
            const RuleLine(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  CommentaryPane(location: location, settings: settings),
                  OriginalTextPane(location: location),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
