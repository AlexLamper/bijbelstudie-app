import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../feedback/present/feedback_sheet.dart';
import '../../referral/data/referral_repository.dart';
import '../data/friend_models.dart';
import '../data/friends_repository.dart';
import 'friend_post_card.dart';
import 'friend_rows.dart';
import 'friends_providers.dart';

/// `/vriendenkring` - Feed | Vrienden | Verzoeken, the same three sections the
/// website's `/vriendenkring` has, so the kring is in the same place on both.
///
/// Reached from the Start tab's header button and from "Alles bekijken" under
/// "Bij je vrienden"; it has no tab of its own.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Opening the screen is what "gezien" means, so the badge on Start clears
    // here rather than on any tap that happens to land in the feed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(friendsFeedProvider.notifier).markSeen();
    });
  }

  Future<void> _refresh() async {
    await ref.read(friendsFeedProvider.notifier).refresh();
    ref.invalidate(friendsKringProvider);
    ref.invalidate(friendsRequestsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(friendsFeedProvider);
    final kring = ref.watch(friendsKringProvider).value;
    final requests = ref.watch(friendsRequestsProvider).value;
    final pending = requests?.incoming.length ?? kring?.pendingIncoming ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vriendenkring'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppSegmentedControl(
                labels: [
                  'Feed',
                  'Vrienden',
                  pending > 0 ? 'Verzoeken ($pending)' : 'Verzoeken',
                ],
                selectedIndex: _tab,
                onChanged: (index) => setState(() => _tab = index),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppTheme.teal,
        onRefresh: _refresh,
        child: switch (_tab) {
          1 => _KringTab(kring: kring, loading: ref.watch(friendsKringProvider).isLoading),
          2 => _RequestsTab(requests: requests, loading: ref.watch(friendsRequestsProvider).isLoading),
          _ => _FeedTab(
            feed: feedAsync.value,
            loading: feedAsync.isLoading,
            hasKring: (kring?.friends.length ?? 0) > 0,
          ),
        },
      ),
    );
  }
}

/// The scroll view every tab uses, so pull-to-refresh works on a short tab too.
class _TabList extends StatelessWidget {
  const _TabList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );
  }
}

class _FeedTab extends StatelessWidget {
  const _FeedTab({required this.feed, required this.loading, required this.hasKring});

  final FriendsFeed? feed;
  final bool loading;
  final bool hasKring;

  @override
  Widget build(BuildContext context) {
    if (feed == null && loading) return const Center(child: AppLoader());
    final posts = feed?.posts ?? const <FriendPost>[];
    return _TabList(
      children: [
        if (posts.isNotEmpty)
          FriendPostList(posts: posts)
        else if (hasKring || (feed?.hasFriends ?? false))
          AppCard(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Nog niets gedeeld in je kring. Deel zelf een tekst of een mijlpaal '
              'om te beginnen.',
              textAlign: TextAlign.center,
              style: AppTheme.caption.copyWith(fontSize: 13.5),
            ),
          )
        else
          const InviteFriendsCard(),
      ],
    );
  }
}

class _KringTab extends StatelessWidget {
  const _KringTab({required this.kring, required this.loading});

  final FriendsKring? kring;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (kring == null && loading) return const Center(child: AppLoader());
    final friends = kring?.friends ?? const <FriendSummary>[];
    if (friends.isEmpty) {
      return const _TabList(children: [InviteFriendsCard()]);
    }
    return _TabList(
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < friends.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: AppTheme.rule),
                FriendRow(friend: friends[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const InviteFriendsCard(),
      ],
    );
  }
}

class _RequestsTab extends StatelessWidget {
  const _RequestsTab({required this.requests, required this.loading});

  final FriendRequestsResponse? requests;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (requests == null && loading) return const Center(child: AppLoader());
    final value = requests ?? FriendRequestsResponse.empty;
    if (value.isEmpty) {
      return _TabList(
        children: [
          AppCard(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Geen open verzoeken.',
              textAlign: TextAlign.center,
              style: AppTheme.caption.copyWith(fontSize: 13.5),
            ),
          ),
        ],
      );
    }

    Widget group(List<FriendRequestView> rows, {required bool incoming}) => AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: AppTheme.rule),
            FriendRequestRow(request: rows[i], incoming: incoming),
          ],
        ],
      ),
    );

    return _TabList(
      children: [
        if (value.incoming.isNotEmpty) group(value.incoming, incoming: true),
        if (value.outgoing.isNotEmpty) ...[
          if (value.incoming.isNotEmpty) const SizedBox(height: 20),
          const SectionHeader(title: 'Verstuurd'),
          const SizedBox(height: 10),
          group(value.outgoing, incoming: false),
        ],
      ],
    );
  }
}

/// The feed itself: [FriendPostCard]s wired to [friendsFeedProvider], so the
/// Start tab's two newest posts and the whole Vriendenkring list behave the
/// same under a heart or a reaction.
class FriendPostList extends ConsumerWidget {
  const FriendPostList({super.key, required this.posts, this.spacing = 12});

  final List<FriendPost> posts;
  final double spacing;

  Future<void> _comment(BuildContext context, WidgetRef ref, FriendPost post) async {
    final text = await showFriendCommentSheet(context);
    if (text == null || !context.mounted) return;
    final ok = await ref.read(friendsRepositoryProvider).addComment(post.id, text);
    if (!context.mounted) return;
    if (ok) {
      await ref.read(friendsFeedProvider.notifier).refresh();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reactie kon niet worden geplaatst')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < posts.length; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          FriendPostCard(
            post: posts[i],
            onLike: () => ref.read(friendsFeedProvider.notifier).toggleLike(posts[i].id),
            onComment: () => _comment(context, ref, posts[i]),
            onMore: () => showFriendPostMoreSheet(
              context,
              post: posts[i],
              onReport: () => showFeedbackSheet(context, ref),
            ),
          ),
        ],
      ],
    );
  }
}

/// "Lees samen met vrienden" - the card a reader without a kring sees, on
/// Start and on Vriendenkring both.
///
/// Two ways in, neither of which needs the address book yet: share the invite
/// link, or type the code a friend gave you. The link is the referral link
/// that already exists, so one code does both jobs and the reader never has to
/// know which is which.
class InviteFriendsCard extends ConsumerStatefulWidget {
  const InviteFriendsCard({super.key});

  @override
  ConsumerState<InviteFriendsCard> createState() => _InviteFriendsCardState();
}

class _InviteFriendsCardState extends ConsumerState<InviteFriendsCard> {
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() => _busy = true);
    final result = await ref.read(friendsRepositoryProvider).invite(code: code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = result.message;
    });
    if (result.ok) {
      _codeController.clear();
      ref.invalidate(friendsRequestsProvider);
      ref.invalidate(friendsKringProvider);
      await ref.read(friendsFeedProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final overview = ref.watch(referralOverviewProvider).value;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconChip(icon: Icons.people_outline, size: 40, iconSize: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lees samen met vrienden',
                      style: AppTheme.bodyStrong.copyWith(
                        fontSize: 15,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Zie waar zij lezen en moedig elkaar aan.',
                      style: AppTheme.caption.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SiteButton(
            label: 'Vrienden uitnodigen',
            icon: Icons.ios_share,
            onPressed: overview == null ? null : () => Share.share(overview.shareText),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'Code van een vriend'),
                  onSubmitted: (_) => _join(),
                ),
              ),
              const SizedBox(width: 8),
              SiteButton(
                label: 'Toevoegen',
                expand: false,
                height: 44,
                loading: _busy,
                onPressed: _join,
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(_message!, style: AppTheme.caption.copyWith(fontSize: 12.5)),
          ],
        ],
      ),
    );
  }
}
