import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../premium/present/paywall_route.dart';
import '../../premium/present/pro_access_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../bible/present/bible_providers.dart';
import '../data/ai_repository.dart';
import 'ai_conversation_store.dart';
import 'ai_report_sheet.dart';

/// The AI-assistent tab of the study page.
///
/// Mirrors `components/study/AiAssistant.tsx`: the open chapter is sent as
/// context with every question, the free tier is capped at five questions a
/// day, and the cap is reported by the server rather than guessed here.
class AiAssistantPane extends ConsumerStatefulWidget {
  const AiAssistantPane({super.key, this.surface = 'study_ai'});

  /// Which screen hosts the pane, attached to AI-answer reports:
  /// `study_ai` (split reader) or `lesson_ai` (lesson screen).
  final String surface;

  @override
  ConsumerState<AiAssistantPane> createState() => _AiAssistantPaneState();
}

class _AiAssistantPaneState extends ConsumerState<AiAssistantPane> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  // The transcript, the quota and the error state all live in
  // [aiConversationStoreProvider], not here. This pane is one tab of a
  // `TabBarView`: its element is destroyed as soon as the reader swipes two
  // tabs away or leaves the study page, and anything held in this State goes
  // with it. Only the composer and the scroll position are view state and may
  // be rebuilt.

  static const _suggestions = [
    'Wat is de kern van dit hoofdstuk?',
    'Welke historische context helpt hier?',
    'Hoe pas ik dit toe in mijn leven?',
  ];

  @override
  void initState() {
    super.initState();
    // A read of a notifier, never a watch, and deferred one microtask so the
    // first frame is not rebuilt from inside its own build.
    Future.microtask(() {
      if (!mounted) return;
      ref.read(aiConversationStoreProvider.notifier).loadQuota();
    });
    // Returning to a conversation that is still there should land on the
    // newest answer rather than the top of the transcript.
    _scrollToEnd(animate: false);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// What a question asked right now is about, and so where its answer is
  /// filed. Reading another chapter or another translation is another key, so
  /// a kept answer can never be shown against the wrong text.
  AiContextKey _contextKey() {
    final location = ref.read(readerLocationProvider);
    return AiContextKey(
      surface: widget.surface,
      versionId: location.versionId,
      book: location.book,
      chapter: location.chapter,
    );
  }

  Future<void> _send(String raw) async {
    final message = raw.trim();
    if (message.isEmpty) return;

    final key = _contextKey();
    final store = ref.read(aiConversationStoreProvider);
    // A question already in flight for this chapter is not sent twice.
    if (store.blocked != null || store.conversationFor(key).isSending) return;

    // Dismiss the soft keyboard now that the send is actually going ahead -
    // covers the send button, the field's own submit action, and the
    // suggestion chips alike, since all three land here.
    FocusScope.of(context).unfocus();
    _controller.clear();
    _scrollToEnd();

    // The request is owned by the store, so an answer that lands while this
    // pane is unmounted is kept instead of thrown away with the widget.
    final restore = await ref
        .read(aiConversationStoreProvider.notifier)
        .ask(key: key, message: message);
    if (!mounted) return;
    // A question that never reached the model goes back into the composer, so
    // retrying is one tap and nothing the reader typed is lost.
    if (restore != null && _controller.text.isEmpty) {
      _controller.text = restore;
    }
    _scrollToEnd();
  }

  void _scrollToEnd({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final end = _scrollController.position.maxScrollExtent;
      if (!animate) {
        _scrollController.jumpTo(end);
        return;
      }
      _scrollController.animateTo(
        end,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watched, so moving to another chapter repaints against that chapter's
    // own conversation rather than the one just left.
    final location = ref.watch(readerLocationProvider);
    final store = ref.watch(aiConversationStoreProvider);
    final conversation = store.conversationFor(
      AiContextKey(
        surface: widget.surface,
        versionId: location.versionId,
        book: location.book,
        chapter: location.chapter,
      ),
    );

    final turns = conversation.turns;
    final sending = conversation.isSending;
    final quota = store.quota;
    final blocked = store.blocked;

    // A standing block outranks a per-question error: it is the reason the
    // question could not be sent at all.
    final notice = blocked ?? conversation.error;
    final showLoginCta = blocked != null
        ? store.blockedIsAuth
        : conversation.errorKind == AiErrorKind.auth;
    // A subscriber at their limit is not offered Pro again (3.1.1).
    final showProCta =
        blocked == null &&
        conversation.errorKind == AiErrorKind.quota &&
        !ref.watch(hasProProvider);

    return Column(
      children: [
        if (blocked == null && quota != null && !quota.unlimited)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppTheme.assistantTint,
            child: Text(
              'Nog ${quota.remaining} van ${quota.cap} gratis vragen vandaag',
              style: AppTheme.caption.copyWith(color: AppTheme.assistant),
            ),
          ),
        Expanded(
          child: turns.isEmpty
              ? _EmptyPrompt(
                  onPick: _send,
                  suggestions: _suggestions,
                  enabled: blocked == null,
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: turns.length + (sending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= turns.length) return const _TypingBubble();
                    final turn = turns[index];
                    if (turn.isUser) return _TurnBubble(turn: turn);
                    final previous = index > 0 ? turns[index - 1] : null;
                    return _TurnBubble(
                      turn: turn,
                      onReport: () => showAiReportSheet(
                        context,
                        answer: turn.content,
                        question: previous != null && previous.isUser
                            ? previous.content
                            : '',
                        surface: widget.surface,
                        model: turn.model,
                      ),
                    );
                  },
                ),
        ),
        if (notice != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppTheme.destructive.withValues(alpha: 0.07),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    notice,
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.destructive,
                    ),
                  ),
                ),
                if (showProCta)
                  TextButton(
                    onPressed: () {
                      ref.read(analyticsProvider).track(
                        AnalyticsEvents.paywallCtaClicked,
                        {'surface': 'ai_limit'},
                      );
                      openPaywall(context, gate: PaywallGate.aiLimit);
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 30),
                    ),
                    child: Text(
                      'Pro',
                      style: AppTheme.buttonLabel.copyWith(
                        color: AppTheme.assistant,
                      ),
                    ),
                  ),
                if (showLoginCta)
                  TextButton(
                    onPressed: () => context.push('/login'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 30),
                    ),
                    child: const Text('Inloggen'),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Text(
            'AI kan fouten maken. Controleer met de Bijbel.',
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
          ),
        ),
        const RuleLine(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: blocked == null,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: InputDecoration(
                    hintText: blocked == null
                        ? 'Stel een vraag over dit hoofdstuk…'
                        : 'Niet beschikbaar',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                width: 44,
                child: FilledButton(
                  onPressed: sending || blocked != null
                      ? null
                      : () => _send(_controller.text),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.assistant,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                  ),
                  child: const Icon(Icons.arrow_upward, size: 18),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt({
    required this.onPick,
    required this.suggestions,
    required this.enabled,
  });

  final void Function(String prompt) onPick;
  final List<String> suggestions;

  /// False while the assistant cannot answer at all. A suggestion that quietly
  /// does nothing when tapped is worse than one that is visibly unavailable.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      children: [
        Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.assistantTint,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Icon(
              Icons.smart_toy_outlined,
              size: 20,
              color: AppTheme.assistant,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'AI-assistent',
          textAlign: TextAlign.center,
          style: AppTheme.displayTitle.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Stel een vraag over het hoofdstuk dat je leest. '
          'De assistent kent de tekst die nu open staat.',
          textAlign: TextAlign.center,
          style: AppTheme.bodyMuted,
        ),
        const SizedBox(height: 20),
        for (final suggestion in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: enabled ? () => onPick(suggestion) : null,
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size.fromHeight(44),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(suggestion, style: AppTheme.bodyMuted),
              ),
            ),
          ),
      ],
    );
  }
}

class _TurnBubble extends StatelessWidget {
  const _TurnBubble({required this.turn, this.onReport});

  final AiTurn turn;

  /// Opens the report sheet. Set for assistant answers only.
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = turn.isUser;

    final bubble = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: onReport == null ? 10 : 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.teal : scheme.surface,
          border: isUser ? null : Border.all(color: scheme.outline),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: SelectableText(
          turn.content,
          style: TextStyle(
            fontFamily: AppTheme.sansFontName,
            fontSize: 14,
            height: 1.6,
            color: isUser ? Colors.white : scheme.onSurface,
          ),
        ),
      ),
    );

    final report = onReport;
    if (report == null) return bubble;

    // Always visible rather than tucked in a long-press menu: the bubble's
    // long-press already selects text, and a report that has to be discovered
    // is not one a reader can be expected to find.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bubble,
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextButton.icon(
            onPressed: report,
            icon: Icon(Icons.flag_outlined, size: 14, color: AppTheme.inkFaint),
            label: Text(
              'Melden',
              semanticsLabel: 'AI-antwoord melden',
              style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.outline),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.assistant,
          ),
        ),
      ),
    );
  }
}
