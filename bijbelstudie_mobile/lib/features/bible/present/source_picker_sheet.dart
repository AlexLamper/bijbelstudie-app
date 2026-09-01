import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../domain/bible_models.dart';
import '../domain/version_catalog.dart';
import 'bible_providers.dart';
import 'book_download_button.dart';
import 'version_badge.dart';

/// Translation picker. Only allowlisted versions ever reach the client, so
/// there is nothing to filter here — the server already did it.
Future<void> showVersionPickerSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
    ),
    builder: (_) => const _VersionPicker(),
  );
}

Future<void> showBookPickerSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
    ),
    builder: (_) => const _BookPicker(),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The version picker has a text field in it, so the sheet has to give the
    // keyboard its space back instead of letting it sit over the list.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Align(alignment: Alignment.centerLeft, child: Eyebrow(title)),
          ),
          const RuleLine(),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: keyboard),
              child: PrimaryScrollController(controller: controller, child: child),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionPicker extends ConsumerStatefulWidget {
  const _VersionPicker();

  @override
  ConsumerState<_VersionPicker> createState() => _VersionPickerState();
}

class _VersionPickerState extends ConsumerState<_VersionPicker> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Name, description, short code and language all match: a reader after the
  /// Statenvertaling may well type "SV", and one after the English block may
  /// well type "engels".
  bool _matches(BibleSource version, String needle) {
    if (needle.isEmpty) return true;
    final haystack = [
      version.name,
      version.attribution,
      VersionCatalog.shortCode(version),
      version.languageLabel,
      version.language,
    ].join(' ').toLowerCase();
    return haystack.contains(needle);
  }

  @override
  Widget build(BuildContext context) {
    final versionsAsync = ref.watch(bibleVersionsProvider);
    final current = ref.watch(readerLocationProvider).versionId;
    final needle = _query.text.trim().toLowerCase();

    return _SheetFrame(
      title: 'Vertaling',
      child: Column(
        children: [
          _VersionSearchField(
            controller: _query,
            onChanged: (_) => setState(() {}),
          ),
          const RuleLine(),
          Expanded(
            child: versionsAsync.when(
              loading: () => const SkeletonList(rows: 8),
              error: (_, __) => const AppEmptyState(
                icon: Icons.wifi_off_outlined,
                title: 'Vertalingen niet geladen',
                description: 'Controleer je verbinding en probeer het opnieuw.',
              ),
              // Grouped by language under a real section header. The catalog
              // already orders Dutch before English; what was missing was a
              // heading, so the English translations read as more Dutch ones
              // that happened to have English names.
              //
              // The groups are built from the *filtered* list, so the counts
              // follow the search and a language with no match drops out.
              data: (versions) {
                final groups = VersionCatalog.grouped(
                  versions.where((v) => _matches(v, needle)),
                );
                if (groups.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.search_off_outlined,
                    title: 'Geen vertalingen gevonden',
                    description: 'Probeer een andere naam of afkorting.',
                  );
                }
                return ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    for (final group in groups) ...[
                      LanguageSectionHeader(
                        label: group.label,
                        count: group.versions.length,
                      ),
                      for (final version in group.versions)
                        RuleListTile(
                          onTap: () {
                            ref
                                .read(readerLocationProvider.notifier)
                                .openChapter(versionId: version.id);
                            Navigator.of(context).pop();
                          },
                          child: Row(
                            children: [
                              VersionBadge.forVersion(
                                version,
                                selected: version.id == current,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      version.name,
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      version.attribution,
                                      style: AppTheme.bodyMuted.copyWith(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              if (version.id == current)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Icon(Icons.check, size: 18, color: AppTheme.lapis),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The picker's search box. Pinned above the list rather than scrolling with
/// it, so it stays reachable once a reader has scrolled into the English
/// block.
class _VersionSearchField extends StatelessWidget {
  const _VersionSearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.paperSunken,
          border: Border.all(color: AppTheme.rule),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.search, size: 18, color: AppTheme.inkMuted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                cursorColor: AppTheme.ink,
                cursorWidth: 1.4,
                style: TextStyle(
                  fontFamily: AppTheme.sansFontName,
                  fontSize: 15,
                  color: AppTheme.ink,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Zoek een vertaling',
                  hintStyle: TextStyle(
                    fontFamily: AppTheme.sansFontName,
                    fontSize: 15,
                    color: AppTheme.inkMuted,
                  ),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: AppTheme.inkMuted),
                tooltip: 'Wissen',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _BookPicker extends ConsumerStatefulWidget {
  const _BookPicker();

  @override
  ConsumerState<_BookPicker> createState() => _BookPickerState();
}

class _BookPickerState extends ConsumerState<_BookPicker> {
  String? _expandedBook;

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(readerLocationProvider);
    final booksAsync = ref.watch(bibleBooksProvider(location.versionId));

    return _SheetFrame(
      title: 'Boek en hoofdstuk',
      child: booksAsync.when(
        loading: () => const SkeletonList(rows: 10),
        error: (error, __) => AppEmptyState(
          icon: error is ContentNotLicensedException
              ? Icons.gavel_outlined
              : Icons.wifi_off_outlined,
          title: error is ContentNotLicensedException
              ? 'Niet beschikbaar in de app'
              : 'Boeken niet geladen',
          description: error is ContentNotLicensedException
              ? 'Deze vertaling mag alleen op de website worden aangeboden.'
              : 'Controleer je verbinding en probeer het opnieuw.',
        ),
        data: (books) => ListView.builder(
          itemCount: books.length,
          itemBuilder: (context, index) {
            final book = books[index];
            final expanded = _expandedBook == book;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RuleListTile(
                  showRule: !expanded,
                  onTap: () => setState(() => _expandedBook = expanded ? null : book),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(book, style: Theme.of(context).textTheme.titleMedium),
                      ),
                      if (book == location.book)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: SiteBadge.lapis('Nu'),
                        ),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: AppTheme.inkMuted,
                      ),
                    ],
                  ),
                ),
                if (expanded) _ChapterGrid(book: book, versionId: location.versionId),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChapterGrid extends ConsumerWidget {
  const _ChapterGrid({required this.book, required this.versionId});

  final String book;
  final String versionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersAsync = ref.watch(bibleChaptersProvider(BookRef(versionId, book)));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.paperSunken,
        border: Border(bottom: BorderSide(color: AppTheme.rule)),
      ),
      child: chaptersAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: SkeletonText(lines: 2, lineHeight: 12, gap: 12),
        ),
        error: (_, __) => Text('Hoofdstukken niet geladen', style: AppTheme.bodyMuted),
        data: (chapters) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chapter in chapters)
                  Semantics(
                    button: true,
                    label: '$book hoofdstuk $chapter',
                    child: InkWell(
                      onTap: () {
                        ref
                            .read(readerLocationProvider.notifier)
                            .openChapter(book: book, chapter: chapter);
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        width: 40,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.paperRaised,
                          border: Border.all(color: AppTheme.rule),
                          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        ),
                        child: Text('$chapter', style: AppTheme.caption),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            BookDownloadButton(versionId: versionId, book: book, chapters: chapters),
          ],
        ),
      ),
    );
  }
}
