import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/notifications/permission_moment.dart'
    show maybeAskAfterFriendAction;
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../levensboom/present/studio/levensboom_studio_screen.dart' show publicProfileUrl;
import '../data/friend_models.dart';
import '../data/friends_failure.dart';
import '../data/friends_repository.dart';
import 'friend_block_action.dart';
import 'friend_post_card.dart' show FriendAvatar;
import 'friend_tap_target.dart';
import 'friends_providers.dart';

// ---------------------------------------------------------------- the copy
//
// The Dutch of this screen, kept in one place for the same reason
// `components/friends/profileCopy.ts` exists on the website: these lines are
// the product's promise about who sees what, they are asserted in
// `test/vriendenkring_profile_test.dart`, and the two clients have to agree
// word for word. The strings below are that file's, reused.
//
// House rule, and the one that matters most here: nothing may tell a reader
// *why* a profile is missing. `GET /friends/:userId` answers the same 404 for
// a block in either direction, a deleted account, a malformed id and the
// reader's own id, and no copy on this screen may let a visitor tell those
// apart.

/// The meta line when there is no plan day to show. Same as a kring row.
const String kProfileReadsAlong = 'Leest mee';
const String kProfileBefriend = 'Vrienden worden';
const String kProfileBefriending = 'Versturen...';
const String kProfileRequestSent =
    'Verzoek verstuurd. Zodra het geaccepteerd is, zien jullie elkaars voortgang.';
const String kProfileRemove = 'Uit je kring halen';
const String kProfileBlock = 'Blokkeren';
const String kProfileRemoveBody =
    'Jullie zien elkaars berichten niet meer. Je kunt elkaar later opnieuw uitnodigen.';
const String kProfileRemoveAction = 'Verwijderen';
const String kProfileMutualsHint = 'Vrienden die jullie delen.';

/// Any failure that is not a 404. The feature degrades quietly everywhere.
const String kProfileUnavailable = 'Dit profiel kan nu niet geladen worden.';

/// The 404, which is deliberately one sentence for four different causes.
/// It names none of them, and it must stay that way.
const String kProfileMissingTitle = 'Dit profiel is niet beschikbaar';
const String kProfileMissingBody = 'Je kunt deze pagina nu niet bekijken.';

const List<String> _months = [
  'januari', 'februari', 'maart', 'april', 'mei', 'juni',
  'juli', 'augustus', 'september', 'oktober', 'november', 'december',
];

/// "12 vrienden". A count is public; the list is not.
String friendCountLabel(int count) => count == 1 ? '1 vriend' : '$count vrienden';

/// "Vrienden sinds maart 2026", or null when there is no usable date.
String? friendsSinceLabel(DateTime? when) {
  if (when == null) return null;
  return 'Vrienden sinds ${_months[when.month - 1]} ${when.year}';
}

/// The tail under a capped mutuals list - the server names twelve and
/// `mutualCount` carries the real total, so the rest get a line.
String? moreMutualsLabel(int hidden) {
  if (hidden < 1) return null;
  return hidden == 1 ? 'En nog 1 ander.' : 'En nog $hidden anderen.';
}

/// "3 gezamenlijke vrienden" for a profile, whose count lives on the view and
/// not on the person.
///
/// Routed through [FriendSummary.mutualLabel] rather than formatting a count
/// here, so "0 gezamenlijke vrienden" stays unsayable on this screen too.
String? profileMutualLabel(FriendProfileView view) => FriendSummary(
  userId: view.user.userId,
  name: view.user.name,
  mutualCount: view.mutualCount,
).mutualLabel;

/// The heading over their own kring, which only a friend is shown.
String theirKringTitle(String name) => 'Vrienden van $name';

/// Their kring is empty, which is only ever said when the reader IS a friend
/// and so may see the list. See [theirKringState].
String noOtherFriendsLabel(String name) => 'Buiten jou heeft $name nog geen vrienden.';

/// The way on to `/gebruiker/<id>`, shown only when that page exists.
String publicTreeLabel(String name) => 'Bekijk de boom van $name';

/// The confirm title, the same sentence a kring row asks.
String removeConfirmTitle(String name) => '$name uit je kring halen?';

// ------------------------------------------------- the null / empty verdict

/// What a profile should do with [FriendProfileView.friends].
enum FriendKringState {
  /// `null` - "niet voor jou te zien". No section at all.
  hidden,

  /// `[]` - a friend whose only friend is the reader. Gets its own line.
  empty,

  /// People to name.
  list,
}

/// The one place the `null` / `[]` distinction is decided, so no renderer has
/// to get it right twice (`theirKringState` in `lib/friends/client.ts`):
///
/// - `null` is "not yours to see" - the reader is not a friend - and the whole
///   section is [FriendKringState.hidden]. An empty-list state there would
///   read as "they have no friends", which is a claim the server never made
///   and the UI must not make either;
/// - `[]` is a friend whose only friend is the reader (their kring comes back
///   with the reader filtered out), which is true, is theirs to know, and gets
///   the [FriendKringState.empty] line;
/// - anything else is the [FriendKringState.list].
FriendKringState theirKringState(List<FriendSummary>? friends) {
  if (friends == null) return FriendKringState.hidden;
  return friends.isEmpty ? FriendKringState.empty : FriendKringState.list;
}

// ------------------------------------------------------------- the screen

/// `/vriendenkring/:userId` - one person, from `GET /api/v1/friends/:userId`.
///
/// The better link target than the public tree page: that one is opt-in and
/// 404s for everyone who did not switch it on, while this answers for anyone
/// the reader is allowed to look at. It links on to the tree only when
/// [FriendSummary.publicProfile] says that page is there.
///
/// What is shown is graded by the server, not here: a non-friend's `streak`,
/// `planDay` and `friendsSince` come back zeroed, so those lines are left off
/// rather than printed as zeros, and `friends` is null rather than empty.
class FriendProfileScreen extends ConsumerStatefulWidget {
  const FriendProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends ConsumerState<FriendProfileScreen> {
  bool _busy = false;
  bool _invited = false;

  Future<void> _reload() async {
    ref.invalidate(friendProfileProvider(widget.userId));
    try {
      await ref.read(friendProfileProvider(widget.userId).future);
    } catch (_) {}
  }

  Future<void> _invite() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await ref
        .read(friendsRepositoryProvider)
        .invite(userId: widget.userId, source: 'link');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _invited = result.ok;
    });
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
      return;
    }
    ref.invalidate(friendsRequestsProvider);
    ref.invalidate(friendSuggestionsProvider);
    // Inviting someone who already asked makes you friends on the spot, so the
    // profile is re-read rather than assumed to be pending.
    await _reload();
    if (!mounted) return;
    // Sending a verzoek is the other half of the earned moment for the social
    // notifications (see `permission_moment.dart`). Once, after the reload, so
    // the sheet does not open over a screen that is still settling.
    await maybeAskAfterFriendAction(context, ref);
  }

  Future<void> _remove(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(removeConfirmTitle(name)),
        content: const Text(kProfileRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(kProfileRemoveAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final ok = await ref.read(friendsRepositoryProvider).removeFriend(widget.userId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dat lukte niet. Probeer het zo nog eens.')),
      );
      return;
    }
    ref.invalidate(friendsKringProvider);
    ref.invalidate(friendsFeedProvider);
    await _reload();
  }

  /// Harder than removing, and said so before it happens. After a block the
  /// endpoint answers 404 for this person, which is the right landing: the
  /// same page a stranger gets, so nothing leaks either way.
  Future<void> _block(String name) async {
    setState(() => _busy = true);
    final ok = await confirmAndBlockFriend(
      context,
      ref,
      userId: widget.userId,
      name: name,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) await _reload();
  }

  Future<void> _openTree() async {
    final uri = Uri.tryParse(publicProfileUrl(widget.userId));
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final async = ref.watch(friendProfileProvider(widget.userId));
    final view = async.value;

    // The error is read before the loading flag: an `AsyncError` still reports
    // `isLoading`, and a failure that renders as a spinner never finishes.
    Widget body;
    if (view == null && async.hasError) {
      final failure = async.error;
      final missing =
          failure is FriendsException && failure.kind == FriendsFailure.notFound;
      body = _ProfileNotice(
        title: missing ? kProfileMissingTitle : 'Even niet beschikbaar',
        body: missing ? kProfileMissingBody : kProfileUnavailable,
        onRetry: missing ? null : _reload,
      );
    } else if (view == null) {
      body = const Center(child: AppLoader());
    } else {
      body = _ProfileBody(
        view: view,
        busy: _busy,
        invited: _invited,
        onInvite: _invite,
        onRemove: _remove,
        onBlock: _block,
        onOpenTree: _openTree,
      );
    }

    final title = view?.user.name.trim() ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(title.isEmpty ? 'Vriendenkring' : title)),
      body: RefreshIndicator(
        color: AppTheme.teal,
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [body],
        ),
      ),
    );
  }
}

/// A 404 or a bad moment, in a card. The 404's wording says nothing about the
/// cause, because the server deliberately does not either.
class _ProfileNotice extends StatelessWidget {
  const _ProfileNotice({required this.title, required this.body, this.onRetry});

  final String title;
  final String body;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTheme.bodyStrong.copyWith(fontSize: 15, color: scheme.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(fontSize: 13.5),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            SiteOutlineButton(
              label: 'Opnieuw proberen',
              icon: Icons.refresh,
              height: 44,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({
    required this.view,
    required this.busy,
    required this.invited,
    required this.onInvite,
    required this.onRemove,
    required this.onBlock,
    required this.onOpenTree,
  });

  final FriendProfileView view;
  final bool busy;
  final bool invited;
  final Future<void> Function() onInvite;
  final Future<void> Function(String name) onRemove;
  final Future<void> Function(String name) onBlock;
  final Future<void> Function() onOpenTree;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final person = view.user;
    final name = person.name.trim().isEmpty ? 'Een lezer' : person.name.trim();
    final since = view.isFriend ? friendsSinceLabel(person.friendsSince) : null;
    final mutual = profileMutualLabel(view);
    final hiddenMutuals = moreMutualsLabel(view.hiddenMutualCount);
    final kringState = theirKringState(view.visibleFriends);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FriendAvatar(name: person.name, image: person.image, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          style: AppTheme.bodyStrong.copyWith(
                            fontSize: 17,
                            color: scheme.onSurface,
                          ),
                        ),
                        // A non-friend's numbers are zeroed server-side, so the
                        // line is left off rather than printed as zeros.
                        if (view.isFriend) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  person.planLabel ?? kProfileReadsAlong,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.caption.copyWith(fontSize: 12.5),
                                ),
                              ),
                              if (person.streak > 0) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.local_fire_department,
                                  size: 13,
                                  color: AppTheme.flame,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${person.streak}',
                                  style: AppTheme.caption.copyWith(fontSize: 12.5),
                                ),
                              ],
                            ],
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          since == null
                              ? friendCountLabel(view.friendCount)
                              : '${friendCountLabel(view.friendCount)}  ·  $since',
                          style: AppTheme.caption.copyWith(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  if (view.isFriend)
                    PopupMenuButton<String>(
                      enabled: !busy,
                      icon: Icon(Icons.more_horiz, size: 20, color: AppTheme.inkMuted),
                      tooltip: 'Meer',
                      onSelected: (value) {
                        if (value == 'remove') onRemove(name);
                        if (value == 'block') onBlock(name);
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'remove',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.person_remove_outlined, size: 20),
                            title: Text(kProfileRemove),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'block',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.block_outlined, size: 20),
                            title: Text(kProfileBlock),
                          ),
                        ),
                      ],
                    )
                  else if (!invited)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SiteButton(
                        label: busy ? kProfileBefriending : kProfileBefriend,
                        expand: false,
                        height: 40,
                        onPressed: busy ? null : onInvite,
                      ),
                    ),
                ],
              ),
              if (!view.isFriend && invited) ...[
                const SizedBox(height: 10),
                Text(
                  kProfileRequestSent,
                  style: AppTheme.caption.copyWith(fontSize: 13),
                ),
              ],
              // The one place the public tree page is still worth linking: a
              // deliberate way on to it, shown only when its owner opted in.
              if (person.hasPublicTree) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onOpenTree,
                    child: Text(publicTreeLabel(name)),
                  ),
                ),
              ],
            ],
          ),
        ),

        if (mutual != null) ...[
          const SizedBox(height: 22),
          SectionHeader(title: mutual),
          const SizedBox(height: 4),
          Text(kProfileMutualsHint, style: AppTheme.caption.copyWith(fontSize: 12.5)),
          const SizedBox(height: 10),
          if (view.mutuals.isNotEmpty) _PersonList(people: view.mutuals),
          if (hiddenMutuals != null) ...[
            const SizedBox(height: 8),
            Text(hiddenMutuals, style: AppTheme.caption.copyWith(fontSize: 12.5)),
          ],
        ],

        // `null` is "not yours to see" and gets nothing at all; `[]` is a
        // friend whose only friend is the reader. [theirKringState] owns the
        // call, so this widget never compares against an empty list itself.
        if (kringState != FriendKringState.hidden) ...[
          const SizedBox(height: 22),
          SectionHeader(title: theirKringTitle(name)),
          const SizedBox(height: 10),
          if (kringState == FriendKringState.list)
            _PersonList(people: view.visibleFriends!)
          else
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Text(
                noOtherFriendsLabel(name),
                style: AppTheme.caption.copyWith(fontSize: 13.5),
              ),
            ),
        ],
      ],
    );
  }
}

/// A card of names and faces, each one a way on to that person's own profile.
/// Nothing else: a mutual friend or a friend-of-a-friend is not the subject of
/// this page.
class _PersonList extends StatelessWidget {
  const _PersonList({required this.people});

  final List<FriendSummary> people;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < people.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: AppTheme.rule),
            FriendTapTarget(
              onTap: () => openFriendProfile(context, people[i].userId),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                child: Row(
                  children: [
                    FriendAvatar(name: people[i].name, image: people[i].image, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        people[i].name.trim().isEmpty ? 'Een lezer' : people[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodyStrong.copyWith(
                          fontSize: 14,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 20, color: AppTheme.inkMuted),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens `/vriendenkring/<userId>`, the one way in to [FriendProfileScreen].
///
/// Every name and face in the kring goes through here, so a byline is a link
/// everywhere or nowhere. An empty id is not a route: a post whose author came
/// back without one simply does not open.
void openFriendProfile(BuildContext context, String userId) {
  final id = userId.trim();
  if (id.isEmpty) return;
  GoRouter.of(context).push('/vriendenkring/${Uri.encodeComponent(id)}');
}

/// The same, from inside a bottom sheet: the sheet closes first, so the
/// profile does not open behind it.
///
/// The router is looked up before the pop, because the sheet's own context is
/// no use once its route is gone.
void openFriendProfileFromSheet(BuildContext context, String userId) {
  final id = userId.trim();
  if (id.isEmpty) return;
  final router = GoRouter.of(context);
  Navigator.of(context).pop();
  router.push('/vriendenkring/${Uri.encodeComponent(id)}');
}
