import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/content_cache.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../domain/bible_models.dart';
import '../domain/copy_policy.dart';
import '../domain/version_catalog.dart';
import 'bible_providers.dart';
import 'book_download_button.dart';
import 'version_badge.dart';

/// Translation picker. Only allowlisted versions ever reach the client, so
/// there is nothing to filter here - the server already did it.
///
/// Opens on the canvas colour rather than on card white: every translation is
/// its own card, and a card needs something to sit on. The book picker below
/// keeps the raised fill, because its rows are rows.
Future<void> showVersionPickerSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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

/// Chrome shared by both pickers: grab handle, heading, hairline, scrollable
/// body.
///
/// The heading used to be an [Eyebrow] - 12px uppercase in the faintest ink
/// the palette has - which is the treatment for a label *inside* a screen, not
/// for the name of the thing you just opened. It is a sheet title now, in the
/// display face, with room under it for one line of context.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.child, this.subtitle});

  final String title;

  /// One quiet line under the title - which translation is open, say. Null
  /// leaves the title alone.
  final String? subtitle;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    // The version picker has a text field in it, so the sheet has to give the
    // keyboard its space back instead of letting it sit over the list.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (context, controller) => Column(
        children: [
          const _SheetGrabHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.displaySmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
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

/// The pill at the top of a sheet. The sheet drags between two heights, and
/// nothing else on it says so.
class _SheetGrabHandle extends StatelessWidget {
  const _SheetGrabHandle();

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppTheme.ruleStrong,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        ),
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

  /// The name of the open translation, for the line under the sheet title.
  /// Null until the catalog has loaded - the id on its own is not a name worth
  /// showing a reader.
  String? _openVersionName(List<BibleSource>? versions, String current) {
    if (versions == null) return null;
    for (final version in versions) {
      if (version.id == current) return version.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final versionsAsync = ref.watch(bibleVersionsProvider);
    final current = ref.watch(readerLocationProvider).versionId;
    final needle = _query.text.trim().toLowerCase();

    // What is already on the device, per translation, so a card can say so.
    // Read off the loaded value only: the picker never waits on the cache, and
    // no counts yet simply means no offline line yet.
    final offline = _offlineBookCounts(
      ref.watch(offlineBooksProvider).value ?? const <OfflineBook>[],
    );
    final openName = _openVersionName(versionsAsync.value, current);

    return _SheetFrame(
      title: 'Vertaling',
      subtitle: openName == null ? null : 'Nu geopend: $openName',
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
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
                  children: [
                    for (final group in groups) ...[
                      LanguageSectionHeader(
                        label: group.label,
                        count: group.versions.length,
                      ),
                      for (final version in group.versions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _VersionCard(
                            version: version,
                            selected: version.id == current,
                            offlineBooks: offline[version.id] ?? 0,
                            onTap: () {
                              ref
                                  .read(readerLocationProvider.notifier)
                                  .openChapter(versionId: version.id);
                              Navigator.of(context).pop();
                            },
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
    AppTheme.dependOn(context);
    // A single raised fill - the app's own `inputDecorationTheme` fill - now
    // that the sheet stands on the canvas colour. It used to be sunken, which
    // was right against a raised sheet and invisible against this one: in
    // light mode the canvas and the sunken fill are the same grey. The border,
    // radius and focus ring still come from the shared theme. No wrapper
    // Container: that used to stack a second themed fill and a themed outline
    // border inside this box.
    final hasText = controller.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
          filled: true,
          fillColor: AppTheme.paperRaised,
          hintText: 'Zoek een vertaling',
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Wissen',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
        ),
      ),
    );
  }
}

/// How many books of each translation are stored on this device, keyed by
/// version id. One entry per translation the reader has downloaded anything
/// of; a translation with nothing cached is simply absent.
Map<String, int> _offlineBookCounts(List<OfflineBook> books) {
  final counts = <String, int>{};
  for (final book in books) {
    counts[book.sourceId] = (counts[book.sourceId] ?? 0) + 1;
  }
  return counts;
}

/// One translation, as a card.
///
/// Was a full-bleed row with a hairline under it, which put nine translations
/// in a column of identical stripes and left the reader reading names to find
/// the one they wanted. The card gives each translation an edge of its own and
/// lets the chosen one be a different object rather than a tinted stripe.
///
/// Reading order is deliberate: the short code first, because that is the
/// handle a reader already has for a translation (`SV`, `KJV`) and the same
/// code the reader's badge shows; then the full Dutch name; then the quiet
/// facts - who holds the text, what is downloaded, what the licence allows.
/// Nothing here is an icon standing in for a word.
class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.version,
    required this.selected,
    required this.offlineBooks,
    required this.onTap,
  });

  final BibleSource version;

  /// The translation the reader currently has open.
  final bool selected;

  /// Books of this translation stored on the device, 0 for none.
  final int offlineBooks;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    // Same answer the download button and the verse sheet get, from the same
    // policy file - a translation may be read here either way, so this is a
    // note about copying, not a lock on the row.
    final restricted = isCopyRestricted(version.id);

    return Semantics(
      button: true,
      selected: selected,
      label: [
        version.name,
        'afkorting ${VersionCatalog.shortCode(version)}',
        if (selected) 'nu geopend',
      ].join(', '),
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        radius: AppTheme.radiusMd,
        padding: const EdgeInsets.all(12),
        color: selected ? AppTheme.tealTint : AppTheme.paperRaised,
        borderColor: selected ? AppTheme.teal : AppTheme.rule,
        child: Row(
          children: [
            VersionBadge.forVersion(version, selected: selected, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    version.name,
                    style: AppTheme.displayTitle.copyWith(fontSize: 15.5, height: 1.25),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (version.attribution.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      version.attribution,
                      style: AppTheme.caption.copyWith(
                        fontSize: 11.5,
                        height: 1.35,
                        color: AppTheme.inkFaint,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (offlineBooks > 0)
                    _VersionFact(
                      icon: Icons.offline_pin_outlined,
                      label: offlineBooks == 1
                          ? '1 boek offline beschikbaar'
                          : '$offlineBooks boeken offline beschikbaar',
                    ),
                  if (restricted)
                    const _VersionFact(
                      icon: Icons.lock_outline,
                      label: 'Alleen losse verzen kopiëren',
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _SelectionMark(selected: selected),
          ],
        ),
      ),
    );
  }
}

/// One quiet fact under a translation's name - what is downloaded, what the
/// licence allows. Small icon, small type, muted ink: a detail of the card,
/// never competing with the name above it.
class _VersionFact extends StatelessWidget {
  const _VersionFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AppTheme.inkMuted),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              style: AppTheme.caption.copyWith(fontSize: 11.5, height: 1.2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Filled when this is the open translation, an empty ring when it is not.
///
/// A tint on the card was doing this job alone, which is not enough: tints
/// read as decoration, and the two Dutch cards nearest the top of the list
/// looked much the same. A solid mark is unambiguous at a glance and in a
/// screenshot.
class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    if (!selected) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.ruleStrong, width: 1.5),
        ),
      );
    }
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppTheme.teal, shape: BoxShape.circle),
      child: const Icon(Icons.check, size: 14, color: Colors.white),
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
