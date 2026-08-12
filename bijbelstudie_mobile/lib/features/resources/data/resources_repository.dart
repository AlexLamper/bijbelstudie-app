import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';

final resourcesRepositoryProvider = Provider((ref) {
  return ResourcesRepository(ref.watch(apiClientProvider));
});

class ResourceCategory {
  const ResourceCategory({
    required this.id,
    required this.label,
    required this.color,
  });

  final String id;
  final String label;

  /// The site stores these as CSS hex strings, e.g. `#0D9488`.
  final String color;

  factory ResourceCategory.fromJson(Map<String, dynamic> json) {
    return ResourceCategory(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      color: json['color'] as String? ?? '#0D9488',
    );
  }
}

class ResourceItem {
  const ResourceItem({
    required this.slug,
    required this.title,
    required this.description,
    required this.category,
    required this.source,
    required this.sourceUrl,
    required this.rightsNote,
    required this.locked,
    this.author,
    this.year,
  });

  final String slug;
  final String title;
  final String description;
  final String category;
  final String source;
  final String sourceUrl;
  final String rightsNote;

  /// Resolved server-side from the caller's Pro status.
  final bool locked;

  final String? author;
  final String? year;

  String get byline => [
    if (author != null && author!.isNotEmpty) author!,
    if (year != null && year!.isNotEmpty) year!,
  ].join(' · ');

  factory ResourceItem.fromJson(Map<String, dynamic> json) {
    return ResourceItem(
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? '',
      source: json['source'] as String? ?? '',
      sourceUrl: json['sourceUrl'] as String? ?? '',
      rightsNote: json['rightsNote'] as String? ?? '',
      locked: json['locked'] as bool? ?? false,
      author: json['author'] as String?,
      year: json['year'] as String?,
    );
  }
}

class ResourceLibrary {
  const ResourceLibrary({required this.categories, required this.items});

  final List<ResourceCategory> categories;
  final List<ResourceItem> items;
}

class ResourcesRepository {
  ResourcesRepository(this._apiClient);

  final ApiClient _apiClient;

  /// The Hulpbronnen library. Every entry lives on a third-party archive, so
  /// the app links out — it mirrors nothing.
  Future<ResourceLibrary> getLibrary() async {
    try {
      final response = await _apiClient.dio.get('/resources');
      final data = response.data as Map<String, dynamic>;
      return ResourceLibrary(
        categories: (data['categories'] as List? ?? const [])
            .map((c) => ResourceCategory.fromJson(c as Map<String, dynamic>))
            .toList(growable: false),
        items: (data['items'] as List? ?? const [])
            .map((i) => ResourceItem.fromJson(i as Map<String, dynamic>))
            .toList(growable: false),
      );
    } on DioException catch (e) {
      throw Exception('Fout bij ophalen hulpbronnen: ${e.message}');
    }
  }
}

final resourceLibraryProvider = FutureProvider.autoDispose<ResourceLibrary>((ref) {
  return ref.watch(resourcesRepositoryProvider).getLibrary();
});
