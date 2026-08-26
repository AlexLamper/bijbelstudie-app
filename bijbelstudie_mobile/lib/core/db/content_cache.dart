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

    // Upsert rather than REPLACE, because the pin has to survive the write.
    // The ordinary read path fetches with `pinned: false`, so a REPLACE meant
    // that simply reading a chapter you had downloaded cleared its pin and
    // handed it back to the LRU - the download quietly stopped being a
    // download. `MAX(...)` keeps an existing pin and still lets a real
    // download set one.
    await db.rawInsert(
      '''
      INSERT INTO chapters
        (kind, source_id, book, chapter, payload, etag, bytes, fetched_at, last_read_at, pinned)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (kind, source_id, book, chapter) DO UPDATE SET
        payload      = excluded.payload,
        etag         = excluded.etag,
        bytes        = excluded.bytes,
        fetched_at   = excluded.fetched_at,
        last_read_at = excluded.last_read_at,
        pinned       = MAX(chapters.pinned, excluded.pinned)
      ''',
      [
        kind,
        sourceId,
        book,
        chapter,
        encoded,
        etag,
        utf8.encode(encoded).length,
        now,
        now,
        pinned ? 1 : 0,
      ],
    );

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

  /// Empties the read-through cache.
  ///
  /// Downloaded books are spared unless [includeDownloads] says otherwise. The
  /// settings screen tells the reader in as many words that what they chose to
  /// download stays; wiping those rows here would have made that a lie, and
  /// would have thrown away megabytes the user deliberately fetched to read
  /// somewhere with no signal.
  Future<void> clear({bool includeDownloads = false}) async {
    final db = await _open();
    await db.delete(
      'chapters',
      where: includeDownloads ? null : 'pinned = 0',
    );
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

  // --- what is actually on the device --------------------------------------

  /// Chapter numbers of one book that are readable with no network, ascending.
  ///
  /// This is the honest denominator for anything the UI says about a download:
  /// a row exists only if its payload is on disk, so a book that lost chapters
  /// to a failed request or to eviction reports the smaller number rather than
  /// keeping the label it was given on the day it was downloaded.
  Future<List<int>> cachedChaptersForBook({
    required String kind,
    required String sourceId,
    required String book,
  }) async {
    final db = await _open();
    final rows = await db.query(
      'chapters',
      columns: ['chapter'],
      where: 'kind = ? AND source_id = ? AND book = ?',
      whereArgs: [kind, sourceId, book],
      orderBy: 'chapter ASC',
    );
    return rows.map((r) => (r['chapter'] as num).toInt()).toList();
  }

  /// Books of one source with at least one chapter on disk.
  ///
  /// Ordering is left to the caller: the canon order lives in `BibleBooks` and
  /// this layer has no business knowing it.
  Future<List<String>> cachedBooks({
    required String kind,
    required String sourceId,
  }) async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT DISTINCT book FROM chapters WHERE kind = ? AND source_id = ?',
      [kind, sourceId],
    );
    return rows.map((r) => r['book'] as String).toList();
  }

  /// Every book holding at least one pinned chapter, newest download first.
  ///
  /// [OfflineBook.chapterCount] counts every cached chapter of the book and
  /// [OfflineBook.pinnedChapterCount] only the downloaded ones, because those
  /// two can differ: reading around a downloaded book adds unpinned chapters
  /// beside it.
  Future<List<OfflineBook>> downloadedBooks({String kind = 'bible'}) async {
    final db = await _open();
    final rows = await db.rawQuery(
      '''
      SELECT source_id, book,
             COUNT(*)                        AS chapters,
             SUM(pinned)                     AS pinned_chapters,
             COALESCE(SUM(bytes), 0)         AS bytes,
             MAX(fetched_at)                 AS fetched_at
      FROM chapters
      WHERE kind = ?
      GROUP BY source_id, book
      HAVING SUM(pinned) > 0
      ORDER BY fetched_at DESC
      ''',
      [kind],
    );
    return rows.map((row) {
      return OfflineBook(
        sourceId: row['source_id'] as String,
        book: row['book'] as String,
        chapterCount: (row['chapters'] as num).toInt(),
        pinnedChapterCount: (row['pinned_chapters'] as num).toInt(),
        bytes: (row['bytes'] as num).toInt(),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch((row['fetched_at'] as num).toInt()),
      );
    }).toList();
  }

  /// Deletes one book outright, pin and all. This is the "reclaim the space"
  /// half of a download and the only way to get those bytes back short of
  /// deleting the app.
  Future<int> removeBook({
    required String kind,
    required String sourceId,
    required String book,
  }) async {
    final db = await _open();
    return db.delete(
      'chapters',
      where: 'kind = ? AND source_id = ? AND book = ?',
      whereArgs: [kind, sourceId, book],
    );
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

/// One book with chapters stored on this device.
class OfflineBook {
  const OfflineBook({
    required this.sourceId,
    required this.book,
    required this.chapterCount,
    required this.pinnedChapterCount,
    required this.bytes,
    required this.fetchedAt,
  });

  final String sourceId;
  final String book;
  final int chapterCount;
  final int pinnedChapterCount;
  final int bytes;
  final DateTime fetchedAt;
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
