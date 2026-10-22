import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/data/account_scope.dart';
import '../../auth/present/auth_controller.dart' show sessionAccountProvider;
import 'dashboard_models.dart';

/// Local memory for the "Tekst van de dag" card.
///
/// The server has no endpoint for either half of this: `GET /daytext` hands
/// out today's verse and nothing else - no archive, no favourites. So the app
/// keeps both on the device, the same way [ReadingSettings] keeps the reader's
/// typography: every verse that arrives is appended to a capped history, and
/// every verse the reader hearts is stored whole, so "Favoriete teksten" can
/// show it back to them.
///
/// Both are best-effort. A device with no preferences plugin (tests, an
/// unusual platform) simply gets an empty history and no likes rather than an
/// error - the card must still render today's verse.

/// One day's verse as it was stored, plus the day it was shown.
class DailyVerseEntry {
  const DailyVerseEntry({
    required this.date,
    required this.text,
    required this.reference,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.version,
  });

  /// Local calendar day, `yyyy-mm-dd`. Also the de-duplication key: one entry
  /// per day, so a dashboard refresh does not stack the same verse twice.
  final String date;

  final String text;
  final String reference;
  final String book;
  final int chapter;
  final int verse;

  /// The translation abbreviation shown beside the reference on the day it was
  /// captured, e.g. `SV`. Empty when it could not be determined.
  final String version;

  Map<String, dynamic> toJson() => {
    'date': date,
    'text': text,
    'reference': reference,
    'book': book,
    'chapter': chapter,
    'verse': verse,
    'version': version,
  };

  static DailyVerseEntry? fromJson(Map<String, dynamic> json) {
    final text = json['text'] as String?;
    final date = json['date'] as String?;
    if (text == null || date == null) return null;
    return DailyVerseEntry(
      date: date,
      text: text,
      reference: json['reference'] as String? ?? '',
      book: json['book'] as String? ?? '',
      chapter: (json['chapter'] as num?)?.toInt() ?? 1,
      verse: (json['verse'] as num?)?.toInt() ?? 1,
      version: json['version'] as String? ?? '',
    );
  }

  /// What the share sheet and the archive rows show.
  String get referenceWithVersion =>
      version.isEmpty ? reference : '$reference $version';
}

/// A verse the reader hearted, kept whole rather than as a bare reference.
///
/// The heart is tapped on a card that already has the text, the book and the
/// translation label in hand, so the like stores a snapshot of all of it. The
/// favourites screen can then show the verse itself even after the day has
/// dropped out of the capped archive.
class LikedVerse {
  const LikedVerse({
    required this.reference,
    required this.text,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.version,
    required this.likedAt,
  });

  final String reference;
  final String text;
  final String book;
  final int chapter;
  final int verse;
  final String version;

  /// When the heart was tapped. Favourites are listed newest first on this.
  final DateTime likedAt;

  /// The reference as it is printed, with the translation label when known.
  String get referenceWithVersion =>
      version.isEmpty ? reference : '$reference $version';

  Map<String, dynamic> toJson() => {
    'reference': reference,
    'text': text,
    'book': book,
    'chapter': chapter,
    'verse': verse,
    'version': version,
    'likedAt': likedAt.toIso8601String(),
  };

  static LikedVerse? fromJson(Map<String, dynamic> json) {
    final reference = json['reference'] as String?;
    if (reference == null || reference.isEmpty) return null;
    return LikedVerse(
      reference: reference,
      text: json['text'] as String? ?? '',
      book: json['book'] as String? ?? '',
      chapter: (json['chapter'] as num?)?.toInt() ?? 1,
      verse: (json['verse'] as num?)?.toInt() ?? 1,
      version: json['version'] as String? ?? '',
      likedAt:
          DateTime.tryParse(json['likedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  /// The like as it is made from the archived day the heart was tapped on.
  factory LikedVerse.fromEntry(DailyVerseEntry entry, {DateTime? likedAt}) {
    return LikedVerse(
      reference: entry.reference,
      text: entry.text,
      book: entry.book,
      chapter: entry.chapter,
      verse: entry.verse,
      version: entry.version,
      likedAt: likedAt ?? DateTime.now(),
    );
  }
}

/// The stored state: newest day first, plus the verses that were hearted.
class DailyVerseMemory {
  const DailyVerseMemory({
    this.history = const [],
    this.likes = const [],
    this.loaded = false,
    this.strandedLikes = false,
  });

  /// Newest first, at most [DailyVerseStore.maxDays] entries.
  final List<DailyVerseEntry> history;

  /// The hearted verses, newest like first.
  final List<LikedVerse> likes;

  /// The references (without the version suffix) that are hearted.
  Set<String> get liked => {for (final like in likes) like.reference};

  /// False until the first read from disk has finished, so the card can show a
  /// skeleton instead of a heart that flips a moment later.
  final bool loaded;

  /// True when hearted verses are sitting on this device under an account id
  /// it cannot place, and this reader has none of their own. Favoriete teksten
  /// offers to put them back; see [DailyVerseStore.restoreStrandedLikes].
  final bool strandedLikes;

  bool isLiked(String reference) =>
      likes.any((like) => like.reference == reference);

  DailyVerseMemory copyWith({
    List<DailyVerseEntry>? history,
    List<LikedVerse>? likes,
    bool? loaded,
    bool? strandedLikes,
  }) {
    return DailyVerseMemory(
      history: history ?? this.history,
      likes: likes ?? this.likes,
      loaded: loaded ?? this.loaded,
      strandedLikes: strandedLikes ?? this.strandedLikes,
    );
  }
}

/// Per device: the archive is the same feed for everyone. The likes below are
/// per account, keyed through [AccountScope.keyFor].
const _kHistory = 'daytext.history';

/// The pre-1.2 store: a flat list of hearted references, with no text and no
/// date. Still read once, to migrate it into [_kLikes].
const _kLiked = 'daytext.liked';

/// The likes as whole verses, JSON encoded, newest like first.
const _kLikes = 'daytext.likes';

final dailyVerseStoreProvider =
    NotifierProvider<DailyVerseStore, DailyVerseMemory>(DailyVerseStore.new);

class DailyVerseStore extends Notifier<DailyVerseMemory> {
  /// Two months of archive. Long enough that "voorgaande dagen" is worth
  /// opening, short enough that the whole thing stays a few kilobytes of JSON.
  static const int maxDays = 60;

  /// The first read from disk. Every mutator awaits it before touching state.
  ///
  /// This used to be a fire-and-forget read with a `_written` flag that made it
  /// bail out if a write had got in first - and a write always did. The card
  /// calls [remember] from its first post-frame callback, which lands well
  /// before `SharedPreferences.getInstance()` resolves, so the read returned
  /// early on every single launch. State was then "today's verse and nothing
  /// else", and [_persistHistory] wrote exactly that back over the stored
  /// archive. Every previous day was destroyed on startup, which is why
  /// "Voorgaande dagen" was always empty no matter how long the app had been
  /// used.
  ///
  /// Waiting is the whole fix: the read is quick, the writes it gates are not
  /// user-visible, and a mutation can no longer be built on a blank history.
  late Future<void> _ready;

  /// The account whose hearts this build shows. The store rebuilds when a
  /// different account signs in, so one reader's favourites never show up
  /// for the next.
  late Future<String?> _account;

  /// Bumped on every rebuild, which is every time a different account signs
  /// in. [build] also resets state to an empty [DailyVerseMemory] and reloads,
  /// so a mutator that started before the rebuild holds a list computed for
  /// the reader who has just left - or for that transient empty state. It must
  /// not be written: see [_readyToMutate] and [_stillCurrent].
  int _generation = 0;

  /// True when the read off disk threw. What is stored is then *unknown*, not
  /// empty, even though state says `loaded: true` with no likes - so no write
  /// may go out, or an empty list lands on top of a good one.
  bool _loadFailed = false;

  @override
  DailyVerseMemory build() {
    _generation++;
    _loadFailed = false;
    _account = AccountScope.resolve(ref.watch(sessionAccountProvider));
    _ready = _load();
    return const DailyVerseMemory();
  }

  Future<void> _load() async {
    // This build's ref: after a rebuild (another account) it reads unmounted,
    // so a slow read cannot land the previous reader's likes.
    final buildRef = ref;
    final generation = _generation;
    try {
      final account = await _account;
      final prefs = await SharedPreferences.getInstance();
      await _adoptSameReaderLikes(prefs, account);
      // The read outlives the provider when the app (or a test) tears down
      // mid-launch; writing state then throws rather than being ignored.
      if (!buildRef.mounted || _generation != generation) return;
      final history = _decode(prefs.getString(_kHistory));
      final likes = _decodeLikes(prefs, history, account);
      state = DailyVerseMemory(
        history: history,
        likes: likes,
        loaded: true,
        strandedLikes: likes.isEmpty && _strandedDonor(prefs, account) != null,
      );
    } catch (_) {
      // No preferences plugin, or a stored value that is not the type it
      // should be: an empty archive, and likes that live only for this
      // session. Still "loaded" - nothing more is coming - but flagged, so
      // nothing from this session is written over what is really on disk.
      if (_generation == generation) _loadFailed = true;
      if (!buildRef.mounted || _generation != generation) return;
      state = state.copyWith(loaded: true);
    }
  }

  /// Waits for this build's read off disk. False when the caller must not go
  /// on at all: the store rebuilt for another account while waiting, or this
  /// build was disposed. Its list would be the previous reader's.
  Future<bool> _readyToMutate() async {
    final generation = _generation;
    final buildRef = ref;
    await _ready;
    return buildRef.mounted && _stillCurrent(generation);
  }

  /// Still the build that started the mutation.
  bool _stillCurrent(int generation) => _generation == generation;

  /// Whether what is in memory may go to disk: still this build's, and the
  /// read it was built on actually succeeded. A failed read leaves state empty
  /// while disk holds the real list, so a write would wipe it; the tap still
  /// shows in the UI for this session, it just is not stored.
  bool _canPersist(int generation) =>
      _stillCurrent(generation) && !_loadFailed;

  /// The two keys a reader's hearts live under, newest store first.
  static const _likeBases = [_kLikes, _kLiked];

  /// Takes over hearts stranded under an id this same reader lost.
  ///
  /// An account that is deleted and made again comes back with a new id, and
  /// `daytext.likes.<new id>` then reads empty while the whole list sits under
  /// the old one. [AccountScope.sameReaderScope] only names that old id when
  /// the device recorded the same reader behind it, so this is a recovery of
  /// the reader's own verses and never a peek at somebody else's.
  Future<void> _adoptSameReaderLikes(
    SharedPreferences prefs,
    String? account,
  ) async {
    if (account == null || account.isEmpty) return;
    final donor = AccountScope.sameReaderScope(prefs, _likeBases, account);
    if (donor == null) return;
    await _moveLikes(prefs, donor, account);
  }

  /// The id holding hearts this device cannot place, for the offer on
  /// Favoriete teksten. Null unless this reader has nothing of their own.
  String? _strandedDonor(SharedPreferences prefs, String? account) {
    if (account == null || account.isEmpty) return null;
    if (!_isEmptyLikesBlob(prefs.getString(AccountScope.keyFor(_kLikes, account)))) {
      return null;
    }
    return AccountScope.strandedScope(prefs, _likeBases, account);
  }

  /// Puts back the hearts stranded under an id this device cannot place.
  ///
  /// What the "Favorieten terugzetten" button on Favoriete teksten calls. The
  /// reader asking for it is the one thing the silent path cannot have: data
  /// from before [AccountScope.kIdentitiesKey] carries no proof of whose it
  /// is, so it is offered rather than taken. True when something moved.
  Future<bool> restoreStrandedLikes() async {
    if (!await _readyToMutate()) return false;
    final generation = _generation;
    if (!_canPersist(generation)) return false;
    try {
      final account = await _account;
      final prefs = await SharedPreferences.getInstance();
      if (!_canPersist(generation)) return false;
      final donor = account == null || account.isEmpty
          ? null
          : _strandedDonor(prefs, account);
      if (donor == null || account == null) {
        if (_stillCurrent(generation) && ref.mounted) {
          state = state.copyWith(strandedLikes: false);
        }
        return false;
      }
      if (!await _moveLikes(prefs, donor, account)) return false;
      if (!_stillCurrent(generation) || !ref.mounted) return true;
      state = DailyVerseMemory(
        history: state.history,
        likes: _decodeLikes(prefs, state.history, account),
        loaded: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Hands the hearts stored under [donor] to [account]. True when something
  /// moved.
  ///
  /// Only ever writes into an empty list, so a reader who genuinely has no
  /// favourites cannot have theirs overwritten. The donor keys go once the
  /// copy is on disk: the data has a single home again, and a *further* change
  /// of id stays recoverable the same way.
  Future<bool> _moveLikes(
    SharedPreferences prefs,
    String donor,
    String account,
  ) async {
    final ownLikes = AccountScope.keyFor(_kLikes, account);
    final ownLiked = AccountScope.keyFor(_kLiked, account);
    if (!_isEmptyLikesBlob(prefs.getString(ownLikes))) return false;
    if ((prefs.getStringList(ownLiked) ?? const <String>[]).isNotEmpty) {
      return false;
    }

    final donorLikes = AccountScope.keyFor(_kLikes, donor);
    final donorLiked = AccountScope.keyFor(_kLiked, donor);
    final raw = prefs.getString(donorLikes);
    final legacy = prefs.getStringList(donorLiked) ?? const <String>[];
    final emptyRaw = _isEmptyLikesBlob(raw);
    if (emptyRaw && legacy.isEmpty) return false;

    if (!emptyRaw) await prefs.setString(ownLikes, raw!);
    if (legacy.isNotEmpty) await prefs.setStringList(ownLiked, legacy);
    await prefs.remove(donorLikes);
    await prefs.remove(donorLiked);
    return true;
  }

  /// Nothing to lose: absent, blank, or valid JSON holding no likes at all.
  /// A blob that will not parse counts as *not* empty - it may still be a
  /// reader's list, and is never written over.
  bool _isEmptyLikesBlob(String? raw) {
    if (raw == null || raw.trim().isEmpty) return true;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List && decoded.isEmpty;
    } catch (_) {
      return false;
    }
  }

  List<DailyVerseEntry> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(DailyVerseEntry.fromJson)
          .whereType<DailyVerseEntry>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// The likes off disk, newest first, migrating the old flat set if that is
  /// all this install has.
  ///
  /// A migrated like has no timestamp of its own - the old store kept only the
  /// reference - so it is dated from the archived day it was hearted on, and
  /// falls back to the epoch-less "onbekend" path in the UI when even that is
  /// gone.
  List<LikedVerse> _decodeLikes(
    SharedPreferences prefs,
    List<DailyVerseEntry> history,
    String? account,
  ) {
    final raw = prefs.getString(AccountScope.keyFor(_kLikes, account));
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final likes = decoded
              .whereType<Map<String, dynamic>>()
              .map(LikedVerse.fromJson)
              .whereType<LikedVerse>()
              .toList()
            ..sort((a, b) => b.likedAt.compareTo(a.likedAt));
          return List.unmodifiable(likes);
        }
      } catch (_) {
        // Fall through to the legacy list rather than losing every like.
      }
    }

    final legacy =
        prefs.getStringList(AccountScope.keyFor(_kLiked, account)) ?? const <String>[];
    if (legacy.isEmpty) return const [];

    final byReference = <String, DailyVerseEntry>{
      for (final entry in history.reversed) entry.reference: entry,
    };
    final migrated = <LikedVerse>[];
    for (final reference in legacy) {
      final entry = byReference[reference];
      migrated.add(
        entry == null
            ? LikedVerse(
                reference: reference,
                text: '',
                book: '',
                chapter: 1,
                verse: 1,
                version: '',
                likedAt: DateTime.fromMillisecondsSinceEpoch(0),
              )
            : LikedVerse.fromEntry(
                entry,
                likedAt:
                    DateTime.tryParse(entry.date) ??
                    DateTime.fromMillisecondsSinceEpoch(0),
              ),
      );
    }
    migrated.sort((a, b) => b.likedAt.compareTo(a.likedAt));
    return List.unmodifiable(migrated);
  }

  /// Records [verse] as today's entry, if today is not already recorded.
  ///
  /// Called from the card whenever `/dashboard` hands over a daily verse, so
  /// the archive fills itself simply by opening the app on consecutive days.
  Future<void> remember(DailyVerse verse, {required String version}) async {
    if (!await _readyToMutate()) return;
    final today = dayKey(DateTime.now());
    final existing = state.history;
    // Same day, same verse, same translation: nothing to write. A switch of
    // translation keeps the reference but changes the text and the label, and
    // today's entry must follow it - "Voorgaande dagen" and the favourites
    // show the verse as the reader last saw it.
    if (existing.isNotEmpty &&
        existing.first.date == today &&
        existing.first.reference == verse.reference &&
        existing.first.text == verse.text &&
        existing.first.version == version) {
      return;
    }

    final entry = DailyVerseEntry(
      date: today,
      text: verse.text,
      reference: verse.reference,
      book: verse.book,
      chapter: verse.chapter,
      verse: verse.verse,
      version: version,
    );

    // Newest first, and sorted by day rather than by arrival: an entry
    // recovered from an older install, or a day whose key sorts before one
    // already stored, still lands in the right place in the list.
    final next =
        <DailyVerseEntry>[entry, ...existing.where((e) => e.date != today)]
          ..sort((a, b) => b.date.compareTo(a.date));

    final capped = next.take(maxDays).toList(growable: false);
    state = state.copyWith(history: capped, loaded: true);
    await _persistHistory(capped);
  }

  /// Folds the server's archive into the device's.
  ///
  /// `GET /daytext/history` is the shared record of every day the feed was
  /// fetched, so this is what makes "Voorgaande dagen" show more than the days
  /// this particular install happened to be opened - a reinstall, a new phone
  /// or a fresh build no longer starts from nothing.
  ///
  /// The device copy wins on a clash: it was written from the verse the reader
  /// actually saw, including the translation label they were reading in.
  Future<void> mergeServer(List<DailyVerseEntry> entries) async {
    if (entries.isEmpty) return;
    if (!await _readyToMutate()) return;

    final byDate = <String, DailyVerseEntry>{
      for (final entry in entries) entry.date: entry,
      for (final entry in state.history) entry.date: entry,
    };

    final merged = byDate.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final capped = merged.take(maxDays).toList(growable: false);

    // Nothing new: leave state alone rather than handing every listener a new
    // list to rebuild on.
    final before = state.history.map((e) => e.date).join(',');
    if (before == capped.map((e) => e.date).join(',')) return;

    state = state.copyWith(history: capped, loaded: true);
    await _persistHistory(capped);
  }

  /// Hearts [reference], or un-hearts it when it is already a favourite.
  ///
  /// The verse itself is taken from the archive the card has just written, so
  /// the favourites list keeps the text and the translation label even once
  /// the day has aged out of [maxDays]. A reference with no archived day - a
  /// heart tapped before the archive was written - is still stored, and simply
  /// shows as a reference on its own.
  Future<void> toggleLike(String reference) async {
    if (reference.isEmpty) return;
    if (!await _readyToMutate()) return;

    final next = [...state.likes];
    final at = next.indexWhere((like) => like.reference == reference);
    if (at >= 0) {
      next.removeAt(at);
    } else {
      DailyVerseEntry? source;
      for (final entry in state.history) {
        if (entry.reference == reference) {
          source = entry;
          break;
        }
      }
      final like = source == null
          ? LikedVerse(
              reference: reference,
              text: '',
              book: '',
              chapter: 1,
              verse: 1,
              version: '',
              likedAt: DateTime.now(),
            )
          : LikedVerse.fromEntry(source);
      next.insert(0, like);
    }

    await _setLikes(next);
  }

  /// Drops [reference] from the favourites. What the Favoriete teksten screen
  /// calls; a reference that is not hearted is left alone.
  Future<void> removeLike(String reference) async {
    if (!await _readyToMutate()) return;
    if (!state.isLiked(reference)) return;
    await _setLikes(
      state.likes.where((like) => like.reference != reference).toList(),
    );
  }

  /// Puts [reference] back where it was, for "Ongedaan maken" after a remove.
  Future<void> restoreLike(LikedVerse like) async {
    if (!await _readyToMutate()) return;
    if (state.isLiked(like.reference)) return;
    final next = [...state.likes, like]
      ..sort((a, b) => b.likedAt.compareTo(a.likedAt));
    await _setLikes(next);
  }

  /// Stores [likes] as this account's whole list.
  ///
  /// Callers reach here through [_readyToMutate], so the list was computed from
  /// what is really on disk rather than from the empty state a rebuild leaves
  /// behind. The generation is checked once more after the awaits: a sign-in
  /// that lands in between must not get the previous reader's list written
  /// under its key.
  Future<void> _setLikes(List<LikedVerse> likes) async {
    final generation = _generation;
    final capped = List<LikedVerse>.unmodifiable(likes);
    state = state.copyWith(likes: capped, loaded: true);
    if (!_canPersist(generation)) return;
    try {
      final account = await _account;
      final prefs = await SharedPreferences.getInstance();
      if (!_canPersist(generation)) return;
      await prefs.setString(
        AccountScope.keyFor(_kLikes, account),
        jsonEncode(capped.map((like) => like.toJson()).toList(growable: false)),
      );
      // The legacy list is kept in step (under the same account key), as it
      // was before likes were per account.
      await prefs.setStringList(
        AccountScope.keyFor(_kLiked, account),
        capped.map((like) => like.reference).toList(growable: false),
      );
    } catch (_) {
      // Best effort; the heart still reflects the tap for this session.
    }
  }

  Future<void> _persistHistory(List<DailyVerseEntry> history) async {
    final generation = _generation;
    if (!_canPersist(generation)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_canPersist(generation)) return;
      await prefs.setString(
        _kHistory,
        jsonEncode(history.map((e) => e.toJson()).toList(growable: false)),
      );
    } catch (_) {
      // Best effort.
    }
  }
}

/// `yyyy-mm-dd` in local time - the archive's per-day key.
String dayKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

/// The short label for a translation, as it is printed after a reference.
///
/// Takes an id (`nbg51`) or the full name the server sends ("Statenvertaling",
/// "NBG-vertaling 1951"), in any case - the same table as
/// `versionAbbreviation` in the website's `lib/dailyVerseStore.ts`. The name
/// used to fall through to capitals, which put "STATENVERTALING" after every
/// reference. Anything unknown still falls back to capitals: wrong-looking,
/// but never blank.
String versionAbbreviation(String versionId) {
  final key = versionId.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  return switch (key) {
    'statenvertaling' || 'sv' => 'SV',
    'nbg51' || 'nbgvertaling1951' => 'NBG51',
    'canisiusbijbel' || 'canisiusbijbel1939' => 'CANIS',
    'heiligeschrift1917' || 'deheiligeschrift1917' => 'HS1917',
    'kjv' || 'kingjamesversion' => 'KJV',
    'asv' || 'americanstandardversion' => 'ASV',
    'web' || 'worldenglishbible' => 'WEB',
    'geneva' || 'genevabible(1599)' => 'GNV',
    'coverdale' || 'coverdalebible(1535)' => 'CVDL',
    _ => versionId.replaceAll('_', '').toUpperCase(),
  };
}

/// The NBG-vertaling 1951 copyright notice, verbatim. The wording is
/// contractual - never reword, shorten or restyle it. It must match
/// `BIBLE_ATTRIBUTIONS.nbg51` in the website's `lib/bible-attribution.ts`,
/// which is what the server sends as `attribution` with today's verse.
const String nbg51Attribution =
    'NBG-vertaling 1951© 1951 Nederlands-Vlaams Bijbelgenootschap';

/// The notice a stored verse must carry, from the label it was stored with:
/// the NBG51 string for an NBG51 verse, null for public domain. Days in the
/// archive and hearted verses keep only the label, so this is how "Voorgaande
/// dagen" and the favourites print the notice with licensed text.
String? attributionForVersionLabel(String label) =>
    label == 'NBG51' ? nbg51Attribution : null;
