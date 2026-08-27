import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';

/// The subset of `GET /preferences` this app reads back.
///
/// The endpoint (`app/api/v1/preferences/route.ts` on the website) stores a
/// much larger preferences bag than this — translation, commentary, font
/// choices, reminder time — but the only thing the app needs to *read* is
/// whether setup and the tour were already completed elsewhere (the website,
/// or another device), so a returning user is never asked the same questions
/// twice.
class UserPreferences {
  const UserPreferences({
    required this.onboardingCompleted,
    required this.tourCompleted,
  });

  final bool onboardingCompleted;
  final bool tourCompleted;

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    final prefs = json['preferences'] as Map<String, dynamic>?;
    return UserPreferences(
      onboardingCompleted:
          json['onboardingCompleted'] as bool? ??
          prefs?['onboardingCompleted'] as bool? ??
          false,
      tourCompleted: prefs?['tourCompleted'] as bool? ?? false,
    );
  }
}

final preferencesRepositoryProvider = Provider<PreferencesRepository>((ref) {
  return PreferencesRepository(ref.watch(apiClientProvider));
});

/// Syncs onboarding/reading choices with the server so the website shows the
/// same picture. Best-effort by design (see call sites): a preference that
/// fails to sync still applies on-device via the reading settings controller,
/// it just does not show up on the website until the next successful sync.
class PreferencesRepository {
  PreferencesRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<UserPreferences> getPreferences() async {
    final response = await _apiClient.dio.get('/preferences');
    return UserPreferences.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> syncPreferences(Map<String, dynamic> patch) async {
    await _apiClient.dio.patch('/preferences', data: patch);
  }
}
