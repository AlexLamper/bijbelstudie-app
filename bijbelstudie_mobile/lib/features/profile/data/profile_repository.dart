import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';
import 'profile_model.dart';

final profileRepositoryProvider = Provider((ref) {
  return ProfileRepository(ref.watch(apiClientProvider));
});

class ProfileRepository {
  final ApiClient _apiClient;

  ProfileRepository(this._apiClient);

  Future<ProfileModel> getProfile() async {
    try {
      final response = await _apiClient.dio.get('/me');
      final data = response.data as Map<String, dynamic>;
      return ProfileModel.fromJson(data);
    } on DioException catch (e) {
      throw Exception('Fout bij ophalen profiel: ${e.message}');
    }
  }

  Future<ProfileModel> updateProfile({String? name, ReadingPreferences? preferences}) async {
    final response = await _apiClient.dio.patch(
      '/me',
      data: {
        if (name != null) 'name': name,
        if (preferences != null) 'preferences': preferences.toJson(),
      },
    );
    return ProfileModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Forces the server to reconcile Pro with RevenueCat and returns the
  /// resulting flag.
  ///
  /// RevenueCat does not re-send a webhook for an already-owned purchase or a
  /// restore, so without this call Pro can stay locked on the server forever
  /// while the app's local CustomerInfo insists it is active. Returns null if
  /// the endpoint is unreachable, so callers can fall back to re-reading /me.
  Future<bool?> syncPremium() async {
    try {
      final response = await _apiClient.dio.post('/sync-premium');
      final data = response.data as Map<String, dynamic>;
      return data['isPro'] as bool? ?? false;
    } catch (_) {
      return null;
    }
  }

  /// Apple guideline 5.1.1(v): account deletion has to complete in-app.
  Future<void> deleteAccount() async {
    await _apiClient.dio.delete('/account', data: {'confirm': 'VERWIJDER'});
  }
}
