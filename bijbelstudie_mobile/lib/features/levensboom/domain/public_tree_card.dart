/// What the API hands out about *someone else's* tree: enough to draw it,
/// nothing else. Mirror of the website's `lib/levensboom/publicCard.ts`.
library;

import 'catalog.dart';
import 'stages.dart';

class PublicTreeCard {
  const PublicTreeCard({
    required this.seed,
    required this.level,
    required this.avatar,
    required this.health,
    required this.disabled,
  });

  final String seed;
  final int level;
  final AvatarChoice avatar;
  final double health;

  /// "Boom tonen" off means no tree anywhere, other people's screens included.
  final bool disabled;

  StageInfo get stage => stageForLevel(level);

  static PublicTreeCard? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final seed = raw['seed'] as String? ?? '';
    if (seed.isEmpty) return null;
    return PublicTreeCard(
      seed: seed,
      level: (raw['level'] as num?)?.toInt() ?? 1,
      avatar: AvatarChoice.fromJson(raw['avatar']),
      health: (raw['health'] as num?)?.toDouble() ?? 1,
      disabled: raw['disabled'] == true,
    );
  }
}
