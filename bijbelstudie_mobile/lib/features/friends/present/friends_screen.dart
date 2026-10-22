import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../referral/data/referral_repository.dart';
import '../data/friend_models.dart';
import '../data/friends_repository.dart';
import 'contacts/connect_contacts_button.dart';
import 'contacts/contact_discovery_providers.dart';
import 'friend_block_action.dart';
import 'friend_comments_sheet.dart';
import 'friend_post_card.dart';
import 'friend_profile_screen.dart';
import 'friend_report_sheet.dart';
import 'friend_rows.dart';
import 'friend_suggestions_section.dart';
import 'friends_entry_providers.dart';
import 'friends_error_card.dart';
import 'friends_providers.dart';

/// `/vriendenkring` - one scrolling page, modelled on YouVersion: "Mensen die
/// je misschien kent" at the top with "Verbind Contacten" in it, then any
/// verzoeken waiting for an answer, then the feed. The kring itself (and the
/// blocked list) is the second tab, "Je vrienden".
///
/// While the contacts are not connected and there is no kring yet
/// ([friendsContactsGateProvider]), the page is only the invitation to connect
/// them, with the code-or-link route under it for whoever would rather not.
///
/// Reached from the Start tab's header button and from "Alles bekijken" under
/// "Bij je vrienden"; it has no tab of its own.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  AppLifecycleListener? _lifecycle;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Opening the screen is what "gezien" means, so the badge and the dot on
    // Start clear here rather than on any tap that happens to land in the feed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(friendsFeedProvider.notifier).markSeen();
      final people = ref.read(friendSuggestionsProvider).value?.suggestions ?? const [];
      ref
          .read(friendsEntrySeenProvider.notifier)
          .markOpened(suggestionIds: people.map((person) => person.userId));
    });
    // Access granted or taken away in the Settings app shows up on return.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(contactsConnectedProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await ref.read(friendsFeedProvider.notifier).refresh();
    ref.invalidate(friendsKringProvider);
    ref.invalidate(friendsRequestsProvider);
    ref.invalidate(friendsSettingsProvider);
    ref.invalidate(friendSuggestionsProvider);
    ref.invalidate(contactsConnectedProvider);
  }

  /// "Verbind Contacten": straight to the OS prompt, with the disclosure
  /// printed on the card the reader just tapped.
  ///
  /// There is no page in between any more. The ordering Play asks for still
  /// holds, because the disclosure is *on* that card and the controller still
  /// refuses to touch the address book until this call has written down that
  /// it was accepted.
  Future<void> _connectContacts() async {
    await startContactsMatch(context, ref);
    if (!mounted) return;
    ref.invalidate(contactsConnectedProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Suggestions that arrive while the screen is open count as seen.
    ref.listen(friendSuggestionsProvider, (_, next) {
      final people = next.value?.suggestions;
      if (people == null || people.isEmpty) return;
      ref
          .read(friendsEntrySeenProvider.notifier)
          .markSuggestionsSeen(people.map((person) => person.userId));
    });
    // A finished match can change who is suggested and who is in the kring.
    ref.listen(contactDiscoveryProvider.select((state) => state.stage), (previous, next) {
      if (next != ContactDiscoveryStage.matched || previous == next) return;
      ref.invalidate(friendSuggestionsProvider);
      ref.invalidate(friendsKringProvider);
      ref.invalidate(friendsRequestsProvider);
    });

    final gated = ref.watch(friendsContactsGateProvider);
    final requestsAsync = ref.watch(friendsRequestsProvider);

    // Without contacts and without a kring there is nothing for a second tab to
    // show yet, so the page is only the invitation.
    final tab = gated ? 0 : _tab;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vriendenkring'),
        bottom: gated
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AppSegmentedControl(
                      labels: const ['Overzicht', 'Je vrienden'],
                      selectedIndex: tab,
                      onChanged: (index) => setState(() => _tab = index),
                    ),
                  ),
                ),
              ),
      ),
      body: RefreshIndicator(
        color: AppTheme.teal,
        onRefresh: _refresh,
        child: tab == 1
            ? const _KringTab()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _PeopleYouMayKnow(onConnect: _connectContacts),
                  _IncomingRequests(async: requestsAsync),
                  if (gated) ...[
                    Text(
                      'Liever zonder je contacten? Nodig iemand uit met je link of code.',
                      style: AppTheme.caption.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    const InviteFriendsCard(),
                  ] else ...[
                    const SectionHeader(title: 'Feed'),
                    const SizedBox(height: 12),
                    const _Feed(),
                  ],
                ],
              ),
      ),
    );
  }
}

/// "Mensen die je misschien kent", the top of the page.
///
/// With contact matching on and the contacts not connected, "Verbind
/// Contacten" sits right under the title, so it is in view the moment the
/// screen opens. Once they are connected the rows take its place, with a quiet
/// way to look through the address book again.
class _PeopleYouMayKnow extends ConsumerWidget {
  const _PeopleYouMayKnow({required this.onConnect});

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final offered = ref.watch(contactDiscoveryOfferedProvider).value == true;
    final connected = ref.watch(contactsConnectedProvider).value;

    // Contact matching off (the build or the server), or not known yet: the
    // friends-of-friends list as it always was, which draws nothing when empty.
    if (!offered || connected == null) {
      final people = ref.watch(friendSuggestionsProvider).value?.suggestions;
      if (people == null || people.isEmpty) return const SizedBox.shrink();
      return const Padding(
        padding: EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Mensen die je misschien kent',
              description: 'Vrienden van de mensen in je kring.',
            ),
            FriendSuggestionsSection(showHeader: false),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Mensen die je misschien kent',
            // Short on purpose now that the card under it carries the
            // disclosure: two paragraphs of explaining read as a warning.
            description: connected
                ? 'Uit je contacten en uit de kring van je vrienden.'
                : 'Zie wie je al kent. Je kiest zelf wie je uitnodigt.',
          ),
          const SizedBox(height: 12),
          if (!connected) ConnectContactsButton(onPressed: onConnect),
          const FriendSuggestionsSection(showHeader: false),
          if (connected)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Contacten opnieuw doorzoeken'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Verzoeken waiting for an answer. Nothing at all when there are none, and
/// nothing on a failure either: the feed below already reports the connection.
class _IncomingRequests extends StatelessWidget {
  const _IncomingRequests({required this.async});

  final AsyncValue<FriendRequestsResponse> async;

  @override
  Widget build(BuildContext context) {
    final incoming = async.value?.incoming ?? const <FriendRequestView>[];
    if (incoming.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: 'Verzoeken (${incoming.length})'),
          const SizedBox(height: 10),
          _RequestGroup(rows: incoming, incoming: true),
        ],
      ),
    );
  }
}

class _RequestGroup extends StatelessWidget {
  const _RequestGroup({required this.rows, required this.incoming});

  final List<FriendRequestView> rows;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    return AppCard(
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
  }
}

/// The "Je vrienden" tab: the kring, the verzoeken sent and the blocked list.
class _KringTab extends ConsumerWidget {
  const _KringTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(friendsKringProvider);
    final kring = async.value;
    final failed = kring == null && async.hasError;
    final outgoing =
        ref.watch(friendsRequestsProvider).value?.outgoing ?? const <FriendRequestView>[];
    final friends = kring?.friends ?? const <FriendSummary>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (failed && !FriendsErrorCard.isQuiet(async.error))
          FriendsErrorCard(
            failure: async.error!,
            onRetry: () async {
              ref.invalidate(friendsKringProvider);
              try {
                await ref.read(friendsKringProvider.future);
              } catch (_) {}
            },
          )
        else if (kring == null && !failed && async.isLoading)
          const Padding(padding: EdgeInsets.all(32), child: AppLoader())
        else if (friends.isNotEmpty)
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
        if (outgoing.isNotEmpty) ...[
          const SizedBox(height: 24),
          const SectionHeader(title: 'Verstuurd'),
          const SizedBox(height: 10),
          _RequestGroup(rows: outgoing, incoming: false),
        ],
        const SizedBox(height: 24),
        const InviteFriendsCard(),
        const _BlockedSection(),
      ],
    );
  }
}

/// The feed: the posts, or what to say when there are none.
class _Feed extends ConsumerWidget {
  const _Feed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(friendsFeedProvider);
    final hasKring = (ref.watch(friendsKringProvider).value?.friends.length ?? 0) > 0;
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
      return FriendsErrorCard(
        failure: async.error!,
        onRetry: () => ref.read(friendsFeedProvider.notifier).refresh(),
      );
    }
    if (feed == null && !failed && async.isLoading) {
      return const Padding(padding: EdgeInsets.all(32), child: AppLoader());
    }
    final posts = feed?.posts ?? const <FriendPost>[];
    if (posts.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FriendPostList(posts: posts),
          if (feed != null && feed.hasMore) ...[
            const SizedBox(height: 14),
            _LoadMoreButton(
              feed: feed,
              onLoadMore: () => ref.read(friendsFeedProvider.notifier).loadMore(),
            ),
          ],
        ],
      );
    }
    if (hasKring || (feed?.hasFriends ?? false)) {
      return AppCard(
        padding: const EdgeInsets.all(20),
        child: Text(
          'Nog niets te zien in je kring. Zodra iemand een studie afrondt of '
          'een tekst bewaart, staat het hier.',
          textAlign: TextAlign.center,
          style: AppTheme.caption.copyWith(fontSize: 13.5),
        ),
      );
    }
    return const InviteFriendsCard();
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
