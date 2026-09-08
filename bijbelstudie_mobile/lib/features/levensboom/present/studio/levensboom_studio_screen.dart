import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';
import '../../../../core/ui/skeleton.dart';
import '../../domain/catalog.dart';
import '../../domain/tree_state.dart';
import '../levensboom_avatar.dart';
import '../levensboom_providers.dart';
import '../tree_view.dart';
import 'groei_tab.dart';
import 'studio_tiles.dart';

/// `/profile/boom` - the studio.
///
/// A live stage pinned on top and a grid of tiles under it. Tapping an
/// unlocked tile saves it at once (optimistic; a refusal rolls back and names
/// the rule); tapping a locked one previews it on the stage and says what it
/// takes, which is the whole "achievable" half of the avatar. A Pro tile sends
/// the reader to the app's own paywall - never to a web checkout. The mirror of
/// the website's `components/levensboom/studio/LevensboomStudio.tsx`.
class LevensboomStudioScreen extends ConsumerStatefulWidget {
  const LevensboomStudioScreen({super.key});

  @override
  ConsumerState<LevensboomStudioScreen> createState() => _LevensboomStudioScreenState();
}

enum _StudioTab { species, scene, animal, ring, groei }

const Map<_StudioTab, String> _tabLabels = {
  _StudioTab.species: 'Boomsoort',
  _StudioTab.scene: 'Omgeving',
  _StudioTab.animal: 'Dieren',
  _StudioTab.ring: 'Ring',
  _StudioTab.groei: 'Groei',
};

ItemKind? _kindOf(_StudioTab tab) => switch (tab) {
  _StudioTab.species => ItemKind.species,
  _StudioTab.scene => ItemKind.scene,
  _StudioTab.animal => ItemKind.animal,
  _StudioTab.ring => ItemKind.ring,
  _StudioTab.groei => null,
};

/// The website that shows the public profile: the API base without `/api/v1`.
String publicProfileUrl(String seed) {
  final base = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');
  return '$base/gebruiker/$seed';
}

class _LevensboomStudioScreenState extends ConsumerState<LevensboomStudioScreen> {
  _StudioTab _tab = _StudioTab.species;
  AvatarChoice? _preview;
  Timer? _seenTimer;

  @override
  void dispose() {
    _seenTimer?.cancel();
    super.dispose();
  }

  void _selectTab(_StudioTab tab) {
    setState(() {
      _tab = tab;
      _preview = null;
    });
    _scheduleSeen();
  }

  /// The "Nieuw" dots of the tab on screen are cleared once the reader has had
  /// a moment to see them.
  void _scheduleSeen() {
    _seenTimer?.cancel();
    final kind = _kindOf(_tab);
    final tree = ref.read(treeStateProvider).value;
    if (kind == null || tree == null) return;
    final fresh = [
      for (final item in itemsOfKind(kind))
        if (item.unlock is! FreeUnlock && tree.unlocked.contains(item.key) && !tree.seenItems.contains(item.key))
          item.key,
    ];
    if (fresh.isEmpty) return;
    _seenTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) ref.read(treeStateProvider.notifier).markItemsSeen(fresh);
    });
  }

  void _notice(String text, {bool pro = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        action: pro
            ? SnackBarAction(
                label: 'Bekijk Pro',
                onPressed: () => context.push('/premium?source=levensboom'),
              )
            : null,
      ),
    );
  }

  Future<void> _pick(TreeState tree, CatalogItem item) async {
    final locked = !tree.unlocked.contains(item.key);
    if (locked) {
      setState(() => _preview = tree.avatar.withItem(item.kind, item.id));
      final pro = item.unlock is ProUnlock;
      _notice(
        pro ? '${item.name} is er voor Pro-leden.' : '${item.name}: ${unlockLabel(item.unlock)} nodig.',
        pro: pro,
      );
      return;
    }
    setState(() => _preview = null);
    final outcome = await ref
        .read(treeStateProvider.notifier)
        .setAvatar(tree.chosen.withItem(item.kind, item.id));
    if (!mounted || !outcome.failed) return;
    _notice(
      outcome.label != null
          ? '${item.name}: ${outcome.label} nodig.'
          : 'Opslaan is niet gelukt. Probeer het nog eens.',
      pro: outcome.locked && item.unlock is ProUnlock,
    );
  }

  Future<void> _share(TreeState tree) async {
    if (!tree.publicProfile) {
      _notice("Zet 'Openbaar profiel' aan bij Instellingen om je boom te delen.");
      return;
    }
    await Clipboard.setData(ClipboardData(text: publicProfileUrl(tree.seed)));
    if (mounted) _notice('Link gekopieerd.');
  }

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(treeStateProvider);
    final tree = treeAsync.value;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Mijn levensboom'),
        actions: [
          if (tree != null)
            IconButton(
              tooltip: 'Deel link',
              icon: const Icon(Icons.link),
              onPressed: () => _share(tree),
            ),
        ],
      ),
      body: treeAsync.when(
        loading: () => const _Skeleton(),
        error: (_, __) => AppEmptyState(
          icon: Icons.wifi_off_outlined,
          title: 'Je boom kon niet worden geladen',
          description: 'Controleer je verbinding en probeer het opnieuw.',
          action: SiteOutlineButton(
            label: 'Opnieuw proberen',
            expand: false,
            onPressed: () => ref.read(treeStateProvider.notifier).refresh(),
          ),
        ),
        data: _body,
      ),
    );
  }

  Widget _body(TreeState tree) {
    final draw = _preview ?? tree.avatar;
    final kind = _kindOf(_tab);
    final needsIntro = !tree.introSeen && !tree.planted;

    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _StageHeader(tree: tree, draw: draw, disabled: tree.disabled),
        ),
        SliverToBoxAdapter(child: _ProgressStrip(tree: tree)),
        if (tree.disabled)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Je boom staat uit', style: AppTheme.metaLabel),
                    const SizedBox(height: 6),
                    Text(
                      'Je XP, niveau en badges lopen gewoon door — alleen de boom '
                      'wordt niet getoond.',
                      style: AppTheme.bodyMuted,
                    ),
                    const SizedBox(height: 14),
                    SiteButton(
                      label: 'Boom weer tonen',
                      onPressed: () => ref.read(treeStateProvider.notifier).setPrefs(disabled: false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (needsIntro)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Je levensboom is vernieuwd', style: AppTheme.metaLabel),
                    const SizedBox(height: 6),
                    Text(
                      'Je boom begint klein en groeit mee met alles wat je leest en '
                      'bestudeert. Kies hier je boomsoort, de omgeving en wie er bij '
                      'je boom woont — nieuwe keuzes ontgrendel je met je voortgang.',
                      style: AppTheme.bodyMuted,
                    ),
                    const SizedBox(height: 12),
                    SiteButton(
                      label: 'Kies je boomsoort',
                      expand: false,
                      onPressed: () {
                        ref.read(treeStateProvider.notifier).markIntroSeen();
                        _selectTab(_StudioTab.species);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: _Tabs(current: _tab, onSelect: _selectTab),
        ),
        if (kind == null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            sliver: SliverToBoxAdapter(child: GroeiTab(tree: tree)),
          )
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                'Tik om te kiezen; vergrendelde keuzes laten zien wat ervoor nodig is.',
                style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            sliver: StudioTileGrid(
              kind: kind,
              tree: tree,
              previewId: _preview?.idFor(kind),
              onPick: (item) => _pick(tree, item),
            ),
          ),
        ],
      ],
    );
  }
}

/// The pinned stage: shrinks from a full scene to a strip as the grid scrolls
/// under it, and the tree re-frames itself to whatever height it gets.
class _StageHeader extends SliverPersistentHeaderDelegate {
  _StageHeader({required this.tree, required this.draw, required this.disabled});

  final TreeState tree;
  final AvatarChoice draw;
  final bool disabled;

  @override
  double get maxExtent => 300;

  @override
  double get minExtent => 150;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final gold = draw.ring == TreeRing.goud;
    final frame = gold
        ? const LinearGradient(colors: [kGoldRingLight, kGoldRing])
        : LinearGradient(
            colors: [AppTheme.teal.withValues(alpha: 0.55), AppTheme.teal.withValues(alpha: 0.15)],
          );
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          gradient: frame,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg + 6),
        ),
        padding: const EdgeInsets.all(3),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg + 3),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (disabled)
                Container(
                  color: AppTheme.paperSunken,
                  alignment: Alignment.center,
                  child: Text('Boom verborgen', style: AppTheme.bodyMuted),
                )
              else
                TreeView(
                  seed: tree.seed,
                  level: tree.level,
                  frac: tree.progress,
                  health: tree.health,
                  species: draw.species,
                  scene: draw.scene,
                  animal: draw.animal,
                  reducedMotion: tree.reducedMotion,
                ),
              Positioned(
                left: 12,
                bottom: 10,
                child: Row(
                  children: [
                    _Pill(
                      text: 'Niveau ${tree.level}',
                      background: gold ? kGoldRing : AppTheme.teal,
                    ),
                    const SizedBox(width: 6),
                    _Pill(text: tree.stage.name, background: Colors.black.withValues(alpha: 0.45)),
                  ],
                ),
              ),
              if (tree.wilting)
                Positioned(
                  right: 12,
                  top: 10,
                  child: _Pill(
                    text: '${tree.daysSinceActive} dagen niet gelezen',
                    background: Colors.black.withValues(alpha: 0.45),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_StageHeader old) =>
      old.tree != tree || old.draw != draw || old.disabled != disabled;
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.background});

  final String text;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        text,
        style: AppTheme.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// One line under the stage: the bar, and where it leads.
class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.tree});

  final TreeState tree;

  @override
  Widget build(BuildContext context) {
    final next = tree.nextUnlock;
    final stage = tree.stage;
    final target = next != null
        ? (label: next.name, level: next.level)
        : stage.nextLevel != null
        ? (label: stage.nextName ?? '', level: stage.nextLevel!)
        : null;
    final soon = target != null && target.level == tree.level + 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: SiteProgressBar(value: tree.progress)),
              const SizedBox(width: 12),
              Text(
                soon
                    ? 'nog ${tree.xpToNextLevel} XP → ${target.label}'
                    : 'nog ${tree.xpToNextLevel} XP → niveau ${tree.level + 1}',
                style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
              ),
            ],
          ),
          if (target != null && !soon) ...[
            const SizedBox(height: 4),
            Text(
              'Volgende ontgrendeling: ${target.label} op niveau ${target.level}.',
              style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.current, required this.onSelect});

  final _StudioTab current;
  final ValueChanged<_StudioTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.rule)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tab in _StudioTab.values)
              InkWell(
                onTap: () => onSelect(tab),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: tab == current ? AppTheme.teal : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    _tabLabels[tab]!,
                    style: AppTheme.bodyStrong.copyWith(
                      color: tab == current ? Theme.of(context).colorScheme.onSurface : AppTheme.inkMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: const [
        Skeleton(height: 280, radius: 22),
        SizedBox(height: 18),
        SkeletonText(lines: 1, lineHeight: 8),
        SizedBox(height: 22),
        SkeletonCard(height: 160, child: SizedBox.shrink()),
        SizedBox(height: 12),
        SkeletonCard(height: 160, child: SizedBox.shrink()),
      ],
    );
  }
}
