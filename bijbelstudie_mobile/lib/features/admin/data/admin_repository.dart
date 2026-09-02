import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';
import '../domain/admin_entities.dart';

final adminRepositoryProvider = Provider((ref) {
  return AdminRepository(ref.watch(apiClientProvider));
});

/// Thrown when the server refused an admin call. [message] is Dutch and ready
/// for a SnackBar or an error state.
///
/// [isForbidden] is the case worth separating: the account simply is not an
/// admin (or stopped being one). Retrying that is pointless, so the screen says
/// so instead of offering "probeer opnieuw".
class AdminException implements Exception {
  const AdminException(this.message, {this.isForbidden = false});

  final String message;
  final bool isForbidden;

  @override
  String toString() => message;
}

/// The admin surface: the same figures the website's `/admin` renders, read
/// through the app's bearer-authenticated `/api/v1/admin/*` routes.
///
/// The server re-checks admin rights on every one of these calls. Hiding the
/// screen from non-admins in the UI is a convenience; this repository will get
/// a 403 either way if the account is not an admin.
class AdminRepository {
  AdminRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<AdminStats> getStats() async {
    try {
      final response = await _apiClient.dio.get('/admin/stats');
      return AdminStats.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _describe(e, 'statistieken');
    }
  }

  /// [days] is 7, 30 or 90 on this screen; the server clamps to 7...365.
  Future<AdminInsights> getInsights({int days = 30}) async {
    try {
      final response = await _apiClient.dio.get(
        '/admin/insights',
        queryParameters: {'days': days},
      );
      return AdminInsights.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _describe(e, 'inzichten');
    }
  }

  /// [search] filters on name and email server-side; the screen also filters
  /// the loaded page locally so typing stays instant.
  Future<List<AdminAccount>> getUsers({String? search, int limit = 500}) async {
    try {
      final response = await _apiClient.dio.get(
        '/admin/users',
        queryParameters: {
          'limit': limit,
          if (search != null && search.trim().isNotEmpty) 'q': search.trim(),
        },
      );
      final data = response.data as Map<String, dynamic>;
      return ((data['users'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AdminAccount.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw _describe(e, 'gebruikers');
    }
  }

  /// Flips one of the two flags an admin may set by hand. Anything else in the
  /// body is ignored by the server.
  Future<void> updateUser(String id, {bool? isAdmin, bool? subscribed}) async {
    try {
      await _apiClient.dio.patch(
        '/admin/users/$id',
        data: {
          if (isAdmin != null) 'isAdmin': isAdmin,
          if (subscribed != null) 'subscribed': subscribed,
        },
      );
    } on DioException catch (e) {
      throw _describe(e, 'wijziging', fallback: 'Bijwerken mislukt.');
    }
  }

  /// Permanently removes the account and its notes.
  Future<void> deleteUser(String id) async {
    try {
      await _apiClient.dio.delete('/admin/users/$id');
    } on DioException catch (e) {
      throw _describe(e, 'account', fallback: 'Verwijderen mislukt.');
    }
  }

  /// Turns a Dio failure into something an admin can act on. The server's own
  /// message is preferred when it sent one — on this screen the reader is the
  /// person who can do something about it.
  AdminException _describe(DioException e, String subject, {String? fallback}) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final detail = data is Map<String, dynamic>
        ? (data['message'] as String?) ?? (data['error'] as String?)
        : null;

    if (status == null) {
      return AdminException(
        'De server is niet bereikbaar. Controleer je verbinding en probeer '
        'het opnieuw.',
      );
    }
    if (status == 401) {
      return const AdminException(
        'Je bent niet (meer) ingelogd. Log opnieuw in.',
      );
    }
    if (status == 403) {
      return const AdminException(
        'Dit account heeft geen beheerdersrechten.',
        isForbidden: true,
      );
    }
    if (status == 503) {
      return AdminException(
        'De database is nu niet bereikbaar. Dit ligt niet aan je verbinding.'
        '${detail == null ? '' : ' ($detail)'}',
      );
    }
    if (status >= 500) {
      return AdminException(
        'Serverfout $status bij het laden van $subject. De oorzaak staat in '
        'de serverlogs.${detail == null ? '' : ' ($detail)'}',
      );
    }
    return AdminException(
      detail ?? fallback ?? 'Kon $subject niet laden ($status).',
    );
  }
}
