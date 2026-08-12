import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/db/content_cache.dart';
import '../../auth/present/auth_controller.dart';
import '../domain/note_models.dart';

final notesRepositoryProvider = Provider((ref) {
  return NotesRepository(ref.watch(apiClientProvider), ref.watch(contentCacheProvider));
});

const _uuid = Uuid();

String newClientId() => _uuid.v4();

/// Notes, highlights, bookmarks and reading positions.
///
/// Writes are offline-tolerant: the client id is generated on the device, so a
/// write that cannot reach the server is queued in SQLite and replayed through
/// `POST /api/v1/sync` on the next successful call. Because the id travels with
/// the record, replaying it is an upsert, never a duplicate.
class NotesRepository {
  NotesRepository(this._apiClient, this._cache);

  final ApiClient _apiClient;
  final ContentCache? _cache;

  Future<List<StudyNote>> listNotes() => _listNotes('/notes');

  Future<List<StudyNote>> listHighlights() => _listNotes('/highlights');

  Future<List<StudyNote>> _listNotes(String path) async {
    final response = await _apiClient.dio.get(path);
    final data = response.data as Map<String, dynamic>;
    return (data['items'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(StudyNote.fromSyncRecord)
        .toList();
  }

  Future<StudyNote> saveNote(StudyNote note) async {
    final kind = note.isHighlight ? 'highlight' : 'note';
    final path = note.isHighlight ? '/highlights' : '/notes';
    try {
      final response = await _apiClient.dio.post(
        path,
        data: {'id': note.id, 'data': note.toRequestData()},
      );
      final item = (response.data as Map<String, dynamic>)['item'] as Map<String, dynamic>;
      unawaitedFlush();
      return StudyNote.fromSyncRecord(item);
    } on DioException {
      await _cache?.enqueueChange(
        kind: kind,
        clientId: note.id,
        payload: note.toRequestData(),
      );
      // The caller gets the note it just wrote; the server catches up later.
      return note;
    }
  }

  Future<void> deleteNote(StudyNote note) async {
    final kind = note.isHighlight ? 'highlight' : 'note';
    final path = note.isHighlight ? '/highlights' : '/notes';
    try {
      await _apiClient.dio.delete('$path/${note.id}');
      unawaitedFlush();
    } on DioException {
      await _cache?.enqueueChange(kind: kind, clientId: note.id, deleted: true);
    }
  }

  Future<List<Bookmark>> listBookmarks() async {
    final response = await _apiClient.dio.get('/bookmarks');
    final data = response.data as Map<String, dynamic>;
    return (data['items'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(Bookmark.fromSyncRecord)
        .toList();
  }

  Future<Bookmark> saveBookmark(Bookmark bookmark) async {
    try {
      final response = await _apiClient.dio.post(
        '/bookmarks',
        data: {'id': bookmark.id, 'data': bookmark.toRequestData()},
      );
      final item = (response.data as Map<String, dynamic>)['item'] as Map<String, dynamic>;
      unawaitedFlush();
      return Bookmark.fromSyncRecord(item);
    } on DioException {
      await _cache?.enqueueChange(
        kind: 'bookmark',
        clientId: bookmark.id,
        payload: bookmark.toRequestData(),
      );
      return bookmark;
    }
  }

  Future<void> deleteBookmark(String id) async {
    try {
      await _apiClient.dio.delete('/bookmarks/$id');
      unawaitedFlush();
    } on DioException {
      await _cache?.enqueueChange(kind: 'bookmark', clientId: id, deleted: true);
    }
  }

  Future<List<ReadingPosition>> listReadingHistory() async {
    final response = await _apiClient.dio.get('/reading-history');
    final data = response.data as Map<String, dynamic>;
    return (data['items'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(ReadingPosition.fromSyncRecord)
        .toList();
  }

  /// Records where the reader stopped.
  ///
  /// One record per (version, book, chapter): the id is derived from the
  /// reference rather than random, so revisiting a chapter updates the existing
  /// row instead of piling up a new one on every scroll.
  Future<void> recordReadingPosition({
    required String version,
    required String book,
    required int chapter,
    required double scrollProgress,
  }) async {
    final id = _uuid.v5(Namespace.url.value, 'bijbelstudie:$version:$book:$chapter');
    final position = ReadingPosition(
      id: id,
      book: book,
      chapter: chapter,
      version: version,
      scrollProgress: scrollProgress,
      readAt: DateTime.now(),
    );
    final body = {
      'id': position.id,
      // Always newer than what is stored, so last-write-wins accepts it.
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'data': position.toRequestData(),
    };

    try {
      await _apiClient.dio.post('/reading-history', data: body);
    } on DioException {
      await _cache?.enqueueChange(
        kind: 'reading-history',
        clientId: position.id,
        payload: position.toRequestData(),
      );
    }
  }

  /// Replays everything queued while offline. Safe to call often — it returns
  /// immediately when the queue is empty.
  Future<int> flushPendingChanges() async {
    final cache = _cache;
    if (cache == null) return 0;

    final pending = await cache.pendingChanges();
    if (pending.isEmpty) return 0;

    try {
      final response = await _apiClient.dio.post('/sync', data: {'changes': pending});
      final data = response.data as Map<String, dynamic>;
      final rejected = (data['rejected'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((r) => r['id'] as String?)
          .whereType<String>()
          .toSet();

      // A rejected change is not a retryable failure: STALE means the server
      // already has something newer and DELETED means the row is gone for good.
      // Both are settled, so they leave the queue with the applied ones.
      await cache.clearPendingChanges(pending.map((c) => c['id'] as String));
      return pending.length - rejected.length;
    } on DioException {
      // Still offline. Leave the queue alone and try again next time.
      return 0;
    }
  }

  /// Fire-and-forget flush after a successful call — the connection is known
  /// good at that moment, which is the cheapest possible trigger.
  void unawaitedFlush() {
    flushPendingChanges().catchError((_) => 0);
  }
}
