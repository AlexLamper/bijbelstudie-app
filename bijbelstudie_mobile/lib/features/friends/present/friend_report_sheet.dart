import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/friend_models.dart';
import '../data/friends_repository.dart';
import 'friend_tap_target.dart';

/// "Melden" for one post, or for one reaction under it.
///
/// The real thing, in place of the generic feedback sheet this used to open:
/// that sheet sends `{message, category, page}` and carries no post id at all,
/// so a melding from it could not reach the moderation queue for the content
/// it was about. This sends `POST /friends/posts/:id/report` with a reason
/// slug from [friendReportReasons] and the optional note.
///
/// A second melding on the same thing is an upsert server-side and comes back
/// ok, so a repeat tap reads as "bedankt" rather than as a failure - which is
/// the truth: it did work, it simply updated the reason.
Future<void> showFriendReportSheet(
  BuildContext context, {
  required String postId,
  String? commentId,
  String? authorName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _FriendReportSheet(
      postId: postId,
      commentId: commentId,
      authorName: authorName,
    ),
  );
}

class _FriendReportSheet extends ConsumerStatefulWidget {
  const _FriendReportSheet({
    required this.postId,
    this.commentId,
    this.authorName,
  });

  final String postId;
  final String? commentId;
  final String? authorName;

  @override
  ConsumerState<_FriendReportSheet> createState() => _FriendReportSheetState();
}

class _FriendReportSheetState extends ConsumerState<_FriendReportSheet> {
  final _note = TextEditingController();
  FriendReportReason? _reason;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _isComment => (widget.commentId ?? '').isNotEmpty;

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(friendsRepositoryProvider).reportPost(
      postId: widget.postId,
      reason: reason,
      note: _note.text,
      commentId: widget.commentId,
    );
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = result.message;
      });
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final media = MediaQuery.of(context);
    final who = widget.authorName?.trim() ?? '';

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + media.viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isComment ? 'Reactie melden' : 'Bericht melden',
                style: AppTheme.displaySmall,
              ),
              const SizedBox(height: 6),
              Text(
                who.isEmpty
                    ? 'Wat is er mis? We kijken ernaar en de melder blijft anoniem.'
                    : 'Wat is er mis met wat $who deelde? We kijken ernaar en de '
                          'melder blijft anoniem.',
                style: AppTheme.bodyMuted,
              ),
              const SizedBox(height: 10),
              // Plain tappable rows rather than RadioListTile: the Radio API
              // is mid-migration in Flutter and a group value is overkill for
              // six lines that set one field.
              for (final reason in friendReportReasons)
                _ReasonRow(
                  label: friendReportReasonLabel(reason),
                  selected: _reason == reason,
                  onTap: _busy ? null : () => setState(() => _reason = reason),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                enabled: !_busy,
                minLines: 2,
                maxLines: 4,
                maxLength: maxFriendReportNote,
                decoration: const InputDecoration(
                  labelText: 'Toelichting (niet verplicht)',
                  hintText: 'Wat moeten we weten?',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: AppTheme.caption.copyWith(
                    fontSize: 12.5,
                    color: AppTheme.destructive,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SiteButton(
                label: 'Melden',
                loading: _busy,
                // No reason picked is nothing to send: the server refuses a
                // slug outside REPORT_REASONS with a 400, so the button waits
                // rather than guessing one.
                onPressed: _reason == null ? null : _send,
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Annuleren'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One reason to pick, with the tick on the chosen one.
class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    return FriendTapTarget(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? AppTheme.teal : AppTheme.inkMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTheme.bodyStrong.copyWith(
                  fontSize: 14.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
