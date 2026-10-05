import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/friend_models.dart';
import '../data/friends_repository.dart';
import 'friend_post_card.dart' show FriendAvatar;
import 'friend_profile_screen.dart' show openFriendProfile;
import 'friend_tap_target.dart';
import 'friends_providers.dart';

/// "Mensen die je misschien kent" - `GET /friends/suggestions`, under the
/// kring in the Vrienden tab.
///
/// Friends of the people already in the kring, which is why it belongs here
/// and nowhere that implies otherwise: a reader with no friends has no
/// friends-of-friends, so for them this list is structurally empty, not
/// broken. It therefore renders **nothing at all** when the list is empty and
/// nothing at all on a failure - no skeleton, no "kon niet laden". A section
/// that was never promised cannot disappoint.
class FriendSuggestionsSection extends ConsumerWidget {
  const FriendSuggestionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    // `.value` on purpose: loading and error both read as "nothing to show".
    final people = ref.watch(friendSuggestionsProvider).value?.suggestions;
    if (people == null || people.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const SectionHeader(title: 'Mensen die je misschien kent'),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Vrienden van de mensen in je kring.',
            style: AppTheme.caption.copyWith(fontSize: 12.5),
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < people.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: AppTheme.rule),
                FriendSuggestionRow(person: people[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One suggestion: a face, a name, what they have in common, and the way in.
///
/// The row stays after the verzoek is sent and says so, rather than vanishing:
/// a row that disappears under the thumb reads as a mis-tap, and the verzoek
/// is pending, not done.
class FriendSuggestionRow extends ConsumerStatefulWidget {
  const FriendSuggestionRow({super.key, required this.person});

  final FriendSummary person;

  @override
  ConsumerState<FriendSuggestionRow> createState() => _FriendSuggestionRowState();
}

class _FriendSuggestionRowState extends ConsumerState<FriendSuggestionRow> {
  bool _busy = false;
  bool _sent = false;

  Future<void> _invite() async {
    if (_busy || _sent) return;
    setState(() => _busy = true);
    final result = await ref
        .read(friendsRepositoryProvider)
        .invite(userId: widget.person.userId, source: 'suggestion');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sent = result.ok;
    });
    if (result.ok) {
      ref.invalidate(friendsRequestsProvider);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final person = widget.person;
    // Never formatted here: `mutualLabel` is null for an unknown count and for
    // zero alike, so "0 gezamenlijke vrienden" cannot be said.
    final mutual = person.mutualLabel;

    return FriendTapTarget(
      onTap: () => openFriendProfile(context, person.userId),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            FriendAvatar(name: person.name, image: person.image, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name.trim().isEmpty ? 'Een lezer' : person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyStrong.copyWith(
                      fontSize: 14,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (mutual != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      mutual,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(fontSize: 12.5),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_sent)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  'Verzoek verstuurd',
                  style: AppTheme.caption.copyWith(fontSize: 12.5),
                ),
              )
            else
              SiteButton(
                label: _busy ? 'Versturen...' : 'Uitnodigen',
                expand: false,
                height: 40,
                onPressed: _busy ? null : _invite,
              ),
          ],
        ),
      ),
    );
  }
}
