import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../referral/data/referral_repository.dart';
import '../data/friend_models.dart';
import '../data/friends_repository.dart';
import 'contacts/contact_discovery_providers.dart';
import 'contacts/contacts_entry_card.dart';
import 'friend_block_action.dart';
import 'friend_comments_sheet.dart';
import 'friend_post_card.dart';
import 'friend_profile_screen.dart';
import 'friend_report_sheet.dart';
import 'friend_rows.dart';
import 'friend_suggestions_section.dart';
import 'friends_error_card.dart';
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
    ref.invalidate(friendsSettingsProvider);
    ref.invalidate(friendSuggestionsProvider);
  }

  /// A retry has to wait for the answer, otherwise the button stops spinning
  /// before anything happened. The failure is already on screen, so swallowing
  /// it here only keeps it from becoming an unhandled future.
  Future<void> _retryKring() async {
    ref.invalidate(friendsKringProvider);
    try {
      await ref.read(friendsKringProvider.future);
    } catch (_) {}
  }

  Future<void> _retryRequests() async {
    ref.invalidate(friendsRequestsProvider);
    try {
      await ref.read(friendsRequestsProvider.future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(friendsFeedProvider);
    final kringAsync = ref.watch(friendsKringProvider);
    final requestsAsync = ref.watch(friendsRequestsProvider);
    final kring = kringAsync.value;
    final requests = requestsAsync.value;
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
          1 => _KringTab(async: kringAsync, onRetry: _retryKring),
          2 => _RequestsTab(async: requestsAsync, onRetry: _retryRequests),
          _ => _FeedTab(
            async: feedAsync,
            hasKring: (kring?.friends.length ?? 0) > 0,
            onRetry: () => ref.read(friendsFeedProvider.notifier).refresh(),
            onLoadMore: () => ref.read(friendsFeedProvider.notifier).loadMore(),
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
  const _FeedTab({
    required this.async,
    required this.hasKring,
    required this.onRetry,
    required this.onLoadMore,
  });

  final AsyncValue<FriendsFeed> async;
  final bool hasKring;
  final Future<void> Function() onRetry;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    final feed = async.value;
    // The error is checked before the loading flag on purpose: an `AsyncError`
    // still reports `isLoading`, and a failure that renders as a spinner is a
    // screen that never finishes.
    //
    // A failed request is also not an empty kring: the invitation card would
    // tell the reader they have no friends, which we do not know. A quiet
    // failure is the exception - it falls through to the ordinary states.
    final failed = feed == null && async.hasError;
    if (failed && !FriendsErrorCard.isQuiet(async.error)) {
      return _TabList(
        children: [FriendsErrorCard(failure: async.error!, onRetry: onRetry)],
      );
    }
    if (feed == null && !failed && async.isLoading) {
      return const Center(child: AppLoader());
    }
    final posts = feed?.posts ?? const <FriendPost>[];
    return _TabList(
      children: [
        if (posts.isNotEmpty) ...[
          FriendPostList(posts: posts),
          if (feed != null && feed.hasMore) ...[
            const SizedBox(height: 14),
            _LoadMoreButton(feed: feed, onLoadMore: onLoadMore),
          ],
        ] else if (hasKring || (feed?.hasFriends ?? false))
          AppCard(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Nog niets te zien in je kring. Zodra iemand een studie afrondt of '
              'een tekst bewaart, staat het hier.',
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

/// "Meer laden" under the feed: one more `before=` page of 20.
///
/// A button rather than silent infinite scroll, because the server sends no
/// total - the reader is told there may be more, not promised a number - and
/// because a page that does not arrive can then say so in place.
class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.feed, required this.onLoadMore});

  final FriendsFeed feed;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SiteOutlineButton(
          label: feed.loadingMore
              ? 'Laden...'
              : feed.loadMoreFailed
              ? 'Opnieuw proberen'
              : 'Meer laden',
          icon: feed.loadMoreFailed ? Icons.refresh : null,
          height: 44,
          onPressed: feed.loadingMore ? null : onLoadMore,
        ),
        if (feed.loadMoreFailed) ...[
          const SizedBox(height: 8),
          Text(
            'Die oudere berichten kwamen niet binnen.',
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(fontSize: 12.5),
          ),
        ],
      ],
    );
  }
}

class _KringTab extends StatelessWidget {
  const _KringTab({required this.async, required this.onRetry});

  final AsyncValue<FriendsKring> async;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final kring = async.value;
    final failed = kring == null && async.hasError;
    if (failed && !FriendsErrorCard.isQuiet(async.error)) {
      return _TabList(
        children: [FriendsErrorCard(failure: async.error!, onRetry: onRetry)],
      );
    }
    if (kring == null && !failed && async.isLoading) {
      return const Center(child: AppLoader());
    }
    final friends = kring?.friends ?? const <FriendSummary>[];
    if (friends.isEmpty) {
      return const _TabList(
        children: [
          _ContactsEntry(),
          InviteFriendsCard(),
          // Structurally empty for a reader with no friends - a friend of a
          // friend needs a friend - so it draws nothing here and says nothing
          // about why.
          FriendSuggestionsSection(),
          _BlockedSection(),
        ],
      );
    }
    return _TabList(
      children: [
        const _ContactsEntry(),
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
        const FriendSuggestionsSection(),
        const _BlockedSection(),
      ],
    );
  }
}

/// [ContactsEntryCard] with the gap under it.
///
/// The card itself renders nothing unless both the `CONTACT_MATCHING`
/// dart-define and the server's pepper are on, so it needs no guard - but the
/// spacing under it does, otherwise a feature that is off leaves a hole at the
/// top of the tab.
class _ContactsEntry extends ConsumerWidget {
  const _ContactsEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(contactDiscoveryOfferedProvider).value != true) {
      return const SizedBox.shrink();
    }
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: ContactsEntryCard(),
    );
  }
}

/// "Geblokkeerd", under the kring, and only when there is something in it.
///
/// The list rides along on `GET /friends/settings`. It is silent on a failure
/// on purpose: a reader who blocked nobody - which is nearly everybody -
/// should not be told that a list they never asked for did not load, and the
/// kring above it already reports the state of the connection.
class _BlockedSection extends ConsumerWidget {
  const _BlockedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(friendsSettingsProvider).value?.blocked ?? const <BlockedUser>[];
    if (blocked.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const SectionHeader(title: 'Geblokkeerd'),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Jullie zien elkaars berichten en verzoeken niet, aan beide kanten.',
            style: AppTheme.caption.copyWith(fontSize: 12.5),
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < blocked.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: AppTheme.rule),
                BlockedUserRow(user: blocked[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RequestsTab extends StatelessWidget {
  const _RequestsTab({required this.async, required this.onRetry});

  final AsyncValue<FriendRequestsResponse> async;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final requests = async.value;
    final failed = requests == null && async.hasError;
    if (failed && !FriendsErrorCard.isQuiet(async.error)) {
      return _TabList(
        children: [FriendsErrorCard(failure: async.error!, onRetry: onRetry)],
      );
    }
    if (requests == null && !failed && async.isLoading) {
      return const Center(child: AppLoader());
    }
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < posts.length; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          FriendPostCard(
            post: posts[i],
            onAuthorTap: () => openFriendProfile(context, posts[i].authorId),
            onLike: () => ref.read(friendsFeedProvider.notifier).toggleLike(posts[i].id),
            onComment: () => showFriendCommentsSheet(context, post: posts[i]),
            onMore: () => showFriendPostMoreSheet(
              context,
              post: posts[i],
              // The real melding, with the post it is about: the generic
              // feedback sheet this used to open sends no post id at all.
              onReport: () => showFriendReportSheet(
                context,
                postId: posts[i].id,
                authorName: posts[i].authorName,
              ),
              onBlock: () => confirmAndBlockFriend(
                context,
                ref,
                userId: posts[i].authorId,
                name: posts[i].authorName,
              ),
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
