import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'music_menu_sheet.dart';
import 'music_picker_sheet.dart';
import 'music_player_controller.dart';

/// The reader's note button: the menu while something plays, otherwise the
/// list to choose from. Never gated itself - see `showMusicPickerSheet`.
Future<void> openMusic(BuildContext context, WidgetRef ref) {
  if (ref.read(musicPlayerProvider).isPlaying) return showMusicMenuSheet(context);
  return showMusicPickerSheet(context);
}
