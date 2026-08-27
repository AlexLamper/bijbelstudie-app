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

/// Thrown when the server looked at a write and refused it - an expired
/// session, a validation error - rather than never receiving it. The offline
/// queue exists for connectivity trouble only: queueing a rejection like this
/// would just get it rejected again on every future flush, forever, with the
/// user never told their note was never saved. [message] is Dutch and ready
/// to put in a SnackBar.
class SyncRejectedException implements Exception {
  SyncRejectedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// True when [e] means the request never reached the server - a timeout, no
/// signal, DNS failure, a 5xx - so queuing it for later is the right call.
/// False means the server answered and said no, and replaying the same
/// payload later would only be rejected again.
bool _isRetryable(DioException e) {
  final status = e.response?.statusCode;
  return status == null || status >= 500;
}

String _rejectionMessage(DioException e, String action) {
  final status = e.response?.statusCode;
  if (status == 401 || status == 403) {
    return 'Je sessie is verlopen. Log opnieuw in.';
  }
  return 'Kon niet worden $action. Probeer het opnieuw.';
}

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

  Future<List<StudyNote>> listNotes() => _listNotes('/notes', kind: 'note');

  Future<List<StudyNote>> listHighlights() => _listNotes('/highlights', kind: 'highlight');

  Future<List<StudyNote>> _listNotes(String path, {required String kind}) async {
    final response = await _apiClient.dio.get(path);
    final data = response.data as Map<String, dynamic>;
    final byId = <String, StudyNote>{
      for (final raw in (data['items'] as List<dynamic>).whereType<Map<String, dynamic>>())
        raw['id'] as String: StudyNote.fromSyncRecord(raw),
    };

    // A note or highlight written while offline lives in the queue, not on
    // the server, until the next flush. Without this it is visible for
    // exactly as long as the dialog that created it, then disappears the
    // instant this list refetches.
    await _mergePending(byId, kind, StudyNote.fromSyncRecord);

    return byId.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
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
    } on DioException catch (e) {
      if (!_isRetryable(e)) throw SyncRejectedException(_rejectionMessage(e, 'opgeslagen'));
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
    } on DioException catch (e) {
      if (!_isRetryable(e)) throw SyncRejectedException(_rejectionMessage(e, 'verwijderd'));
      await _cache?.enqueueChange(kind: kind, clientId: note.id, deleted: true);
    }
  }

  Future<List<Bookmark>> listBookmarks() async {
    final response = await _apiClient.dio.get('/bookmarks');
    final data = response.data as Map<String, dynamic>;
    final byId = <String, Bookmark>{
      for (final raw in (data['items'] as List<dynamic>).whereType<Map<String, dynamic>>())
        raw['id'] as String: Bookmark.fromSyncRecord(raw),
    };

    await _mergePending(byId, 'bookmark', Bookmark.fromSyncRecord);

    return byId.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
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
    } on DioException catch (e) {
      if (!_isRetryable(e)) throw SyncRejectedException(_rejectionMessage(e, 'opgeslagen'));
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
    } on DioException catch (e) {
      if (!_isRetryable(e)) throw SyncRejectedException(_rejectionMessage(e, 'verwijderd'));
      await _cache?.enqueueChange(kind: 'bookmark', clientId: id, deleted: true);
    }
  }

  /// Folds queued-but-unsynced writes of [kind] into [byId], keyed the same
  /// way the server's own list is: the pending write wins over whatever the
  /// server still has (it is strictly newer, or the server would not still
  /// have the old value), and a queued delete removes whatever the server
  /// thinks still exists.
  Future<void> _mergePending<T>(
    Map<String, T> byId,
    String kind,
    T Function(Map<String, dynamic>) fromSyncRecord,
  ) async {
    final cache = _cache;
    if (cache == null) return;
    for (final change in await cache.pendingChanges(kind: kind)) {
      final id = change['id'] as String;
      if (change.containsKey('deletedAt')) {
        byId.remove(id);
      } else {
        byId[id] = fromSyncRecord(change);
      }
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
    } on DioException catch (e) {
      // No UI reads this write's result, so there is nothing to surface - but
      // a genuine rejection still should not be queued: it would just be
      // rejected again on every future flush.
      if (!_isRetryable(e)) return;
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
