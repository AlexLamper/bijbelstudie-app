import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/data/account_scope.dart';
import '../../../core/db/content_cache.dart';
import '../../auth/present/auth_controller.dart';
import '../../levensboom/domain/tree_state.dart';
import '../../levensboom/present/levensboom_providers.dart';
import '../domain/note_models.dart';
import '../present/notes_providers.dart';

final notesRepositoryProvider = Provider((ref) {
  return NotesRepository(
    ref.watch(apiClientProvider),
    ref.watch(contentCacheProvider),
    onXp: (xp) => ref.read(treeAnimationEventProvider.notifier).push(xp),
    onSyncRejected: (rejection) =>
        ref.read(syncRejectionProvider.notifier).push(rejection),
    account: () => AccountScope.resolve(ref.read(sessionAccountProvider)),
  );
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
  SyncRejectedException(this.message, {this.proRequired = false});

  final String message;

  /// The server refused a new note because the free note limit is reached
  /// (`NOTE_LIMIT_REACHED`, the same limit the website enforces). The caller
  /// offers Pro instead of "try again", which would only be refused again.
  final bool proRequired;

  @override
  String toString() => message;
}

/// Wording for the free note limit when the response carries none of its own.
///
/// `POST /notes` answers with the server's `NOTE_LIMIT_MESSAGE`, which names
/// the number, and that is preferred wherever it is present. `POST /sync`
/// rejects per change with `{id, reason}` only - no message - so a limit
/// rejection coming back from a flush has nothing else to show.
const kNoteLimitMessage =
    'Je hebt je gratis notities gebruikt. Met Pro schrijf je onbeperkt notities.';

/// Where [NotesRepository] reports a refusal nobody is awaiting: the offline
/// queue's flush runs fire-and-forget ([NotesRepository.unawaitedFlush]), so
/// there is no `try`/`catch` and no screen context at the moment `/sync` says
/// no. Injected like [XpSink] to keep the data layer ignorant of Riverpod; a
/// null sink (tests, preview mode) is a no-op.
typedef SyncRejectionSink = void Function(SyncRejectedException rejection);

/// What one flush of the offline queue settled.
///
/// [applied] is the count callers used to get back on its own. [limitRejection]
/// is the one rejection the reader has to be told about: `/sync` refusing a
/// queued note with `NOTE_LIMIT_REACHED`. That cannot be seen at write time -
/// the server never answered, which is why the note was queued - so without
/// this the note appeared in Notities and then vanished on the next refetch
/// with nothing said.
class FlushResult {
  const FlushResult({required this.applied, this.limitRejection});

  final int applied;

  /// The free-note-limit refusal, ready for the same SnackBar and "Bekijk Pro"
  /// action a refused single write gets. Null for `STALE` and `DELETED`, which
  /// are settled and stay silent.
  final SyncRejectedException? limitRejection;
}

/// True when [e] means the request never reached the server - a timeout, no
/// signal, DNS failure, a 5xx - so queuing it for later is the right call.
/// False means the server answered and said no, and replaying the same
/// payload later would only be rejected again.
bool _isRetryable(DioException e) {
  final status = e.response?.statusCode;
  return status == null || status >= 500;
}

/// The exception for a write the server refused. The free note limit carries
/// the server's own Dutch message (which names the number) and asks for the
/// Pro offer; every other refusal keeps the generic wording.
SyncRejectedException _rejection(DioException e, String action) {
  final data = e.response?.data;
  if (data is Map && data['error'] == 'NOTE_LIMIT_REACHED') {
    final message = data['message'];
    return SyncRejectedException(
      message is String && message.isNotEmpty ? message : kNoteLimitMessage,
      proRequired: true,
    );
  }
  return SyncRejectedException(_rejectionMessage(e, action));
}

/// The free-note-limit entry in `/sync`'s `rejected` list, as the same
/// exception a refused single write throws, or null when every rejection was a
/// settled `STALE`/`DELETED`.
///
/// The server sends `{id, reason}` per rejected change (`SKIP_REASON` in
/// `app/api/v1/sync/route.ts`); `message` is read anyway so a future server
/// that does send one wins over [kNoteLimitMessage].
SyncRejectedException? _limitRejection(Iterable<Map<String, dynamic>> rejected) {
  for (final entry in rejected) {
    if (entry['reason'] != 'NOTE_LIMIT_REACHED') continue;
    final message = entry['message'];
    return SyncRejectedException(
      message is String && message.isNotEmpty ? message : kNoteLimitMessage,
      proRequired: true,
    );
  }
  return null;
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
  NotesRepository(
    this._apiClient,
    this._cache, {
    XpSink? onXp,
    SyncRejectionSink? onSyncRejected,
    Future<String?> Function()? account,
  }) : _onXp = onXp,
       _onSyncRejected = onSyncRejected,
       _account = account;

  final ApiClient _apiClient;
  final ContentCache? _cache;

  /// Forwards the `xp` a new note earned to the Levensboom. See [XpSink].
  /// Private so the test fakes that `implements` this class need not declare it.
  final XpSink? _onXp;

  /// Forwards a refusal from the offline queue's flush to the UI. See
  /// [SyncRejectionSink].
  final SyncRejectionSink? _onSyncRejected;

  /// The signed-in account (or the last one, on an offline launch). The offline
  /// queue is tagged with it, and a flush only replays that account's writes:
  /// another reader's stay queued until they sign in again. Null before any
  /// sign-in, which tags and replays the untagged rows.
  final Future<String?> Function()? _account;

  Future<String?> _accountId() async => _account == null ? null : await _account();

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
      final data = response.data as Map<String, dynamic>;
      final item = data['item'] as Map<String, dynamic>;
      // Null for a highlight, an edit, a stub, or the fourth note of the day -
      // the guardrails live server-side in lib/noteXp.ts.
      _onXp?.call(data['xp']);
      unawaitedFlush();
      return StudyNote.fromSyncRecord(item);
    } on DioException catch (e) {
      if (!_isRetryable(e)) throw _rejection(e, 'opgeslagen');
      await _cache?.enqueueChange(
        kind: kind,
        clientId: note.id,
        payload: note.toRequestData(),
        account: await _accountId(),
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
      if (!_isRetryable(e)) throw _rejection(e, 'verwijderd');
      await _cache?.enqueueChange(
        kind: kind,
        clientId: note.id,
        deleted: true,
        account: await _accountId(),
      );
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
      if (!_isRetryable(e)) throw _rejection(e, 'opgeslagen');
      await _cache?.enqueueChange(
        kind: 'bookmark',
        clientId: bookmark.id,
        payload: bookmark.toRequestData(),
        account: await _accountId(),
      );
      return bookmark;
    }
  }

  Future<void> deleteBookmark(String id) async {
    try {
      await _apiClient.dio.delete('/bookmarks/$id');
      unawaitedFlush();
    } on DioException catch (e) {
      if (!_isRetryable(e)) throw _rejection(e, 'verwijderd');
      await _cache?.enqueueChange(
        kind: 'bookmark',
        clientId: id,
        deleted: true,
        account: await _accountId(),
      );
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
    final account = await _accountId();
    for (final change in await cache.pendingChanges(kind: kind, account: account)) {
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
        account: await _accountId(),
      );
    }
  }

  /// Replays everything queued while offline. Safe to call often - it returns
  /// immediately when the queue is empty.
  Future<FlushResult> flushPendingChanges() async {
    final cache = _cache;
    if (cache == null) return const FlushResult(applied: 0);

    // Only this account's writes: the token sent with /sync is theirs.
    final pending = await cache.pendingChanges(account: await _accountId());
    if (pending.isEmpty) return const FlushResult(applied: 0);

    try {
      final response = await _apiClient.dio.post('/sync', data: {'changes': pending});
      final data = response.data as Map<String, dynamic>;
      final rejected = (data['rejected'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

      // A rejected change is not a retryable failure: STALE means the server
      // already has something newer, DELETED means the row is gone for good,
      // and NOTE_LIMIT_REACHED means no future flush will ever take it either.
      // All three are settled, so they leave the queue with the applied ones.
      //
      // The first two are also nobody's business: the reader's own newer value
      // is what they see anyway. The note limit is different - it drops a note
      // they wrote and watched appear in Notities - so it is reported before
      // the row goes, both to whoever awaited this flush and, because the
      // usual caller is [unawaitedFlush], to the UI through _onSyncRejected.
      final limit = _limitRejection(rejected);
      await cache.clearPendingChanges(pending.map((c) => c['id'] as String));
      if (limit != null) _onSyncRejected?.call(limit);
      return FlushResult(
        applied: pending.length - rejected.length,
        limitRejection: limit,
      );
    } on DioException {
      // Still offline. Leave the queue alone and try again next time.
      return const FlushResult(applied: 0);
    }
  }

  /// Fire-and-forget flush after a successful call - the connection is known
  /// good at that moment, which is the cheapest possible trigger. Nothing
  /// awaits the result here; a refusal worth telling the reader about travels
  /// out through [SyncRejectionSink] instead.
  void unawaitedFlush() {
    flushPendingChanges().catchError((_) => const FlushResult(applied: 0));
  }
}
