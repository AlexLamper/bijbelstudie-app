import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../notes/present/note_row.dart';
import '../../notes/present/notes_providers.dart';
import '../../premium/present/pro_access_provider.dart';
import 'bible_providers.dart';
import 'book_download_button.dart';
import 'offline_library_sheet.dart';
import 'reader_settings_sheet.dart';

enum _MoreAction { display, offlineLibrary, paywall, bookmarks, share }

/// "Meer" in the reader header: a small card right under the dots, in the
/// app's plain [PopupMenuButton] style, with three 44px rows - offline,
/// bookmarks, share.
///
/// [child] is the header's own tool slot, so the dots line up with the other
/// tools in the row.
class ReaderMoreButton extends ConsumerWidget {
  const ReaderMoreButton({
    super.key,
    required this.location,
    required this.child,
    this.planMode = false,
  });

  final ReaderLocation location;
  final Widget child;

  /// The plan reader's menu: "Weergave" first (its bar has no "Aa"), and no
  /// "Bladwijzers", which would leave the plan for the Notities tab.
  final bool planMode;

  static const double rowHeight = 44;

  void _onSelected(BuildContext context, WidgetRef ref, _MoreAction action) {
    switch (action) {
      case _MoreAction.display:
        showReaderSettingsSheet(context, ref);
      case _MoreAction.offlineLibrary:
        showOfflineLibrarySheet(context);
      case _MoreAction.paywall:
        openOfflinePaywall(context, ref);
      case _MoreAction.bookmarks:
        ref.read(pendingNotesTabProvider.notifier).set(NotesTab.bookmarks);
        context.go('/notes');
      case _MoreAction.share:
        final reference = '${location.book} ${location.chapter}';
        shareRowText(context, text: '$reference\n${chapterLink(location)}', subject: reference);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);

    return PopupMenuButton<_MoreAction>(
      tooltip: 'Meer',
      color: AppTheme.surface,
      position: PopupMenuPosition.under,
      onSelected: (action) => _onSelected(context, ref, action),
      itemBuilder: (_) => [
        if (planMode)
          const PopupMenuItem(
            value: _MoreAction.display,
            height: rowHeight,
            child: _MenuRow(icon: Icons.text_fields, label: 'Weergave'),
          ),
        _DownloadMenuItem(bookRef: BookRef(location.versionId, location.book)),
        if (!planMode)
          const PopupMenuItem(
            value: _MoreAction.bookmarks,
            height: rowHeight,
            child: _MenuRow(icon: Icons.bookmark_outline, label: 'Bladwijzers'),
          ),
        const PopupMenuItem(
          value: _MoreAction.share,
          height: rowHeight,
          child: _MenuRow(icon: Icons.ios_share, label: 'Hoofdstuk delen'),
        ),
      ],
      child: child,
    );
  }
}

/// The website's reader at this chapter, in this translation - the same
/// `/lezen?book=&chapter=&version=` shape the dashboard's resume links use.
String chapterLink(ReaderLocation location) {
  return Uri.parse(AppConfig.baseUrl)
      .replace(
        path: '/lezen',
        queryParameters: {
          'book': location.book,
          'chapter': '${location.chapter}',
          'version': location.versionId,
        },
      )
      .toString();
}

/// "Downloaden voor offline": the current book of the current translation,
/// through the same [bookDownloadsProvider] the book picker uses.
///
/// Unlike the other rows it keeps the menu open when it starts a download, so
/// the row can show the progress; the download carries on if the menu is
/// closed. Once the book is complete it reads "Offline beschikbaar" and opens
/// the offline library, where it can be removed again. Without Pro it leads
/// to the paywall, like every other offline entry.
class _DownloadMenuItem extends PopupMenuItem<_MoreAction> {
  const _DownloadMenuItem({required this.bookRef})
      : super(child: null, height: ReaderMoreButton.rowHeight);

  final BookRef bookRef;

  @override
  PopupMenuItemState<_MoreAction, _DownloadMenuItem> createState() =>
      _DownloadMenuItemState();
}

class _DownloadMenuItemState extends PopupMenuItemState<_MoreAction, _DownloadMenuItem> {
  @override
  void handleTap() {
    final container = ProviderScope.containerOf(context, listen: false);
    final book = widget.bookRef;
    if (container.read(bookDownloadsProvider).containsKey(book)) return;

    final status = container.read(bookOfflineStatusProvider(book)).value;
    if (status?.isComplete ?? false) {
      Navigator.pop(context, _MoreAction.offlineLibrary);
      return;
    }
    if (!container.read(hasProProvider)) {
      Navigator.pop(context, _MoreAction.paywall);
      return;
    }

    final chapters = container.read(bibleChaptersProvider(book)).value ?? const <int>[];
    if (chapters.isEmpty) return;
    // Only what is not on disk yet, as the book picker's button does.
    final stored = status?.stored ?? const <int>[];
    final missing = chapters.where((c) => !stored.contains(c)).toList();
    runBookDownload(
      ScaffoldMessenger.maybeOf(context),
      container.read(bookDownloadsProvider.notifier),
      book,
      missing.isEmpty ? chapters : missing,
    );
  }

  @override
  Widget buildChild() => _DownloadRow(bookRef: widget.bookRef);
}

class _DownloadRow extends ConsumerWidget {
  const _DownloadRow({required this.bookRef});

  final BookRef bookRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    // Watched so the chapter list is loaded by the time the row is tapped.
    ref.watch(bibleChaptersProvider(bookRef));
    final progress = ref.watch(bookDownloadsProvider)[bookRef];
    final complete = ref.watch(bookOfflineStatusProvider(bookRef)).value?.isComplete ?? false;

    if (progress != null) {
      return _MenuRow(
        icon: Icons.downloading_outlined,
        label: '${progress.done} van ${progress.total} hoofdstukken',
        progress: progress.fraction,
      );
    }
    if (complete) {
      return _MenuRow(icon: Icons.check, label: 'Offline beschikbaar', iconColor: AppTheme.lapis);
    }
    return const _MenuRow(icon: Icons.download_outlined, label: 'Downloaden voor offline');
  }
}

/// Icon and label, in the menu's own text style. With [progress], a thin bar
/// under the label, as the book picker's download shows it.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.iconColor, this.progress});

  final IconData icon;
  final String label;
  final Color? iconColor;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final progress = this.progress;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: iconColor ?? AppTheme.inkSoft),
        const SizedBox(width: 12),
        Flexible(
          child: progress == null
              ? Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: AppTheme.rule,
                        color: AppTheme.lapis,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
