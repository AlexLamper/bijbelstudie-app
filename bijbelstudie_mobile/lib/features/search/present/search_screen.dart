import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/content_cache.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible/data/bible_repository.dart';
import '../../bible/domain/bible_models.dart';
import '../../bible/present/bible_providers.dart';

/// Server-side search with a local history.
///
/// The device only holds the chapters it has read, so searching locally would
/// silently miss most of the Bible. History is local because it is personal
/// and needs to work offline.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  SearchResults? _results;
  bool _loading = false;
  String? _error;
  List<String> _history = const [];
  bool _wholeBible = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final cache = ref.read(contentCacheProvider);
    if (cache == null) return;
    final history = await cache.recentSearches();
    if (mounted) setState(() => _history = history);
  }

  Future<void> _run(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return;

    final location = ref.read(readerLocationProvider);
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await ref.read(bibleRepositoryProvider).search(
            query: trimmed,
            versionId: location.versionId,
            book: _wholeBible ? null : location.book,
          );
      await ref.read(contentCacheProvider)?.recordSearch(trimmed);
      await _loadHistory();
      if (mounted) setState(() => _results = results);
    } on ContentNotLicensedException {
      if (mounted) {
        setState(() => _error = 'Deze vertaling is niet beschikbaar in de app.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Zoeken mislukt. Controleer je verbinding.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(readerLocationProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Zoeken'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _run,
                    decoration: InputDecoration(
                      hintText: 'Zoek in de Bijbel',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        onPressed: () => _run(_controller.text),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Hele Bijbel'),
                        selected: _wholeBible,
                        onSelected: (_) => setState(() => _wholeBible = true),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text('Alleen ${location.book}'),
                        selected: !_wholeBible,
                        onSelected: (_) => setState(() => _wholeBible = false),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const RuleLine(),
            Expanded(child: _body(location)),
          ],
        ),
      ),
    );
  }

  Widget _body(ReaderLocation location) {
    if (_loading) return const SkeletonList(rows: 6);
    if (_error != null) {
      return AppEmptyState(icon: Icons.error_outline, title: 'Zoeken mislukt', description: _error);
    }

    final results = _results;
    if (results == null) return _historyList();

    if (results.hits.isEmpty) {
      return const AppEmptyState(
        icon: Icons.search_off,
        title: 'Niets gevonden',
        description: 'Probeer een ander woord of zoek in een andere vertaling.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: results.hits.length + (results.truncated ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == results.hits.length) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Meer resultaten beschikbaar - verfijn je zoekopdracht of zoek in één boek.',
              style: AppTheme.bodyMuted.copyWith(fontSize: 12),
            ),
          );
        }

        final hit = results.hits[index];
        return RuleListTile(
          onTap: () {
            ref
                .read(readerLocationProvider.notifier)
                .openChapter(book: hit.book, chapter: hit.chapter);
            context.go('/read');
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hit.reference, style: AppTheme.caption.copyWith(color: AppTheme.lapis)),
              const SizedBox(height: 4),
              Text(hit.text, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        );
      },
    );
  }

  Widget _historyList() {
    if (_history.isEmpty) {
      return const AppEmptyState(
        icon: Icons.search,
        title: 'Doorzoek de Bijbel',
        description: 'Typ een woord of een zinsdeel. Je zoekgeschiedenis blijft op dit toestel.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Eyebrow('Recent gezocht'),
              TextButton(
                onPressed: () async {
                  await ref.read(contentCacheProvider)?.clearSearchHistory();
                  await _loadHistory();
                },
                child: const Text('Wissen'),
              ),
            ],
          ),
        ),
        for (final query in _history)
          RuleListTile(
            onTap: () {
              _controller.text = query;
              _run(query);
            },
            child: Row(
              children: [
                const Icon(Icons.history, size: 16, color: AppTheme.inkMuted),
                const SizedBox(width: 12),
                Expanded(child: Text(query, style: Theme.of(context).textTheme.bodyLarge)),
              ],
            ),
          ),
      ],
    );
  }
}
