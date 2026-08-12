import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';

final groupsRepositoryProvider = Provider((ref) {
  return GroupsRepository(ref.watch(apiClientProvider));
});

class StudyGroup {
  const StudyGroup({
    required this.id,
    required this.name,
    required this.description,
    required this.isPublic,
    required this.memberCount,
    required this.isMember,
    required this.isLeader,
    this.inviteCode,
    this.assignment,
  });

  final String id;
  final String name;
  final String description;
  final bool isPublic;
  final int memberCount;
  final bool isMember;
  final bool isLeader;

  /// Only ever populated for members — it is a credential.
  final String? inviteCode;

  final String? assignment;

  factory StudyGroup.fromJson(Map<String, dynamic> json) {
    final weekly = json['weeklyAssignment'] as Map<String, dynamic>?;
    return StudyGroup(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      isPublic: json['isPublic'] as bool? ?? true,
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      isMember: json['isMember'] as bool? ?? false,
      isLeader: json['isLeader'] as bool? ?? false,
      inviteCode: json['inviteCode'] as String?,
      assignment: weekly == null || weekly['book'] == null
          ? null
          : '${weekly['book']} ${weekly['chapter'] ?? ''}'.trim(),
    );
  }
}

class GroupMember {
  const GroupMember({
    required this.userId,
    required this.name,
    required this.role,
    required this.isSelf,
    this.image,
  });

  final String userId;
  final String name;
  final String role;
  final bool isSelf;
  final String? image;

  bool get isLeader => role == 'leader';

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: json['userId'] as String? ?? '',
      name: json['name'] as String? ?? 'Onbekend',
      role: json['role'] as String? ?? 'member',
      isSelf: json['isSelf'] as bool? ?? false,
      image: json['image'] as String?,
    );
  }
}

class GroupMessage {
  const GroupMessage({
    required this.id,
    required this.type,
    required this.content,
    required this.authorName,
    required this.isSelf,
    required this.createdAt,
    this.authorImage,
  });

  /// `bericht`, `gebedsverzoek` or `aankondiging`.
  final String type;

  final String id;
  final String content;
  final String authorName;
  final bool isSelf;
  final DateTime createdAt;
  final String? authorImage;

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    return GroupMessage(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'bericht',
      content: json['content'] as String? ?? '',
      authorName: json['authorName'] as String? ?? 'Onbekend',
      isSelf: json['isSelf'] as bool? ?? false,
      authorImage: json['authorImage'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class GroupDetail {
  const GroupDetail({required this.group, required this.members});

  final StudyGroup group;
  final List<GroupMember> members;
}

class GroupsRepository {
  GroupsRepository(this._apiClient);

  final ApiClient _apiClient;

  /// `type` is `mine`, `public`, or null for both.
  Future<List<StudyGroup>> listGroups({String? type}) async {
    try {
      final response = await _apiClient.dio.get(
        '/groups',
        queryParameters: {if (type != null) 'type': type},
      );
      final data = response.data as Map<String, dynamic>;
      return (data['groups'] as List? ?? const [])
          .map((g) => StudyGroup.fromJson(g as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw Exception('Fout bij ophalen groepen: ${e.message}');
    }
  }

  Future<GroupDetail> getGroup(String id) async {
    final response = await _apiClient.dio.get('/groups/$id');
    final data = response.data as Map<String, dynamic>;
    return GroupDetail(
      group: StudyGroup.fromJson(data['group'] as Map<String, dynamic>),
      members: (data['members'] as List? ?? const [])
          .map((m) => GroupMember.fromJson(m as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Future<List<GroupMessage>> listMessages(String groupId) async {
    final response = await _apiClient.dio.get('/groups/$groupId/messages');
    final data = response.data as Map<String, dynamic>;
    return (data['messages'] as List? ?? const [])
        .map((m) => GroupMessage.fromJson(m as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<GroupMessage> postMessage(
    String groupId,
    String content, {
    String type = 'bericht',
  }) async {
    final response = await _apiClient.dio.post(
      '/groups/$groupId/messages',
      data: {'content': content, 'type': type},
    );
    final data = response.data as Map<String, dynamic>;
    return GroupMessage.fromJson(data['message'] as Map<String, dynamic>);
  }

  Future<StudyGroup> createGroup({
    required String name,
    String description = '',
    bool isPublic = true,
  }) async {
    final response = await _apiClient.dio.post(
      '/groups',
      data: {'name': name, 'description': description, 'isPublic': isPublic},
    );
    final data = response.data as Map<String, dynamic>;
    return StudyGroup.fromJson(data['group'] as Map<String, dynamic>);
  }

  /// Joins a group. A private group needs its invite code; the server is the
  /// one that checks it.
  Future<String?> join(String groupId, {String? inviteCode}) async {
    try {
      await _apiClient.dio.post(
        '/groups/$groupId/membership',
        data: {if (inviteCode != null) 'inviteCode': inviteCode},
      );
      return null;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] == 'INVALID_INVITE_CODE') {
        return 'Die uitnodigingscode klopt niet.';
      }
      if (data is Map && data['message'] is String) return data['message'] as String;
      return 'Deelnemen mislukt. Probeer het opnieuw.';
    }
  }

  Future<String?> leave(String groupId) async {
    try {
      await _apiClient.dio.delete('/groups/$groupId/membership');
      return null;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
      return 'Verlaten mislukt. Probeer het opnieuw.';
    }
  }
}

final groupsProvider =
    FutureProvider.autoDispose.family<List<StudyGroup>, String?>((ref, type) {
      return ref.watch(groupsRepositoryProvider).listGroups(type: type);
    });

final groupDetailProvider =
    FutureProvider.autoDispose.family<GroupDetail, String>((ref, id) {
      return ref.watch(groupsRepositoryProvider).getGroup(id);
    });

final groupMessagesProvider =
    FutureProvider.autoDispose.family<List<GroupMessage>, String>((ref, id) {
      return ref.watch(groupsRepositoryProvider).listMessages(id);
    });
