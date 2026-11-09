import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../auth/present/auth_controller.dart';
import '../../profile/domain/bible_progress.dart';
import '../../profile/present/bible_milestone_bar.dart';
import '../../profile/present/bookcase_view.dart';
import '../data/bible_progress_seen_store.dart';
import '../domain/bible_milestones.dart';

/// "Je Bijbel" on Start, under the tekst van de dag: the share of all 1189
/// chapters read, the bookcase of `/profile/bijbel` in miniature, a milestone
/// bar and what is left to the next milestone. Built from the `readChapters`
/// map `/dashboard` already returns; a tap opens the bookcase itself.
///
/// The first time it shows in a session the number counts up, the little
/// spines fill in reading order and the bar grows, all in about 1.4 s. A milestone crossed
/// since the card last showed (remembered per account on the device) makes its
/// tick glow and turns the footer into a short celebration.
class BibleProgressCard extends ConsumerStatefulWidget {
  const BibleProgressCard({super.key, required this.readChapters});

  final Map<String, List<int>> readChapters;

  @override
  ConsumerState<BibleProgressCard> createState() => _BibleProgressCardState();
}

class _BibleProgressCardState extends ConsumerState<BibleProgressCard>
    with TickerProviderStateMixin {
  /// The intro plays once per app session, not every time Start rebuilds.
  static bool _introPlayed = false;

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late BibleProgress _progress = BibleProgress.fromReadChapters(widget.readChapters);
  BibleMilestone? _celebrating;

  @override
  void initState() {
    super.initState();
    final playIntro = !_introPlayed;
    _introPlayed = true;
    if (!playIntro) _intro.value = 1;
    unawaited(_sync(playIntro: playIntro));
  }

  @override
  void didUpdateWidget(BibleProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.readChapters, widget.readChapters)) return;
    final before = _progress.percent;
    _progress = BibleProgress.fromReadChapters(widget.readChapters);
    if (_progress.percent != before) unawaited(_sync(playIntro: false));
  }

  @override
  void dispose() {
    _intro.dispose();
    _glow.dispose();
    super.dispose();
  }

  /// Compares the shown share with the last one seen, remembers the new one
  /// and starts whatever animation is due.
  Future<void> _sync({required bool playIntro}) async {
    final userId = ref.read(authControllerProvider).value?.id;
    final now = _progress.percent;
    final lastSeen = await BibleProgressSeenStore.read(userId);
    if (!mounted) return;
    if (lastSeen != now) unawaited(BibleProgressSeenStore.write(userId, now));

    final crossed = crossedBibleMilestone(lastSeen: lastSeen, now: now);
    if (crossed != null) setState(() => _celebrating = crossed);

    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      return;
    }
    void glow() {
      if (mounted && crossed != null) _glow.forward(from: 0);
    }

    if (playIntro) {
      _intro.forward(from: 0).whenCompleteOrCancel(glow);
    } else {
      glow();
    }
  }

  void _open() => context.push('/profile/bijbel');

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final p = _progress;
    final footer = _celebrating?.celebration ??
        bibleMilestoneFooter(p.chaptersRead, p.chaptersTotal);
    final inProgress = p.booksStarted - p.booksCompleted;

    return Semantics(
      button: true,
      label: 'Je Bijbel, ${formatBiblePercent(p.percent)} van alle hoofdstukken gelezen. '
          '${p.booksCompleted} van ${p.booksTotal} boeken gelezen'
          '${inProgress > 0 ? ', $inProgress bezig' : ''}. $footer',
      onTap: _open,
      excludeSemantics: true,
      child: AppCard(
        padding: EdgeInsets.zero,
        clip: true,
        onTap: _open,
        child: AnimatedBuilder(
          animation: Listenable.merge([_intro, _glow]),
          builder: (context, _) => _content(context, scheme.surface, footer),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, Color surface, String footer) {
    final p = _progress;
    final v = _intro.value;
    final count = p.percent * Curves.easeOutCubic.transform(const Interval(0, 0.6).transform(v));
    final shown = v >= 1 ? p.percent : count;
    final percentText = shown < 0.1 && shown < p.percent ? '0%' : formatBiblePercent(shown);
    final footerIn = Curves.easeOut.transform(const Interval(0.72, 1).transform(v));
    final celebrating = _celebrating != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Je Bijbel',
                          style: AppTheme.caption.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          percentText,
                          style: AppTheme.statNumber.copyWith(
                            fontSize: 32,
                            height: 1.1,
                            letterSpacing: -0.5,
                            color: AppTheme.teal,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${p.booksCompleted} van ${p.booksTotal} boeken gelezen',
                          style: AppTheme.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: CustomPaint(
                      size: MiniBookcasePainter.size,
                      painter: MiniBookcasePainter(
                        books: p.books,
                        intro: v,
                        palette: BookcasePalette.current,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              BibleMilestoneBar(
                fraction: p.percent / 100,
                intro: v,
                glow: _glow.value,
                glowAt: _celebrating?.fraction,
                cut: surface,
              ),
            ],
          ),
        ),
        Container(
          color: AppTheme.tealTint,
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Opacity(
            opacity: footerIn,
            child: Transform.translate(
              offset: Offset(0, 6 * (1 - footerIn)),
              child: Row(
                children: [
                  Icon(
                    celebrating ? Icons.flag : Icons.flag_outlined,
                    size: 16,
                    color: AppTheme.teal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      footer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(
                        fontSize: 13,
                        fontWeight: celebrating ? FontWeight.w700 : FontWeight.w600,
                        color: celebrating ? AppTheme.teal : AppTheme.inkSoft,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 20, color: AppTheme.inkFaint),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
