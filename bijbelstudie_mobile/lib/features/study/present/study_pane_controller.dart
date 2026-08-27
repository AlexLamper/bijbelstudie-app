import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which pane and which materials tab `/study` is showing.
///
/// This used to be `_StudyScreenState._showMaterials` plus a `TabController`
/// index, both private. That is the right shape for state only the screen
/// touches, and the wrong one the moment something outside the screen has to
/// put it in a particular state - which is exactly what the guided tour does
/// when it walks from the bible text to the commentary tabs.
///
/// Kept out of `study_screen.dart` so the tour does not have to import the
/// screen it is pointing at.
class StudyPaneState {
  const StudyPaneState({this.showMaterials = false, this.materialsTab = 0});

  /// False shows the reader, true shows Commentaar/Grondtekst/etc.
  final bool showMaterials;

  /// Index into the materials pane's five tabs.
  final int materialsTab;

  StudyPaneState copyWith({bool? showMaterials, int? materialsTab}) {
    return StudyPaneState(
      showMaterials: showMaterials ?? this.showMaterials,
      materialsTab: materialsTab ?? this.materialsTab,
    );
  }
}

final studyPaneProvider = NotifierProvider<StudyPaneController, StudyPaneState>(
  StudyPaneController.new,
);

class StudyPaneController extends Notifier<StudyPaneState> {
  @override
  StudyPaneState build() => const StudyPaneState();

  void showReader() => state = state.copyWith(showMaterials: false);

  void showMaterials() => state = state.copyWith(showMaterials: true);

  void setMaterialsTab(int index) => state = state.copyWith(materialsTab: index);

  /// Applies whichever of the two the caller cares about, leaving the rest
  /// alone. Both null is a no-op, so a tour step that says nothing about the
  /// panes leaves the reader where they were.
  void apply({bool? showMaterials, int? materialsTab}) {
    if (showMaterials == null && materialsTab == null) return;
    state = state.copyWith(showMaterials: showMaterials, materialsTab: materialsTab);
  }
}
