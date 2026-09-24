import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../profile/present/profile_provider.dart';
import '../data/referral_repository.dart';

const _months = [
  'januari', 'februari', 'maart', 'april', 'mei', 'juni',
  'juli', 'augustus', 'september', 'oktober', 'november', 'december',
];

String _day(DateTime date) => '${date.day} ${_months[date.month - 1]}';

/// "Nodig een vriend uit" on Profiel: the section header and its card, or
/// nothing at all while the invite data is unavailable - an older server, no
/// connection - so the profile never shows a broken card.
///
/// Sharing is optional and unlocks nothing the reader already had
/// (guideline 3.2.2); the link goes to the website's /uitnodiging page, never
/// to a checkout.
class InviteSection extends ConsumerWidget {
  const InviteSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(referralOverviewProvider).value;
    if (overview == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 28),
        const SectionHeader(title: 'Nodig een vriend uit'),
        const SizedBox(height: 12),
        _InviteCard(overview: overview),
      ],
    );
  }
}

class _InviteCard extends ConsumerStatefulWidget {
  const _InviteCard({required this.overview});

  final ReferralOverview overview;

  @override
  ConsumerState<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends ConsumerState<_InviteCard> {
  final _codeController = TextEditingController();
  bool _claiming = false;
  ClaimOutcome? _outcome;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _share(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : null;
    try {
      await Share.share(widget.overview.shareText, sharePositionOrigin: origin);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delen is niet gelukt.')),
        );
      }
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.overview.url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link gekopieerd')),
      );
    }
  }

  Future<void> _claim() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _claiming = true;
      _outcome = null;
    });
    final outcome = await ref.read(referralRepositoryProvider).claim(code);
    if (!mounted) return;
    setState(() {
      _claiming = false;
      _outcome = outcome;
    });
    if (outcome.ok) {
      // Pro is read from /me; refetching it opens every paywall at once.
      ref.invalidate(profileProvider);
      ref.invalidate(referralOverviewProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final overview = widget.overview;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Maakt een vriend via jouw link een account, dan krijgt die meteen '
            'een week Pro.'
            '${overview.youEarn ? ' Gaat je vriend echt aan de slag, dan krijg '
                'jij er ook een week bij.' : ''}',
            style: AppTheme.bodyMuted,
          ),
          const SizedBox(height: 14),
          Builder(
            builder: (buttonContext) => SiteButton(
              label: 'Deel je link',
              icon: Icons.ios_share,
              height: 44,
              onPressed: () => _share(buttonContext),
            ),
          ),
          const SizedBox(height: 10),
          // The link itself, as on the website's card, with copy as an icon
          // control - two labelled buttons side by side do not fit a phone.
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              color: AppTheme.paperSunken,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: AppTheme.rule),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    overview.url.replaceFirst('https://', ''),
                    style: AppTheme.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Kopieer link',
                  color: AppTheme.teal,
                  onPressed: _copy,
                ),
              ],
            ),
          ),
          if (overview.joined > 0 || (overview.youEarn && overview.proUntil != null)) ...[
            const SizedBox(height: 12),
            if (overview.joined > 0)
              Text(
                '${overview.joined} ${overview.joined == 1 ? 'vriend' : 'vrienden'} via jouw link'
                '${overview.active > 0 ? ' · ${overview.active} al aan de slag' : ''}',
                style: AppTheme.caption,
              ),
            if (overview.youEarn && overview.proUntil != null)
              Text('Je hebt Pro tot ${_day(overview.proUntil!)}.', style: AppTheme.caption),
          ],
          if (overview.canClaim) ...[
            const SizedBox(height: 14),
            const RuleLine(),
            const SizedBox(height: 12),
            Text('Heb je zelf een uitnodigingscode?', style: AppTheme.bodyStrong),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      hintText: 'ABCD 2345',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _claim(),
                  ),
                ),
                const SizedBox(width: 10),
                SiteButton(
                  label: 'Gebruiken',
                  height: 44,
                  expand: false,
                  loading: _claiming,
                  onPressed: _claim,
                ),
              ],
            ),
          ],
          if (_outcome != null) ...[
            const SizedBox(height: 8),
            Text(
              _outcome!.ok && _outcome!.proUntil != null
                  ? 'Je week Pro is gestart, tot ${_day(_outcome!.proUntil!)}.'
                  : _outcome!.message,
              style: AppTheme.caption.copyWith(
                color: _outcome!.ok ? AppTheme.teal : AppTheme.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
