import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/commentary_note_anchor.dart';

/// The commentary section the standalone commentary screen should open on next.
///
/// Written by a tap on a commentary note in the Notities list, which also sets
/// the reader location and the commentary source before it navigates to
/// `/commentary`; consumed (reset to null) by the pane on that screen once its
/// chapter has rendered. Same one-shot shape as
/// `pendingCommentaryVerseProvider` in `commentary_jump.dart`, and kept
/// separate from it on purpose: that one belongs to the pane beside the reader
/// in `/studie`, and a target meant for a note must not be swallowed by a pane
/// that happens to still be mounted under a pushed route.
final pendingCommentaryNoteProvider =
    NotifierProvider<PendingCommentaryNote, CommentaryNoteAnchor?>(
      PendingCommentaryNote.new,
    );

class PendingCommentaryNote extends Notifier<CommentaryNoteAnchor?> {
  @override
  CommentaryNoteAnchor? build() => null;

  void set(CommentaryNoteAnchor anchor) => state = anchor;

  void consume() {
    if (state != null) state = null;
  }
}
