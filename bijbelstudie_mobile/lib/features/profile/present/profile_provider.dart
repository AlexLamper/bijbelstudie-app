import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/payload_cache.dart';
import '../../../core/data/provider_cache.dart';
import '../data/profile_model.dart';
import '../data/profile_repository.dart';

/// The Profiel tab's own request. Cached to disk like the dashboard's, so the
/// header renders the reader's name and plan on the first frame instead of
/// after a round trip.
class ProfileNotifier extends AsyncNotifier<ProfileModel> {
  static const _cacheKey = 'profile';

  @override
  Future<ProfileModel> build() async {
    ref.cacheFor();
    final repo = ref.watch(profileRepositoryProvider);

    final cached = await PayloadCache.read(_cacheKey);
    if (cached != null && state is AsyncLoading) {
      try {
        state = AsyncData(ProfileModel.fromJson(cached));
      } catch (_) {
        // Written by an older build; wait for the network instead.
      }
    }

    final profile = await repo.getProfile();
    unawaited(PayloadCache.write(_cacheKey, profile.raw));
    return profile;
  }
}

final profileProvider =
    AsyncNotifierProvider.autoDispose<ProfileNotifier, ProfileModel>(
      ProfileNotifier.new,
    );
