import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/friend_models.dart';

/// One post in the vriendenkring feed: who, when, what, and the heart /
/// reaction / more row under it.
///
/// Provider-free so it renders from a fixed [post] in tests and in the Start
/// tab's "Bij je vrienden" block; [FriendPostList] wires it to the feed.
class FriendPostCard extends StatelessWidget {
  const FriendPostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onMore,
  });

  final FriendPost post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FriendAvatar(name: post.authorName, image: post.authorImage),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.authorName.isEmpty ? 'Een vriend' : post.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyStrong.copyWith(
                        fontSize: 14,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      '${_kindLabel(post.kind)} · ${friendPostWhen(post.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              _IconAction(
                icon: Icons.more_horiz,
                tooltip: 'Meer',
                onPressed: onMore,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 46, right: 6, top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.reference != null && post.reference!.isNotEmpty) ...[
                  Text(
                    post.reference!,
                    style: AppTheme.metaLabel.copyWith(color: AppTheme.teal),
                  ),
                  const SizedBox(height: 4),
                ],
                if (post.body.isNotEmpty)
                  Text(
                    post.body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyStrong.copyWith(
                      fontSize: 14,
                      fontWeight: post.kind == FriendPostKind.verse
                          ? FontWeight.w500
                          : FontWeight.w400,
                      height: 1.45,
                      color: scheme.onSurface,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Row(
              children: [
                _IconAction(
                  icon: post.likedByMe ? Icons.favorite : Icons.favorite_border,
                  color: post.likedByMe ? AppTheme.flame : null,
                  label: post.likeCount == 0 ? null : '${post.likeCount}',
                  tooltip: post.likedByMe ? 'Hart weghalen' : 'Hart geven',
                  onPressed: onLike,
                ),
                _IconAction(
                  icon: Icons.chat_bubble_outline,
                  label: post.commentCount == 0 ? null : '${post.commentCount}',
                  tooltip: 'Reageren',
                  onPressed: onComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _kindLabel(FriendPostKind kind) => switch (kind) {
    FriendPostKind.verse => 'Tekst van de dag',
    FriendPostKind.milestone => 'Mijlpaal',
    FriendPostKind.note => 'Notitie',
    FriendPostKind.other => 'Deelde iets',
  };
}

/// A friend's picture, or the first letter of their name on the brand tint -
/// the same circle [ProfileAvatar] draws, at feed size.
class FriendAvatar extends StatelessWidget {
  const FriendAvatar({super.key, required this.name, this.image, this.size = 36});

  final String name;
  final String? image;
  final double size;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
    final url = image?.trim();
    final letter = Text(
      initial,
      style: AppTheme.bodyStrong.copyWith(
        fontSize: size * 0.42,
        fontWeight: FontWeight.w700,
        color: AppTheme.tealStrong,
      ),
    );

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.tealTint,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.rule),
      ),
      child: url == null || url.isEmpty
          ? letter
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) => letter,
            ),
    );
  }
}

/// One footer action: icon, optional count, 44x44 tap target.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    this.label,
    this.color,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final String? label;
  final Color? color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppTheme.inkMuted;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: Container(
          height: 44,
          constraints: const BoxConstraints(minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: tint),
              if (label != null) ...[
                const SizedBox(width: 5),
                Text(label!, style: AppTheme.caption.copyWith(fontSize: 13, color: tint)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The sheet behind the heart's neighbour: a reaction, sent to the server.
/// Returns the text, or null when the reader backs out.
Future<String?> showFriendCommentSheet(BuildContext context) {
  final controller = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        20 + MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reageren', style: AppTheme.displayBase),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Schrijf een reactie'),
          ),
          const SizedBox(height: 14),
          SiteButton(
            label: 'Plaatsen',
            onPressed: () {
              final text = controller.text.trim();
              Navigator.of(sheetContext).pop(text.isEmpty ? null : text);
            },
          ),
        ],
      ),
    ),
  );
}

/// The `...` sheet: copy the reader's own link to the post, or report it.
Future<void> showFriendPostMoreSheet(
  BuildContext context, {
  required FriendPost post,
  required VoidCallback onReport,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Tekst kopieren'),
            onTap: () {
              final reference = post.reference;
              Clipboard.setData(
                ClipboardData(
                  text: reference == null || reference.isEmpty
                      ? post.body
                      : '${post.body}\n$reference',
                ),
              );
              Navigator.of(sheetContext).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Melden'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              onReport();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
