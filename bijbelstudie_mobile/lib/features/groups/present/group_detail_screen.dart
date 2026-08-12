import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/groups_repository.dart';

/// `/groepen/[id]` — the group's wall, its roster, and the invite code.
class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  final _composer = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final content = _composer.text.trim();
    if (content.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await ref.read(groupsRepositoryProvider).postMessage(widget.groupId, content);
      _composer.clear();
      ref.invalidate(groupMessagesProvider(widget.groupId));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bericht niet verstuurd.')),
        );
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _leave() async {
    final failure = await ref.read(groupsRepositoryProvider).leave(widget.groupId);
    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure)));
      return;
    }
    ref.invalidate(groupsProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(groupDetailProvider(widget.groupId));
    final messages = ref.watch(groupMessagesProvider(widget.groupId));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(detail.value?.group.name ?? 'Groep'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'leave') _leave();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'leave', child: Text('Groep verlaten')),
            ],
          ),
        ],
      ),
      body: detail.when(
        loading: () => const AppLoader(),
        error: (error, _) => AppEmptyState(
          icon: Icons.wifi_off_outlined,
          title: 'Groep niet geladen',
          description: '$error',
        ),
        data: (data) => Column(
          children: [
            _GroupHeader(detail: data),
            const RuleLine(),
            Expanded(
              child: messages.when(
                loading: () => const AppLoader(),
                error: (_, __) => const AppEmptyState(
                  icon: Icons.forum_outlined,
                  title: 'Berichten niet geladen',
                  description: 'Controleer je verbinding.',
                ),
                data: (list) => list.isEmpty
                    ? const AppEmptyState(
                        icon: Icons.forum_outlined,
                        title: 'Nog geen berichten',
                        description: 'Schrijf het eerste bericht van deze groep.',
                      )
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        itemCount: list.length,
                        itemBuilder: (context, index) =>
                            _MessageBubble(message: list[index]),
                      ),
              ),
            ),
            const RuleLine(),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _composer,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Schrijf een bericht…',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 44,
                      width: 44,
                      child: FilledButton(
                        onPressed: _sending ? null : _send,
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          ),
                        ),
                        child: const Icon(Icons.send, size: 17),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.detail});

  final GroupDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final group = detail.group;

    return Container(
      width: double.infinity,
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (group.description.isNotEmpty) ...[
            Text(group.description, style: AppTheme.bodyMuted),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SiteBadge.neutral(
                '${group.memberCount} '
                '${group.memberCount == 1 ? 'lid' : 'leden'}',
              ),
              if (group.assignment != null)
                SiteBadge.teal(
                  'Deze week: ${group.assignment}',
                  icon: Icons.assignment_outlined,
                ),
              if (group.inviteCode != null)
                // Tapping copies it — an invite code is meant to be passed on.
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: group.inviteCode!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Uitnodigingscode gekopieerd')),
                    );
                  },
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  child: SiteBadge(
                    'Code ${group.inviteCode}',
                    icon: Icons.copy,
                    foreground: AppTheme.inkMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: detail.members.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final member = detail.members[index];
                return Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: CircleAvatar(
                    backgroundColor: AppTheme.teal.withValues(alpha: 0.12),
                    child: Text(
                      member.name.isEmpty ? '?' : member.name[0].toUpperCase(),
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.teal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  label: Text(member.isSelf ? 'Jij' : member.name),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final GroupMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPrayer = message.type == 'gebedsverzoek';
    final isAnnouncement = message.type == 'aankondiging';

    return Align(
      alignment: message.isSelf ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        decoration: BoxDecoration(
          color: message.isSelf ? AppTheme.teal : scheme.surface,
          border: message.isSelf ? null : Border.all(color: scheme.outline),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!message.isSelf)
              Text(
                message.authorName,
                style: AppTheme.caption.copyWith(
                  color: AppTheme.teal,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (isPrayer || isAnnouncement)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  isPrayer ? 'GEBEDSVERZOEK' : 'AANKONDIGING',
                  style: AppTheme.overline.copyWith(
                    color: message.isSelf
                        ? Colors.white.withValues(alpha: 0.85)
                        : AppTheme.flame,
                  ),
                ),
              ),
            Text(
              message.content,
              style: TextStyle(
                fontFamily: AppTheme.sansFontName,
                fontSize: 14,
                height: 1.5,
                color: message.isSelf ? Colors.white : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
