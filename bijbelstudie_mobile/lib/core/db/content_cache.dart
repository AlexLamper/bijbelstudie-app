import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// On-device cache of fetched chapters.
///
/// The corpus is ~355 MB on the server. It cannot ship inside the IPA and must
/// not be downloaded wholesale on first launch, so the unit of transfer — and
/// of caching — is one chapter. Rows are keyed `(kind, sourceId, book,
/// chapter)` and carry the server's `ETag`, which turns a re-read into a
/// conditional request that usually costs one empty 304.
///
/// Eviction is least-recently-used against a byte cap. `lastReadAt` is what
/// LRU sorts on, `fetchedAt` is when the bytes were last validated — a 304
/// refreshes the second without touching the first.
class ContentCache {
  static const _dbName = 'bijbelstudie_content.db';
  static const _dbVersion = 1;

  /// Default ceiling for cached chapter text. Roughly a few thousand chapters.
  static const int defaultMaxBytes = 300 * 1024 * 1024;

  Database? _db;
  final int maxBytes;

  ContentCache({this.maxBytes = defaultMaxBytes});

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), _dbName);
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chapters (
            kind        TEXT    NOT NULL,
            source_id   TEXT    NOT NULL,
            book        TEXT    NOT NULL,
            chapter     INTEGER NOT NULL,
            payload     TEXT    NOT NULL,
            etag        TEXT,
            bytes       INTEGER NOT NULL,
            fetched_at  INTEGER NOT NULL,
            last_read_at INTEGER NOT NULL,
            pinned      INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (kind, source_id, book, chapter)
          )
        ''');
        await db.execute('CREATE INDEX idx_chapters_lru ON chapters (pinned, last_read_at)');
        await db.execute('''
          CREATE TABLE search_history (
            query      TEXT PRIMARY KEY,
            searched_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_changes (
            client_id  TEXT    NOT NULL,
            kind       TEXT    NOT NULL,
            payload    TEXT,
            deleted    INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (kind, client_id)
          )
        ''');
      },
    );
    return _db!;
  }

  // --- offline write queue --------------------------------------------------

  /// Queues a note/highlight/bookmark/history write that could not reach the
  /// server. Keyed on (kind, client_id) and replaced on conflict, so editing
  /// the same note five times offline leaves one row holding the latest state,
  /// not five conflicting ones.
  Future<void> enqueueChange({
    required String kind,
    required String clientId,
    Map<String, dynamic>? payload,
    bool deleted = false,
  }) async {
    final db = await _open();
    await db.insert('pending_changes', {
      'client_id': clientId,
      'kind': kind,
      'payload': payload == null ? null : jsonEncode(payload),
      'deleted': deleted ? 1 : 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Pending writes in the shape `POST /api/v1/sync` expects.
  Future<List<Map<String, dynamic>>> pendingChanges() async {
    final db = await _open();
    final rows = await db.query('pending_changes', orderBy: 'updated_at ASC');
    return rows.map((row) {
      final updatedAt =
          DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int).toUtc().toIso8601String();
      final deleted = (row['deleted'] as int) == 1;
      return <String, dynamic>{
        'id': row['client_id'],
        'kind': row['kind'],
        'updatedAt': updatedAt,
        if (deleted) 'deletedAt': updatedAt,
        if (!deleted && row['payload'] != null)
          'data': jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      };
    }).toList();
  }

  Future<int> pendingChangeCount() async {
    final db = await _open();
    final result = await db.rawQuery('SELECT COUNT(*) AS n FROM pending_changes');
    return (result.first['n'] as num).toInt();
  }

  Future<void> clearPendingChanges(Iterable<String> clientIds) async {
    if (clientIds.isEmpty) return;
    final db = await _open();
    final batch = db.batch();
    for (final id in clientIds) {
      batch.delete('pending_changes', where: 'client_id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<CachedChapter?> read({
    required String kind,
    required String sourceId,
    required String book,
    required int chapter,
  }) async {
    final db = await _open();
    final rows = await db.query(
      'chapters',
      where: 'kind = ? AND source_id = ? AND book = ? AND chapter = ?',
      whereArgs: [kind, sourceId, book, chapter],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    // Touch the LRU timestamp, but do not await it — a read must not block on
    // a bookkeeping write.
    unawaited(
      db.update(
        'chapters',
        {'last_read_at': DateTime.now().millisecondsSinceEpoch},
        where: 'kind = ? AND source_id = ? AND book = ? AND chapter = ?',
        whereArgs: [kind, sourceId, book, chapter],
      ),
    );

    try {
      return CachedChapter(
        payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        etag: row['etag'] as String?,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(row['fetched_at'] as int),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write({
    required String kind,
    required String sourceId,
    required String book,
    required int chapter,
    required Map<String, dynamic> payload,
    String? etag,
    bool pinned = false,
  }) async {
    final db = await _open();
    final encoded = jsonEncode(payload);
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert('chapters', {
      'kind': kind,
      'source_id': sourceId,
      'book': book,
      'chapter': chapter,
      'payload': encoded,
      'etag': etag,
      'bytes': encoded.length,
      'fetched_at': now,
      'last_read_at': now,
      'pinned': pinned ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    unawaited(evictIfNeeded());
  }

  /// A 304 means the bytes are still current. Only the validation time moves.
  Future<void> touchFetchedAt({
    required String kind,
    required String sourceId,
    required String book,
    required int chapter,
  }) async {
    final db = await _open();
    await db.update(
      'chapters',
      {'fetched_at': DateTime.now().millisecondsSinceEpoch},
      where: 'kind = ? AND source_id = ? AND book = ? AND chapter = ?',
      whereArgs: [kind, sourceId, book, chapter],
    );
  }

  Future<int> totalBytes() async {
    final db = await _open();
    final result = await db.rawQuery('SELECT COALESCE(SUM(bytes), 0) AS total FROM chapters');
    return (result.first['total'] as num).toInt();
  }

  Future<int> chapterCount() async {
    final db = await _open();
    final result = await db.rawQuery('SELECT COUNT(*) AS n FROM chapters');
    return (result.first['n'] as num).toInt();
  }

  /// Drops least-recently-read chapters until the cache fits again.
  ///
  /// Chapters the user explicitly downloaded ("Bewaar dit boek offline") are
  /// pinned and evicted last — deleting them would silently break the offline
  /// promise the download button made.
  Future<void> evictIfNeeded() async {
    final db = await _open();
    var total = await totalBytes();
    if (total <= maxBytes) return;

    final candidates = await db.query(
      'chapters',
      columns: ['kind', 'source_id', 'book', 'chapter', 'bytes'],
      orderBy: 'pinned ASC, last_read_at ASC',
    );

    final batch = db.batch();
    for (final row in candidates) {
      if (total <= maxBytes) break;
      batch.delete(
        'chapters',
        where: 'kind = ? AND source_id = ? AND book = ? AND chapter = ?',
        whereArgs: [row['kind'], row['source_id'], row['book'], row['chapter']],
      );
      total -= (row['bytes'] as num).toInt();
    }
    await batch.commit(noResult: true);
  }

  Future<void> clear() async {
    final db = await _open();
    await db.delete('chapters');
  }

  Future<void> setPinnedForBook({
    required String kind,
    required String sourceId,
    required String book,
    required bool pinned,
  }) async {
    final db = await _open();
    await db.update(
      'chapters',
      {'pinned': pinned ? 1 : 0},
      where: 'kind = ? AND source_id = ? AND book = ?',
      whereArgs: [kind, sourceId, book],
    );
  }

  Future<int> cachedChapterCountForBook({
    required String kind,
    required String sourceId,
    required String book,
  }) async {
    final db = await _open();
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM chapters WHERE kind = ? AND source_id = ? AND book = ?',
      [kind, sourceId, book],
    );
    return (result.first['n'] as num).toInt();
  }

  // --- search history -------------------------------------------------------

  Future<void> recordSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final db = await _open();
    await db.insert('search_history', {
      'query': trimmed,
      'searched_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<String>> recentSearches({int limit = 12}) async {
    final db = await _open();
    final rows = await db.query(
      'search_history',
      orderBy: 'searched_at DESC',
      limit: limit,
    );
    return rows.map((r) => r['query'] as String).toList();
  }

  Future<void> clearSearchHistory() async {
    final db = await _open();
    await db.delete('search_history');
  }
}

class CachedChapter {
  const CachedChapter({required this.payload, this.etag, required this.fetchedAt});

  final Map<String, dynamic> payload;
  final String? etag;
  final DateTime fetchedAt;
}

/// Web has no sqflite; the provider still resolves so widgets can be rendered
/// in a browser preview, but every call is a no-op miss.
final contentCacheProvider = Provider<ContentCache?>((ref) {
  if (kIsWeb) return null;
  return ContentCache();
});
