import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/provider_cache.dart';
import '../data/profile_model.dart';
import '../data/profile_repository.dart';

final profileProvider = FutureProvider.autoDispose<ProfileModel>((ref) async {
  ref.cacheFor();
  final repo = ref.watch(profileRepositoryProvider);
  return repo.getProfile();
});
