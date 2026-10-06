import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/display_name.dart';
import '../../auth/present/auth_controller.dart';
import '../../dashboard/present/dashboard_providers.dart';
import '../../progress_tree/present/progress_tree_avatar.dart';
import '../../progress_tree/present/progress_tree_providers.dart';
import '../../notes/present/notes_providers.dart';
import '../../onboarding/present/tour_controller.dart';
import '../data/profile_model.dart';
import '../data/profile_repository.dart';
import '../domain/profile_stats.dart';
import 'profile_activity_feed.dart';
import 'profile_menu_sheet.dart';
import 'profile_provider.dart';
import '../../premium/domain/store_copy.dart';
import '../../premium/present/pro_access_provider.dart';
import '../../premium/present/paywall_route.dart';
import '../../referral/data/referral_repository.dart';
import '../../referral/present/invite_section.dart';
import 'profile_stats_provider.dart';

/// Profiel: who you are, what you have read, and what you have done with it.
///
/// The plain navigation this screen used to list lives in the hamburger sheet
/// now ([showProfileMenuSheet]); the screen itself carries the account's own
/// numbers - streak, books, notities, badges - and the activity they produced.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: profileAsync.when(
          loading: () => const _ProfileSkeleton(),
          error: (error, __) => _signedOut(error)
              // A dead session is not a network failure: "opnieuw proberen"
              // would just fail again, so offer the only thing that helps.
              ? AppEmptyState(
                  icon: Icons.lock_outline,
                  title: 'Je bent uitgelogd',
                  description:
                      'Log opnieuw in om je profiel en voortgang te zien.',
                  action: SiteOutlineButton(
                    label: 'Inloggen',
                    expand: false,
                    onPressed: () => context.go('/login'),
                  ),
                )
              : AppEmptyState(
                  icon: Icons.wifi_off_outlined,
                  title: 'Profiel niet geladen',
                  description:
                      'Controleer je verbinding en probeer het opnieuw.',
                  action: SiteOutlineButton(
                    label: 'Opnieuw proberen',
                    expand: false,
                    onPressed: () => ref.invalidate(profileProvider),
                  ),
                ),
          data: (profile) => RefreshIndicator(
            color: AppTheme.teal,
            backgroundColor: AppTheme.paperRaised,
            onRefresh: () => _refresh(ref),
            child: _ProfileBody(profile: profile),
          ),
        ),
      ),
    );
  }

  /// True when the profile request came back as "no valid session" rather than
  /// as a transport failure.
  static bool _signedOut(Object error) =>
      error is DioException && error.response?.statusCode == 401;

  /// Pull-to-refresh: every request the body reads from is repeated together,
  /// and the spinner stays up until the last one lands rather than the first.
  ///
  /// Failures are swallowed here on purpose. Each provider keeps its own error
  /// state and the widget reading it already shows that; a rejected future
  /// would only surface again as an unhandled exception from the indicator.
  static Future<void> _refresh(WidgetRef ref) async {
    Future<void> quiet(Future<Object?> request) async {
      try {
        await request;
      } catch (_) {}
    }

    await Future.wait<void>([
      quiet(ref.refresh(profileProvider.future)),
      quiet(ref.refresh(dashboardProvider.future)),
      quiet(ref.refresh(notesListProvider.future)),
      quiet(ref.refresh(highlightsListProvider.future)),
      quiet(ref.refresh(bookmarksProvider.future)),
      quiet(ref.refresh(referralOverviewProvider.future)),
      // The tree's own refresh keeps what is on screen if the fetch fails.
      ref.read(treeStateProvider.notifier).refresh(),
    ]);
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile});

  final ProfileModel profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The top bar and the identity row carry their own insets (24 left, 20
     // right) so the name can start further from the edge than the cards do;
    // everything below shares one 20 gutter.
    return ListView(
      padding: EdgeInsets.zero,
      // Always scrollable, so the pull-to-refresh around it works on a body
      // that happens to be shorter than the screen.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 20, 0),
          child: _HeaderBar(profile: profile),
        ),
        // The progress tree is the picture in this header - see [ProgressTreeAvatar],
        // which also owns the level-up celebration.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 20, 0),
          child: _ProfileHeader(profile: profile),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _StatTiles(),

              const SizedBox(height: 22),
              const _BadgesCard(),

              // Brings its own header and spacing, and renders nothing when the
              // invite data is unavailable.
              const InviteSection(),

              const SizedBox(height: 22),
              const ProfileSectionHeading('Activiteit'),
              const SizedBox(height: 10),
              ProfileActivityFeed(profile: profile),

              const SizedBox(height: 20),
        // Provenance, not decoration: App Store review checks it on scripture
        // apps (guideline 5.2), so a blanket "publiek domein" that is no longer
        // true of everything shipped is worse than saying nothing. Two sources
        // are licensed rather than public domain - the NBG-vertaling 1951 and
        // KingComments - and both are named here for that reason.
              Text(
                'De meeste vertalingen en commentaren in deze app zijn publiek '
                'domein. De NBG-vertaling 1951 en KingComments (Ger de Koning) '
                'worden met toestemming van de rechthebbenden aangeboden. De '
                'grondtekst komt van STEPBible (TAHOT/TAGNT) en is beschikbaar '
                'onder CC BY 4.0.',
                style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
              ),

              const SizedBox(height: 24),
              SiteOutlineButton(
                label: 'Uitloggen',
                icon: Icons.logout,
                onPressed: () async {
                  await ref.read(authControllerProvider.notifier).logout();
                  if (context.mounted) context.go('/login');
                },
              ),
              const SizedBox(height: 8),
        // Guideline 5.1.1(v): deletion must be reachable without leaving the
        // app, so it stays on the screen itself rather than in the menu sheet.
              TextButton(
                onPressed: () => _confirmDelete(context, ref),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.destructive,
                ),
                child: const Text('Account verwijderen'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Account verwijderen'),
        content: Text(
          'Je account, voortgang, notities, markeringen, bladwijzers en '
          'leesgeschiedenis worden definitief verwijderd. Dit kan niet ongedaan '
          'worden gemaakt.\n\n'
          'Log je daarna opnieuw in met ${StoreCopy.isPlay ? 'Google' : 'Google of Apple'}, '
          'dan krijg je een nieuw, leeg account. Je oude voortgang komt niet terug.\n\n'
          'Heb je een abonnement via ${StoreCopy.storeInSentence}? Zeg dat apart op in je '
          '${StoreCopy.manageLocation} - '
          '${StoreCopy.isPlay ? 'het stopt niet vanzelf als je je account verwijdert.' : 'Apple staat niet toe dat een app dat voor je doet.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
            child: const Text('Definitief verwijderen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(profileRepositoryProvider).deleteAccount();
    } catch (e) {
      if (!context.mounted) return;
      // The server says why when it refuses (a protected admin account, a
      // rate limit); a bare "mislukt" hid that and read as a broken button.
      final body = e is DioException ? e.response?.data : null;
      final message = body is Map
          ? AuthRepository.authErrorMessage(body, 'Verwijderen mislukt')
          : 'Verwijderen mislukt. Probeer het opnieuw.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }
    // The account is gone. Signing out is best-effort from here: the server
    // already revoked every token, so a failing sign-out call must not keep
    // the screen on an account that no longer exists.
    try {
      await ref.read(authControllerProvider.notifier).logout();
    } catch (_) {}
    if (context.mounted) context.go('/login');
  }
}

/// The heading above a section on Profiel: 18 bold, indented 4 so it sits over
/// the card's text rather than over its border.
///
/// Its own widget rather than [SectionHeader] because these two carry nothing
/// but a title - no eyebrow, no description, no action - and the sections on
/// Profiel are set a little larger than the ones on the other tabs.
class ProfileSectionHeading extends StatelessWidget {
  const ProfileSectionHeading(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: AppTheme.displayTitle.copyWith(
          fontSize: 18,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

/// The top bar: the section label on the left, the three controls that lead
/// somewhere real on the right - share the app, settings, the rest of the menu.
///
/// A scan / QR button belongs here in the layout being followed, but this app
/// has nothing to scan - no invite codes in the UI, no plan-sharing links - so
/// it is left out rather than shipped as a dead control.
class _HeaderBar extends ConsumerWidget {
  const _HeaderBar({required this.profile});

  final ProfileModel profile;

  /// What the share button hands out: the product, not the reader. The personal
  /// invite link is its own card further down ([InviteSection]) and gives away
  /// a week of Pro, which is not what a bare share button should do.
  Future<void> _shareApp(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : null;
    try {
      await Share.share(
        'Ik gebruik BijbelStudie om de Bijbel te lezen en te studeren: '
        '${AppConfig.siteUrl}',
        sharePositionOrigin: origin,
      );
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delen is niet gelukt.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const Expanded(child: Eyebrow('Profiel')),
          Builder(
            builder: (shareContext) => _HeaderIcon(
              tooltip: 'Deel de app',
              icon: Icons.ios_share,
              onPressed: () => _shareApp(shareContext),
            ),
          ),
          const SizedBox(width: 4),
          _HeaderIcon(
            tooltip: 'Instellingen',
            icon: Icons.settings_outlined,
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: 4),
          _HeaderIcon(
            tooltip: 'Menu',
            icon: Icons.menu,
            onPressed: () => showProfileMenuSheet(context, ref, profile),
          ),
        ],
      ),
    );
  }
}

/// One of the three controls in the top bar: a 42 tap target around a 22 glyph,
/// with none of [IconButton]'s own padding, so the three sit 4 apart.
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 22),
      color: AppTheme.ink,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 42, height: 42),
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }
}

/// Name and status chips on the left, the avatar on the right.
///
/// No e-mail address: it is not something the reader needs to be told, it is
/// the longest string on the screen, and for an Apple Hide-My-Email account it
/// is noise. The two chips under the name say the things that do change.
class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.profile});

  final ProfileModel profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = displayFirstName(profile.name, profile.email) == null
        ? 'Gebruiker'
        : profile.name.trim();
    final stats = ref.watch(profileStatsProvider).value;
    final isPro = profile.isPro || ref.watch(hasProProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          // Up 4, so the name's cap height lines up with the top of the ring
          // rather than its text box doing.
          child: Transform.translate(
            offset: const Offset(0, -4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: AppTheme.displayMedium.copyWith(
                          fontSize: 29,
                          letterSpacing: -0.6,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RenameButton(profile: profile),
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    if (isPro)
                      // Opens the subscriber's status and the manage-
                      // subscription link; /premium never shows them prices.
                      _StatusChip(
                        onTap: () => context.push('/premium'),
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        children: [
                          const _ChipWord(
                            'PRO',
                            bold: true,
                            color: _ChipColor.pro,
                          ),
                          _ChipWord(
                            profile.isProFromWeb ? 'via web' : 'actief',
                          ),
                        ],
                      )
                    else
                      // Guideline 3.1.1: only a non-subscriber is offered the
                      // purchase route. The tour anchor sits on this chip
                      // alone - on the row it used to be on, the spotlight also
                      // took in the streak chip beside it.
                      TourAnchor(
                        id: TourAnchorIds.profilePro,
                        child: _StatusChip(
                          onTap: () =>
                              openPaywall(context, source: 'app_profile'),
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          children: const [
                            _ChipWord('PRO', bold: true, color: _ChipColor.pro),
                            _ChipWord('bekijk'),
                          ],
                        ),
                      ),
                    if (stats != null)
                      _StatusChip(
                        onTap: () => context.go('/dashboard'),
                        padding: const EdgeInsets.fromLTRB(5, 0, 7, 0),
                        children: [
                          Icon(
                            Icons.local_fire_department,
                            size: 11,
                            color: AppTheme.flame,
                          ),
                          _ChipWord(
                            '${stats.streak} '
                            '${stats.streak == 1 ? 'dag' : 'dagen'}',
                            bold: true,
                            color: _ChipColor.ink,
                          ),
                          const _ChipWord('reeks'),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // The picture is the progress tree, which falls back to the initials
        // avatar while the tree loads or when the reader has switched it off.
        // Nothing sits on top of it: the rename control is beside the name.
        ProgressTreeAvatar(
          size: 96,
          fallback: ProfileAvatar(profile: profile, size: 96),
        ),
      ],
    );
  }
}

/// Which of the three inks a word in a chip takes.
enum _ChipColor { pro, ink, muted }

/// One word inside a [_StatusChip]. Two sizes of nothing: every word is 10, and
/// only the weight and the colour change, so the chips stay 20 high whatever
/// goes in them.
class _ChipWord extends StatelessWidget {
  const _ChipWord(this.text, {this.bold = false, this.color = _ChipColor.muted});

  final String text;
  final bool bold;
  final _ChipColor color;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Text(
      text,
      style: TextStyle(
        fontFamily: AppTheme.sansFontName,
        fontSize: 10,
        height: 1,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        letterSpacing: color == _ChipColor.pro ? 0.4 : null,
        color: switch (color) {
          _ChipColor.pro => AppTheme.tealStrong,
          _ChipColor.ink => AppTheme.ink,
          _ChipColor.muted => AppTheme.inkMuted,
        },
      ),
    );
  }
}

/// A 20-high pill under the name. Small enough that it reads as a label rather
/// than a button, so the whole chip is the tap target instead of carrying one.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.children,
    required this.padding,
    this.onTap,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final chip = Container(
      height: 20,
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.paperRaised,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppTheme.ruleStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            children[i],
          ],
        ],
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      onTap: onTap,
      child: chip,
    );
  }
}

/// The rename control, beside the name it changes.
///
/// A pencil rather than a camera, and next to the name rather than on the
/// avatar, on purpose: `PATCH /me` takes a name and reading preferences and
/// there is no image-upload endpoint anywhere in `/api/v1`, so the control
/// opens the profile edit that really exists - and sits by the field it edits
/// instead of over a picture it could never change.
class _RenameButton extends ConsumerWidget {
  const _RenameButton({required this.profile});

  final ProfileModel profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Naam wijzigen',
      icon: const Icon(Icons.edit_outlined, size: 16),
      color: AppTheme.inkSoft,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      visualDensity: VisualDensity.compact,
      onPressed: () => showProfileNameDialog(context, ref, profile),
    );
  }
}

/// The three figures worth the top of the screen: books opened, days in the app
/// this year, and the streak.
///
/// It used to be four tiles, two of which (Bladwijzers, Notities) only repeated
/// what the Notities tab in the tab bar already leads to. Three leaves each tile
/// wide enough for a two-line label and a number at a readable size.
class _StatTiles extends ConsumerWidget {
  const _StatTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(profileStatsProvider).value;
    final streak = stats?.streak;

    // IntrinsicHeight, not `CrossAxisAlignment.stretch`: inside a ListView the
    // Row has no bounded height to stretch into, and the tiles still have to
    // end level when one label wraps.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatTile(
              label: 'Bijbelboeken',
              value: stats?.booksRead.toString(),
              unit: '/${ProfileStats.canonBooks}',
              unitGap: 1,
              onTap: () => context.push('/profile/bijbel'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              label: 'Dagen in de app dit jaar',
              // Null on a server that predates the field: the device only sees
              // the last 7 days, so there is nothing honest to fall back on.
              value: stats?.activeDaysThisYear?.toString(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              label: 'Leesreeks',
              icon: Icons.local_fire_department,
              iconColor: AppTheme.flame,
              value: streak?.toString(),
              unit: streak == 1 ? 'dag' : 'dagen',
              unitGap: 4,
              onTap: () => context.go('/dashboard'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One figure: its label up top, the number under it.
///
/// A plain [Container] rather than [AppCard]: these three carry a soft shadow
/// and no border, which is the one card shape in the app that does.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.unit,
    this.unitGap = 4,
    this.icon,
    this.iconColor,
    this.onTap,
  });

  final String label;

  /// Null while the figure has not loaded, or when the server cannot give it.
  final String? value;
  final String? unit;
  final double unitGap;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;

  /// Two lines of the 9/1.35 label, always reserved. It keeps the three numbers
  /// on one line as each other whether a label wraps or not.
  static const double _labelHeight = 25;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    final tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.paperRaised,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.06),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            height: _labelHeight,
            child: Text(
              label.toUpperCase(),
              style: AppTheme.overline.copyWith(
                fontSize: 9,
                letterSpacing: 0.7,
                height: 1.35,
                color: AppTheme.inkFaint,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22, color: iconColor),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  value ?? '-',
                  style: AppTheme.statNumber.copyWith(
                    fontSize: 21,
                    letterSpacing: -0.6,
                    height: 1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unit != null && value != null) ...[
                SizedBox(width: unitGap),
                Text(
                  unit!,
                  style: TextStyle(
                    fontFamily: AppTheme.sansFontName,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 1,
                    color: AppTheme.inkFaint,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return tile;
    return Pressable(
      scale: 0.98,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: tile,
      ),
    );
  }
}

/// The badge cabinet's front: the tally, the way in to the rest
/// ([BadgesScreen] at `/profile/badges`), and the last few earned.
///
/// Earned only, newest first. The grey "not yet" discs that used to fill the row
/// said nothing the tally does not, and a shelf of locks is a poor reward for
/// having earned twelve things. The whole card is the tap target; the chevron
/// says where it goes.
class _BadgesCard extends ConsumerWidget {
  const _BadgesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(profileBadgesProvider);
    if (badges.isEmpty) return const _BadgesSkeleton();

    final earned = badges.where((badge) => badge.unlocked).toList();

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => context.push('/profile/badges'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('Beloningen', style: AppTheme.displayTitle),
                ),
                Text(
                  '${earned.length} van ${badges.length}',
                  style: AppTheme.caption.copyWith(fontSize: 13),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 17,
                  color: AppTheme.ruleStrong,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: earned.isEmpty
                ? Text(
                    'Je eerste beloning komt zodra je een paar dagen op rij '
                    'leest.',
                    style: AppTheme.bodyMuted,
                  )
                : _BadgeCluster(earned: earned),
          ),
        ],
      ),
    );
  }
}

/// The last few earned badges, overlapping like coins laid out on a table - the
/// leftmost, newest one on top - with a "+n" disc for the ones that did not fit.
class _BadgeCluster extends StatelessWidget {
  const _BadgeCluster({required this.earned});

  /// Earned badges in the order they were granted, oldest first.
  final List<BadgeProgress> earned;

  /// How many discs are drawn before the rest become "+n".
  static const int _shown = 4;
  static const double _size = 36;

  /// Distance between disc centres: 7 less than the width, which is the overlap.
  static const double _step = _size - 7;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    // Newest first, so the disc on top is the one just won.
    final newest = earned.reversed.take(_shown).toList();
    final overflow = earned.length - newest.length;
    final slots = newest.length + (overflow > 0 ? 1 : 0);

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: _size + (slots - 1) * _step,
        height: _size,
        child: Stack(
          children: [
            if (overflow > 0)
              Positioned(
                left: newest.length * _step,
                child: _Disc(
                  fill: AppTheme.paperSunken,
                  border: AppTheme.paperSunken,
                  child: Text(
                    '+$overflow',
                    style: AppTheme.bodyStrong.copyWith(
                      fontSize: 11.5,
                      color: AppTheme.inkMuted,
                    ),
                  ),
                ),
              ),
            // Painted right to left, so each disc lies over its neighbour.
            for (var i = newest.length - 1; i >= 0; i--)
              Positioned(
                left: i * _step,
                child: _Disc(
                  fill: AppTheme.tealTint,
                  border: AppTheme.teal,
                  child: Icon(
                    newest[i].definition.icon,
                    size: 16,
                    color: AppTheme.tealStrong,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One disc in the cluster. The white ring is a shadow rather than a second
/// border, so it sits outside the 36 and the discs still overlap by exactly 7.
class _Disc extends StatelessWidget {
  const _Disc({required this.fill, required this.border, required this.child});

  final Color fill;
  final Color border;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _BadgeCluster._size,
      height: _BadgeCluster._size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: border, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.paperRaised,
            spreadRadius: 2.5,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _BadgesSkeleton extends StatelessWidget {
  const _BadgesSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonCard(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Skeleton(height: 16, width: 110)),
              Skeleton(height: 13, width: 64),
            ],
          ),
          SizedBox(height: 14),
          Row(
            children: [
              Skeleton.circle(36),
              SizedBox(width: 2),
              Skeleton.circle(36),
              SizedBox(width: 2),
              Skeleton.circle(36),
              SizedBox(width: 2),
              Skeleton.circle(36),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(height: 26, width: 170),
                  SizedBox(height: 9),
                  Skeleton(height: 20, width: 150, radius: 999),
                ],
              ),
            ),
            SizedBox(width: 12),
            Skeleton.circle(96),
          ],
        ),
        const SizedBox(height: 22),
        const Row(
          children: [
            Expanded(
              child: SkeletonCard(height: 74, child: SizedBox.shrink()),
            ),
            SizedBox(width: 10),
            Expanded(
              child: SkeletonCard(height: 74, child: SizedBox.shrink()),
            ),
            SizedBox(width: 10),
            Expanded(
              child: SkeletonCard(height: 74, child: SizedBox.shrink()),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _BadgesSkeleton(),
        const SizedBox(height: 22),
        const Skeleton(height: 18, width: 100),
        const SizedBox(height: 10),
        const SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Skeleton.circle(34),
                  SizedBox(width: 10),
                  Expanded(child: Skeleton(height: 12, width: 160)),
                ],
              ),
              SizedBox(height: 14),
              SkeletonText(lines: 3, lineHeight: 11),
            ],
          ),
        ),
      ],
    );
  }
}
