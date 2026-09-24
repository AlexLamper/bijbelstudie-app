import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';

/// "Nodig een vriend uit": the same two endpoints the website's profile card
/// uses (`GET /api/v1/referral`, `POST /api/v1/referral/claim`), so web and
/// app never disagree about a code or its counts.
final referralRepositoryProvider = Provider((ref) {
  return ReferralRepository(ref.watch(apiClientProvider));
});

/// The account's own invite link and what came of it. Null when the server
/// does not have the endpoint (an older deployment), so the card simply stays
/// out of the way.
final referralOverviewProvider = FutureProvider.autoDispose<ReferralOverview?>((ref) {
  return ref.watch(referralRepositoryProvider).overview();
});

class ReferralOverview {
  const ReferralOverview({
    required this.code,
    required this.url,
    required this.shareText,
    required this.rewardDays,
    required this.joined,
    required this.active,
    required this.youEarn,
    required this.proUntil,
    required this.canClaim,
  });

  final String code;
  final String url;
  final String shareText;
  final int rewardDays;
  final int joined;
  final int active;
  final bool youEarn;
  final DateTime? proUntil;
  final bool canClaim;

  factory ReferralOverview.fromJson(Map<String, dynamic> json) {
    final claim = json['claim'];
    return ReferralOverview(
      code: json['code'] as String? ?? '',
      url: json['url'] as String? ?? '',
      shareText: json['shareText'] as String? ?? '',
      rewardDays: (json['rewardDays'] as num?)?.toInt() ?? 7,
      joined: (json['joined'] as num?)?.toInt() ?? 0,
      active: (json['active'] as num?)?.toInt() ?? 0,
      youEarn: json['youEarn'] as bool? ?? false,
      proUntil: DateTime.tryParse(json['proUntil'] as String? ?? '')?.toLocal(),
      canClaim: claim is Map && claim['eligible'] == true,
    );
  }
}

/// The answer to entering a code. [message] is Dutch and ready to show.
class ClaimOutcome {
  const ClaimOutcome({required this.ok, required this.message, this.proUntil});

  final bool ok;
  final String message;
  final DateTime? proUntil;
}

class ReferralRepository {
  ReferralRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<ReferralOverview?> overview() async {
    try {
      final response = await _apiClient.dio.get('/referral');
      final data = response.data;
      if (data is! Map<String, dynamic>) return null;
      final overview = ReferralOverview.fromJson(data);
      return overview.code.isEmpty ? null : overview;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<ClaimOutcome> claim(String code) async {
    try {
      final response = await _apiClient.dio.post('/referral/claim', data: {'code': code});
      final data = response.data as Map<String, dynamic>? ?? const {};
      return ClaimOutcome(
        ok: true,
        message: 'Je week Pro is gestart.',
        proUntil: DateTime.tryParse(data['proUntil'] as String? ?? '')?.toLocal(),
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      final message = data is Map && data['message'] is String
          ? data['message'] as String
          : 'Dat lukte niet. Probeer het later opnieuw.';
      return ClaimOutcome(ok: false, message: message);
    }
  }
}
