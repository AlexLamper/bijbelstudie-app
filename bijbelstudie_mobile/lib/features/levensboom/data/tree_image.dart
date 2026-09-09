import '../domain/tree_state.dart';
import 'notification_canvas.dart';

export 'notification_canvas.dart' show TreeImageFiles;

/// Renders the reader's tree to files for a notification.
///
/// Kept as the bare "just the tree" entry point now that the picture can also
/// carry a streak, a countdown and a level ring: everything below is
/// [renderNotificationArt] with no chrome asked for
/// (`AVATAR_NOTIFICATIONS_PLAN.md` §2.3).
///
/// [healthOverride] lets the wilting nudge show the tree as it will look on
/// day three, which is the point of sending it on day two.
Future<TreeImageFiles?> renderTreeImages({
  required TreeState tree,
  required String name,
  double? healthOverride,
  Duration budget = const Duration(milliseconds: 400),
}) =>
    renderNotificationArt(
      NotifArtSpec.tree(tree: tree, healthOverride: healthOverride),
      name: name,
      budget: budget,
    );
