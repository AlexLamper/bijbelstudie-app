import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible/present/bible_providers.dart' show readerLocationProvider;
import '../../bible/present/read_screen.dart' show pendingVerseAnchorProvider;
import '../../settings/data/reading_settings.dart';
import '../data/bronnen_prefs.dart';
import '../domain/bronnen_models.dart';
import 'bronnen_blocks.dart';
import 'bronnen_providers.dart';
import 'bronnen_toc.dart';

/// `/bronnen/:slug/:sectionId` - the reader. One page per section, swiped
/// sideways; the section the reader is on is remembered per work so the work
/// page can offer "Verder lezen".
class BronSectionReaderScreen extends ConsumerWidget {
  const BronSectionReaderScreen({
    super.key,
    required this.slug,
    required this.sectionId,
  });

  final String slug;
  final String sectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final work = ref.watch(bronWorkProvider(slug));
    return work.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const SkeletonList(rows: 6),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: AppEmptyState(
          icon: Icons.wifi_off_outlined,
          title: 'Tekst niet geladen',
          description: '$error'.replaceFirst('Exception: ', ''),
          action: SiteButton(
            label: 'Opnieuw proberen',
            expand: false,
            onPressed: () => ref.invalidate(bronWorkProvider(slug)),
          ),
        ),
      ),
      data: (work) => BronSectionPager(work: work, initialSectionId: sectionId),
    );
  }
}

/// The pager itself, split out so a test can pump it with a work in hand.
class BronSectionPager extends ConsumerStatefulWidget {
  const BronSectionPager({
    super.key,
    required this.work,
    required this.initialSectionId,
  });

  final BronWork work;
  final String initialSectionId;

  @override
  ConsumerState<BronSectionPager> createState() => _BronSectionPagerState();
}

class _BronSectionPagerState extends ConsumerState<BronSectionPager> {
  late int _index;
  late final PageController _controller;

  BronWork get _work => widget.work;

  @override
  void initState() {
    super.initState();
    _index = _work.indexOfSection(widget.initialSectionId).clamp(0, _work.sections.length - 1);
    _controller = PageController(initialPage: _index);
    _remember();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _remember() {
    final slug = _work.slug;
    final id = _work.sections[_index].id;
    unawaited(
      BronnenPrefs.setPosition(slug, id).then((_) {
        if (mounted) ref.invalidate(bronPositionProvider(slug));
      }),
    );
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    _remember();
  }

  Future<void> _showContents() async {
    final picked = await showBronTocSheet(
      context,
      title: _work.shortTitle,
      sections: [for (final s in _work.sections) s.head],
      currentId: _work.sections[_index].id,
    );
    if (picked == null || !mounted) return;
    final target = _work.indexOfSection(picked);
    if (target < 0 || target == _index) return;
    _controller.jumpToPage(target);
  }

  void _openRef(BronRef r) {
    if (!r.isResolved) return;
    final verses = r.verses;
    ref.read(pendingVerseAnchorProvider.notifier).set(
      verses == null || verses.isEmpty ? null : verses.first,
    );
    ref.read(readerLocationProvider.notifier).openChapter(
      book: r.readerBook,
      chapter: r.chapter,
    );
    context.go('/read');
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final expandAll = ref.watch(bronExpandAllProvider);
    final fontSize = ref.watch(readingSettingsProvider.select((s) => s.fontSize.points));
    final section = _work.sections[_index];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _work.shortTitle,
              style: AppTheme.caption,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              section.label,
              style: AppTheme.displayBase,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _showContents,
            icon: const Icon(Icons.format_list_bulleted),
            tooltip: 'Inhoud',
          ),
          PopupMenuButton<String>(
            tooltip: 'Meer',
            onSelected: (value) {
              if (value == 'expand') {
                ref.read(bronExpandAllProvider.notifier).set(!expandAll);
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem<String>(
                value: 'expand',
                checked: expandAll,
                child: const Text('Schriftteksten voluit'),
              ),
            ],
          ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: _work.sections.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, i) => BronSectionView(
          key: PageStorageKey('bron:${_work.slug}:${_work.sections[i].id}'),
          section: _work.sections[i],
          fontSize: fontSize,
          expandAll: expandAll,
          onOpenRef: _openRef,
        ),
      ),
    );
  }
}
