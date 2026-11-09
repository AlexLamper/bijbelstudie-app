import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';

/// What `POST /api/v1/allowance` answers: may the reader open this Pro thing
/// the server never serves itself (a music track, an offline download)?
///  - `pro`: yes, and during the reverse trial it was counted;
///  - `allowance`: their personal limit; [allowed] says whether today's slot
///    was free (website and app share it);
///  - `free`: the normal free rule applies - for music and offline that is
///    "Pro only".
class AllowanceAnswer {
  const AllowanceAnswer({required this.allowed, required this.mode, this.message});

  final bool allowed;
  final String mode;
  final String? message;

  bool get personal => mode == 'allowance';

  factory AllowanceAnswer.fromJson(Map<String, dynamic> json) => AllowanceAnswer(
        allowed: json['allowed'] == true,
        mode: json['mode'] as String? ?? 'free',
        message: json['message'] as String?,
      );
}

/// The recap's extras that `/api/v1/me` does not carry.
class TrialRecapData {
  const TrialRecapData({required this.streak});

  final int streak;
}

/// The reverse trial's own endpoints (website `app/api/v1/reverse-trial`,
/// `app/api/v1/allowance`). Everything here is best effort: a failed call
/// never blocks reading, it only means a count or a slot is decided later.
class ReverseTrialRepository {
  ReverseTrialRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<TrialRecapData?> recapData() async {
    try {
      final response = await _apiClient.dio.get('/reverse-trial');
      final data = response.data;
      if (data is! Map<String, dynamic>) return null;
      return TrialRecapData(streak: (data['streak'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return null;
    }
  }

  /// The recap was shown: the website will not show it again either.
  Future<void> markRecapSeen(String platform) async {
    try {
      await _apiClient.dio.post('/reverse-trial', data: {'action': 'recap_seen', 'platform': platform});
    } catch (_) {}
  }

  /// "Je hebt 3 dagen Pro gekregen" was shown: the website will not show it again.
  Future<void> markAnnounceSeen(String platform) async {
    try {
      await _apiClient.dio.post('/reverse-trial', data: {'action': 'announce_seen', 'platform': platform});
    } catch (_) {}
  }

  /// "I am about to open [kind]" (`music`, `offline`). Null when the server
  /// could not be asked - the caller then keeps to what it already knew.
  Future<AllowanceAnswer?> claim(String kind, {String? key}) async {
    try {
      final response = await _apiClient.dio.post('/allowance', data: {'kind': kind, if (key != null) 'key': key});
      final data = response.data;
      return data is Map<String, dynamic> ? AllowanceAnswer.fromJson(data) : null;
    } catch (_) {
      return null;
    }
  }
}

final reverseTrialRepositoryProvider = Provider<ReverseTrialRepository>((ref) {
  return ReverseTrialRepository(ref.watch(apiClientProvider));
});
