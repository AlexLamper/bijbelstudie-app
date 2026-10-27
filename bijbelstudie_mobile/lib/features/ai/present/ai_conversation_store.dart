import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../premium/present/pro_access_provider.dart';
import '../../premium/present/promo_moments.dart';

import '../../../core/analytics/analytics.dart';
import '../data/ai_repository.dart';

/// What one AI answer is about, and therefore what a kept answer is filed under.
///
/// Every field here travels with the request in [AiRepository.askReply], so two
/// keys that differ cannot share an answer: opening another chapter, another
/// book or another translation yields a different key and an empty transcript
/// rather than the previous chapter's answer. [surface] is part of it because
/// the split reader and the lesson screen are two conversations to the reader,
/// not one.
@immutable
class AiContextKey {
  const AiContextKey({
    required this.surface,
    required this.versionId,
    required this.book,
    required this.chapter,
  });

  /// `study_ai` (split reader) or `lesson_ai` (lesson screen).
  final String surface;
  final String versionId;
  final String book;
  final int chapter;

  @override
  bool operator ==(Object other) {
    return other is AiContextKey &&
        other.surface == surface &&
        other.versionId == versionId &&
        other.book == book &&
        other.chapter == chapter;
  }

  @override
  int get hashCode => Object.hash(surface, versionId, book, chapter);

  @override
  String toString() => '$surface|$versionId|$book|$chapter';
}

/// Which state the pane is in after a question failed, which decides what it
/// may offer: the daily cap is the only one that is a paywall.
enum AiErrorKind { none, quota, auth, fault }

/// The transcript for one [AiContextKey], plus whatever is still in flight.
@immutable
class AiConversation {
  const AiConversation({
    required this.touchedAt,
    this.turns = const [],
    this.pending,
    this.error,
    this.errorKind = AiErrorKind.none,
  });

  /// The questions and answers so far, oldest first.
  final List<AiTurn> turns;

  /// The question whose answer has not come back yet, so a reader who swipes
  /// away mid-answer returns to the running load instead of a blank pane, and
  /// asking again does not fire a second request for the same answer.
  final String? pending;

  final String? error;
  final AiErrorKind errorKind;

  /// When this conversation last gained a question, an answer or an error.
  /// Viewing it does not count: the retention window is measured from real
  /// activity so it is the same whether the reader looks once or ten times.
  final DateTime touchedAt;

  bool get isSending => pending != null;

  bool get isEmpty => turns.isEmpty && pending == null && error == null;

  /// Expired conversations are dropped on the next read or write. One still
  /// waiting on an answer never expires: its answer is on its way.
  bool isExpiredAt(DateTime now) {
    if (pending != null) return false;
    return now.difference(touchedAt) >= AiConversationStore.retention;
  }
}

/// Everything the assistant pane paints, held outside the widget tree.
@immutable
class AiAssistantState {
  const AiAssistantState({
    this.conversations = const {},
    this.quota,
    this.blocked,
    this.blockedIsAuth = false,
  });

  final Map<AiContextKey, AiConversation> conversations;

  /// The daily budget as the server last reported it. Account-wide, so it is
  /// not filed per conversation.
  final AiQuota? quota;

  /// Set when the assistant cannot answer *any* question right now: no model
  /// key on the server, or no session behind the request.
  final String? blocked;
  final bool blockedIsAuth;

  /// The conversation for [key], or an empty one when there is none or the one
  /// there has fallen outside the retention window.
  AiConversation conversationFor(AiContextKey key, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final existing = conversations[key];
    if (existing == null || existing.isExpiredAt(at)) {
      return AiConversation(touchedAt: at);
    }
    return existing;
  }
}

/// Holds the assistant's transcripts for the whole app run.
///
/// Deliberately not `autoDispose`, and deliberately not inside the pane's
/// [State]: the pane is one tab of a `TabBarView`, so swiping two tabs away or
/// leaving the study page disposes the widget, and anything kept there goes
/// with it. That is why answers used to vanish the moment the reader looked at
/// something else.
///
/// Memory only, by choice. The transcript is the reader's own questions plus
/// model answers, which is not something to write to the device without being
/// asked, and the thirty minute window is about one sitting: an app restart is
/// a clean slate the reader expects. Nothing here needs sqflite or
/// shared_preferences.
final aiConversationStoreProvider =
    NotifierProvider<AiConversationStore, AiAssistantState>(
      AiConversationStore.new,
    );

class AiConversationStore extends Notifier<AiAssistantState> {
  /// How long an answer stays available after the last activity on it.
  ///
  /// Half an hour covers what the reader actually does: switch to Commentaar,
  /// read the chapter, open their notes, walk away for a coffee and come back
  /// to the answer still there. Longer than one sitting it is no longer the
  /// conversation they left, and the chapter context it was answered against
  /// has usually moved on.
  static const retention = Duration(minutes: 30);

  /// How many chapters' conversations are kept at once. Dropped oldest first.
  static const maxConversations = 6;

  /// Turns kept per conversation, so one long chat cannot grow without bound.
  /// Oldest turns go first; they are also the ones no longer sent as history.
  static const maxTurns = 30;

  /// How long the reported quota is treated as fresh, so remounting the tab
  /// does not fire a `GET /ai/chat` every time.
  static const _quotaFreshness = Duration(minutes: 2);

  DateTime? _quotaFetchedAt;
  Future<void>? _quotaInFlight;

  @override
  AiAssistantState build() => const AiAssistantState();

  /// Drops expired conversations and enforces [maxConversations].
  ///
  /// Pure and static so the retention rules can be tested without a container,
  /// a clock or a socket.
  static Map<AiContextKey, AiConversation> retain(
    Map<AiContextKey, AiConversation> source, {
    required DateTime now,
  }) {
    final kept = <AiContextKey, AiConversation>{
      for (final entry in source.entries)
        if (!entry.value.isExpiredAt(now)) entry.key: entry.value,
    };
    if (kept.length <= maxConversations) return kept;

    final oldestFirst = kept.entries.toList()
      ..sort((a, b) => a.value.touchedAt.compareTo(b.value.touchedAt));
    for (final entry in oldestFirst) {
      if (kept.length <= maxConversations) break;
      // A conversation waiting on an answer is never the one evicted.
      if (entry.value.pending != null) continue;
      kept.remove(entry.key);
    }
    return kept;
  }

  /// The conversation to paint for [key]. Never mutates state, so it is safe
  /// to call from `build`.
  AiConversation conversation(AiContextKey key) => state.conversationFor(key);

  void _write(AiContextKey key, AiConversation conversation) {
    final next = Map<AiContextKey, AiConversation>.of(state.conversations);
    next[key] = conversation;
    state = AiAssistantState(
      conversations: retain(next, now: DateTime.now()),
      quota: state.quota,
      blocked: state.blocked,
      blockedIsAuth: state.blockedIsAuth,
    );
  }

  static List<AiTurn> _capped(List<AiTurn> turns) {
    if (turns.length <= maxTurns) return turns;
    return turns.sublist(turns.length - maxTurns);
  }

  /// Sends one question for [key] and files the answer under it.
  ///
  /// Returns the question when it never reached the model, so the caller can
  /// put the text back in the composer. Returns null when it was answered, and
  /// also when a question for this context is already in flight: that second
  /// send would be a duplicate request for an answer already on its way.
  ///
  /// The await lives here rather than in the widget, so an answer that lands
  /// while the pane is unmounted is kept instead of thrown away.
  Future<String?> ask({
    required AiContextKey key,
    required String message,
  }) async {
    if (state.blocked != null) return null;
    final current = conversation(key);
    if (current.pending != null) return null;

    final history = current.turns;
    _write(
      key,
      AiConversation(
        turns: _capped([
          ...history,
          AiTurn(role: 'user', content: message),
        ]),
        pending: message,
        touchedAt: DateTime.now(),
      ),
    );

    String? restore;
    try {
      final reply = await ref
          .read(aiRepositoryProvider)
          .askReply(
            message: message,
            history: history,
            book: key.book,
            chapter: key.chapter,
            version: key.versionId,
          );
      _write(
        key,
        AiConversation(
          turns: _capped([
            ...conversation(key).turns,
            AiTurn(role: 'assistant', content: reply.text, model: reply.model),
          ]),
          touchedAt: DateTime.now(),
        ),
      );
    } on AiQuotaExceeded catch (e) {
      restore = message;
      _fail(key, message, e.message, AiErrorKind.quota);
      // The one moment this surface actually refuses the reader, which is what
      // `paywall_hit` means. The branches below are faults, not gates.
      ref.read(analyticsProvider).track(AnalyticsEvents.paywallHit, {
        'surface': 'ai_limit',
      });
    } on AiAuthRequired catch (e) {
      restore = message;
      _fail(key, message, e.message, AiErrorKind.auth);
    } catch (e) {
      restore = message;
      _fail(key, message, '$e'.replaceFirst('Exception: ', ''),
          AiErrorKind.fault);
    }

    await loadQuota(force: true);
    return restore;
  }

  /// Rolls back the question that never reached the model.
  ///
  /// Leaving its bubble in the transcript would show an unanswered turn and,
  /// worse, send it again as history on the next question - the model would be
  /// asked to continue from something it never saw.
  void _fail(
    AiContextKey key,
    String message,
    String error,
    AiErrorKind kind,
  ) {
    final current = conversation(key);
    final turns = List<AiTurn>.of(current.turns);
    if (turns.isNotEmpty && turns.last.isUser && turns.last.content == message) {
      turns.removeLast();
    }
    _write(
      key,
      AiConversation(
        turns: turns,
        error: error,
        errorKind: kind,
        touchedAt: DateTime.now(),
      ),
    );
  }

  /// Reads the daily budget, which is also the only place a missing model key
  /// is knowable before the reader types.
  Future<void> loadQuota({bool force = false}) {
    final fetchedAt = _quotaFetchedAt;
    if (!force &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _quotaFreshness) {
      return Future.value();
    }
    return _quotaInFlight ??= _loadQuota().whenComplete(() {
      _quotaInFlight = null;
    });
  }

  Future<void> _loadQuota() async {
    try {
      final quota = await ref.read(aiRepositoryProvider).getQuota();
      _quotaFetchedAt = DateTime.now();
      state = AiAssistantState(
        conversations: state.conversations,
        quota: quota,
        // A deployment without GEMINI_API_KEY answers every question with a
        // 503. The quota call is the only place that is knowable up front.
        blocked: quota.configured
            ? null
            : 'De AI-assistent is momenteel niet beschikbaar.',
        blockedIsAuth: false,
      );
      // The last free question of the day was just used: the offer appears
      // next time Start is on screen, before the next question is refused.
      if (!quota.unlimited && quota.cap > 0 && quota.remaining == 0 && !ref.read(hasProProvider)) {
        ref.read(promoMomentProvider.notifier).request(PromoMoment.aiLastQuestion);
      }
    } on AiAuthRequired catch (e) {
      state = AiAssistantState(
        conversations: state.conversations,
        quota: state.quota,
        blocked: e.message,
        blockedIsAuth: true,
      );
    } catch (_) {
      // A network blip. The composer still works, and a question that really
      // cannot be sent reports it itself.
    }
  }
}
