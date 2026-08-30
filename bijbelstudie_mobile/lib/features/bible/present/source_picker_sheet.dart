import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../domain/bible_models.dart';
import '../domain/version_catalog.dart';
import 'bible_providers.dart';
import 'book_download_button.dart';
import 'language_separator.dart';

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
            child: PrimaryScrollController(controller: controller, child: child),
          ),
        ],
      ),
    );
  }
}

class _VersionPicker extends ConsumerWidget {
  const _VersionPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionsAsync = ref.watch(bibleVersionsProvider);
    final current = ref.watch(readerLocationProvider).versionId;

    return _SheetFrame(
      title: 'Vertaling',
      child: versionsAsync.when(
        loading: () => const AppLoader(),
        error: (_, __) => const AppEmptyState(
          icon: Icons.wifi_off_outlined,
          title: 'Vertalingen niet geladen',
          description: 'Controleer je verbinding en probeer het opnieuw.',
        ),
        // Grouped by language rather than listed flat. The catalog already
        // orders Dutch before English; what was missing was any visible break
        // between them, so the English translations read as more Dutch ones
        // that happened to have English names.
        data: (versions) {
          final groups = VersionCatalog.grouped(versions);
          return ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              for (var g = 0; g < groups.length; g++) ...[
                // The first group is labelled too, unlike the setup wizard's
                // list: this sheet's only title is "Vertaling", so nothing
                // else here says which language the top rows are in.
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20).copyWith(
                    top: g == 0 ? 4 : 0,
                  ),
                  child: LanguageSeparator(label: groups[g].label),
                ),
                for (final version in groups[g].versions)
                  RuleListTile(
                    onTap: () {
                      ref
                          .read(readerLocationProvider.notifier)
                          .openChapter(versionId: version.id);
                      Navigator.of(context).pop();
                    },
                    child: Row(
                      children: [
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
                          const Icon(Icons.check, size: 18, color: AppTheme.lapis),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
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
        loading: () => const AppLoader(),
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
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
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
      decoration: const BoxDecoration(
        color: AppTheme.paperSunken,
        border: Border(bottom: BorderSide(color: AppTheme.rule)),
      ),
      child: chaptersAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: AppLoader(size: 20),
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
