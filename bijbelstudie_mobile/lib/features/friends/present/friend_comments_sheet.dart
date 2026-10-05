import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/friend_models.dart';
import '../data/friends_repository.dart';
import 'friend_post_card.dart';
import 'friend_profile_screen.dart' show openFriendProfileFromSheet;
import 'friend_report_sheet.dart';
import 'friend_tap_target.dart';
import 'friends_error_card.dart';
import 'friends_providers.dart';

/// The reactions under one post: the post, then the thread, then the composer.
///
/// This replaces the composer-only sheet the card used to open. Comments were
/// write-only in the app - a reply could be sent and never read - while
/// `GET /friends/posts/:id/comments` had been answering all along.
Future<void> showFriendCommentsSheet(
  BuildContext context, {
  required FriendPost post,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => FriendCommentsSheet(post: post),
  );
}

/// The sheet's body. Public so a widget test can pump it without a route.
class FriendCommentsSheet extends ConsumerStatefulWidget {
  const FriendCommentsSheet({super.key, required this.post});

  final FriendPost post;

  @override
  ConsumerState<FriendCommentsSheet> createState() => _FriendCommentsSheetState();
}

class _FriendCommentsSheetState extends ConsumerState<FriendCommentsSheet> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await ref.read(friendsRepositoryProvider).addComment(widget.post.id, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reactie kon niet worden geplaatst')),
      );
      return;
    }
    _controller.clear();
    // The thread is the truth; the card's count only has to keep up, and a
    // full feed refresh here would throw away any extra pages already read.
    ref.invalidate(friendPostCommentsProvider(widget.post.id));
    ref.read(friendsFeedProvider.notifier).bumpCommentCount(widget.post.id);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final async = ref.watch(friendPostCommentsProvider(widget.post.id));
    final maxHeight = MediaQuery.of(context).size.height * 0.82;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text('Reacties', style: AppTheme.displayBase),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                children: [
                  _PostSummary(post: widget.post),
                  const SizedBox(height: 14),
                  const RuleLine(),
                  const SizedBox(height: 14),
                  ...switch (async) {
                    AsyncValue(hasError: true, :final error?) => [
                      FriendsErrorCard(
                        failure: error,
                        compact: true,
                        onRetry: () async {
                          ref.invalidate(friendPostCommentsProvider(widget.post.id));
                          await ref.read(
                            friendPostCommentsProvider(widget.post.id).future,
                          );
                        },
                      ),
                    ],
                    AsyncValue(:final value?) when value.isEmpty => [
                      Text(
                        'Nog geen reacties. Je mag de eerste zijn.',
                        style: AppTheme.caption.copyWith(fontSize: 13.5),
                      ),
                    ],
                    AsyncValue(:final value?) => [
                      for (var i = 0; i < value.length; i++) ...[
                        if (i > 0) const SizedBox(height: 14),
                        _CommentRow(
                          comment: value[i],
                          // Melden works on a reaction too: the report route
                          // takes the post id plus `commentId`, so the thread
                          // is not a place where moderation stops.
                          onReport: () => showFriendReportSheet(
                            context,
                            postId: widget.post.id,
                            commentId: value[i].id,
                            authorName: value[i].authorName,
                          ),
                        ),
                      ],
                    ],
                    _ => const [
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: AppLoader(),
                      ),
                    ],
                  },
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLines: 3,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(hintText: 'Schrijf een reactie'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SiteButton(
                    label: 'Plaatsen',
                    expand: false,
                    height: 44,
                    loading: _sending,
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The post the thread hangs under, without the heart / reaction row: in a
/// sheet those actions belong to the card that opened it.
class _PostSummary extends StatelessWidget {
  const _PostSummary({required this.post});

  final FriendPost post;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FriendTapTarget(
              circle: true,
              onTap: () => openFriendProfileFromSheet(context, post.authorId),
              child: FriendAvatar(
                name: post.authorName,
                image: post.authorImage,
                size: 32,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.authorName.isEmpty ? 'Een vriend' : post.authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyStrong.copyWith(fontSize: 14, color: scheme.onSurface),
                  ),
                  Text(
                    friendPostWhen(post.createdAt),
                    style: AppTheme.caption.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (post.reference != null && post.reference!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(post.reference!, style: AppTheme.metaLabel.copyWith(color: AppTheme.teal)),
        ],
        if (post.body.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            post.body,
            style: AppTheme.bodyStrong.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.45,
              color: scheme.onSurface,
            ),
          ),
        ],
      ],
    );
  }
}

/// One reaction: who, how long ago, and what they wrote.
class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment, this.onReport});

  final FriendPostComment comment;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FriendTapTarget(
          circle: true,
          onTap: () => openFriendProfileFromSheet(context, comment.authorId),
          child: FriendAvatar(
            name: comment.authorName,
            image: comment.authorImage,
            size: 28,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      comment.authorName.isEmpty ? 'Een vriend' : comment.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyStrong.copyWith(
                        fontSize: 13.5,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    friendPostWhen(comment.createdAt),
                    style: AppTheme.caption.copyWith(fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                comment.body,
                style: AppTheme.caption.copyWith(
                  fontSize: 13.5,
                  height: 1.4,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        if (onReport != null)
          IconButton(
            onPressed: onReport,
            icon: Icon(Icons.flag_outlined, size: 17, color: AppTheme.inkMuted),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: EdgeInsets.zero,
            tooltip: 'Reactie melden',
          ),
      ],
    );
  }
}
