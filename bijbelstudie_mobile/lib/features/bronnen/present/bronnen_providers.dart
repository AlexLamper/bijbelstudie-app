import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/provider_cache.dart';
import '../../auth/present/auth_controller.dart' show apiClientProvider;
import '../data/bronnen_prefs.dart';
import '../data/bronnen_repository.dart';
import '../data/bronnen_store.dart';
import '../domain/bronnen_models.dart';

final bronnenStoreProvider = Provider<BronnenStore>((ref) => FileBronnenStore());

final bronnenRepositoryProvider = Provider((ref) {
  return BronnenRepository(
    ref.watch(apiClientProvider),
    ref.watch(bronnenStoreProvider),
  );
});

final bronnenIndexProvider = FutureProvider.autoDispose<BronnenIndex>((ref) {
  ref.cacheFor();
  return ref.watch(bronnenRepositoryProvider).getIndex();
});

/// One work in full. Asks the index for the current version first, so a
/// cached copy is used only while it is still current; without an index
/// (offline, first launch) any cached copy is served.
final bronWorkProvider = FutureProvider.autoDispose.family<BronWork, String>((
  ref,
  slug,
) async {
  ref.cacheFor();
  String? version;
  try {
    version = (await ref.watch(bronnenIndexProvider.future)).work(slug)?.version;
  } catch (_) {
    version = null;
  }
  return ref.watch(bronnenRepositoryProvider).getWork(slug, version: version);
});

/// The section id the reader was last on in a work, or null.
final bronPositionProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, slug) => BronnenPrefs.position(slug),
);

/// "Schriftteksten voluit": every reference opens with its verses.
final bronExpandAllProvider = NotifierProvider<BronExpandAll, bool>(
  BronExpandAll.new,
);

class BronExpandAll extends Notifier<bool> {
  bool _written = false;

  @override
  bool build() {
    unawaited(_load());
    return false;
  }

  Future<void> _load() async {
    final stored = await BronnenPrefs.expandAll();
    if (!ref.mounted || _written) return;
    if (stored != state) state = stored;
  }

  void set(bool value) {
    _written = true;
    state = value;
    unawaited(BronnenPrefs.setExpandAll(value));
  }
}
