import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../bible/present/bible_providers.dart';
import '../data/ai_repository.dart';

/// The AI-assistent tab of the study page.
///
/// Mirrors `components/study/AiAssistant.tsx`: the open chapter is sent as
/// context with every question, the free tier is capped at five questions a
/// day, and the cap is reported by the server rather than guessed here.
class AiAssistantPane extends ConsumerStatefulWidget {
  const AiAssistantPane({super.key});

  @override
  ConsumerState<AiAssistantPane> createState() => _AiAssistantPaneState();
}

class _AiAssistantPaneState extends ConsumerState<AiAssistantPane> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<AiTurn> _turns = [];

  bool _sending = false;
  String? _error;
  /// Whether [_error] is the daily cap rather than a network or server fault.
  /// Only the cap is a paywall: offering Pro as the answer to "the assistant is
  /// unreachable" sells nothing and reads as opportunism.
  bool _errorIsQuota = false;
  /// Whether [_error] is a dead session, which needs a way back to the login
  /// screen rather than a retry that will fail the same way.
  bool _errorIsAuth = false;
  AiQuota? _quota;

  /// Set when the assistant cannot answer *any* question right now: the server
  /// reports no model key, or there is no session behind the request. Both are
  /// known before the user types, so the composer is disabled and the reason
  /// stated - letting someone write a question that is guaranteed to fail is
  /// the silent failure this pane used to have.
  String? _blocked;
  bool _blockedIsAuth = false;

  static const _suggestions = [
    'Wat is de kern van dit hoofdstuk?',
    'Welke historische context helpt hier?',
    'Hoe pas ik dit toe in mijn leven?',
  ];

  @override
  void initState() {
    super.initState();
    _loadQuota();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadQuota() async {
    try {
      final quota = await ref.read(aiRepositoryProvider).getQuota();
      if (!mounted) return;
      setState(() {
        _quota = quota;
        // A deployment without GEMINI_API_KEY answers every question with a
        // 503. The quota call is the only place that is knowable up front, and
        // it used to be thrown away here.
        _blocked = quota.configured
            ? null
            : 'De AI-assistent is momenteel niet beschikbaar.';
        _blockedIsAuth = false;
      });
    } on AiAuthRequired catch (e) {
      if (!mounted) return;
      setState(() {
        _blocked = e.message;
        _blockedIsAuth = true;
      });
    } catch (_) {
      // A network blip. The composer still works, and a question that really
      // cannot be sent reports it itself.
    }
  }

  Future<void> _send(String raw) async {
    final message = raw.trim();
    if (message.isEmpty || _sending || _blocked != null) return;

    final location = ref.read(readerLocationProvider);
    final history = List<AiTurn>.from(_turns);

    setState(() {
      _turns.add(AiTurn(role: 'user', content: message));
      _sending = true;
      _error = null;
      _errorIsQuota = false;
      _errorIsAuth = false;
      _controller.clear();
    });
    _scrollToEnd();

    try {
      final reply = await ref
          .read(aiRepositoryProvider)
          .ask(
            message: message,
            history: history,
            book: location.book,
            chapter: location.chapter,
            version: location.versionId,
          );
      if (!mounted) return;
      setState(() {
        _turns.add(AiTurn(role: 'assistant', content: reply));
        _sending = false;
      });
    } on AiQuotaExceeded catch (e) {
      if (!mounted) return;
      _failTurn(message, e.message, isQuota: true);
      // The one moment this surface actually refuses the user, which is what
      // `paywall_hit` means. The branches below are faults, not gates: the
      // server also answers 429 for `AI_BUSY`, and counting that as a paywall
      // both lied to the user and inflated the funnel.
      ref.read(analyticsProvider).track(AnalyticsEvents.paywallHit, {
        'surface': 'ai_limit',
      });
    } on AiAuthRequired catch (e) {
      if (!mounted) return;
      _failTurn(message, e.message, isAuth: true);
    } catch (e) {
      if (!mounted) return;
      _failTurn(message, '$e'.replaceFirst('Exception: ', ''));
    }
    _loadQuota();
    _scrollToEnd();
  }

  /// Rolls back the question that never reached the model.
  ///
  /// Leaving its bubble in the transcript would show an unanswered turn and,
  /// worse, send it again as history on the next question - the model would be
  /// asked to continue from something it never saw. The text goes back into the
  /// composer so retrying is one tap and nothing the user typed is lost.
  void _failTurn(
    String message,
    String error, {
    bool isQuota = false,
    bool isAuth = false,
  }) {
    setState(() {
      if (_turns.isNotEmpty &&
          _turns.last.isUser &&
          _turns.last.content == message) {
        _turns.removeLast();
      }
      if (_controller.text.isEmpty) _controller.text = message;
      _error = error;
      _errorIsQuota = isQuota;
      _errorIsAuth = isAuth;
      _sending = false;
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final quota = _quota;
    final blocked = _blocked;

    // A standing block outranks a per-question error: it is the reason the
    // question could not be sent at all.
    final notice = blocked ?? _error;
    final showLoginCta = blocked != null ? _blockedIsAuth : _errorIsAuth;
    final showProCta = blocked == null && _errorIsQuota;

    return Column(
      children: [
        if (blocked == null && quota != null && !quota.unlimited)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppTheme.ai.withValues(alpha: 0.06),
            child: Text(
              'Nog ${quota.remaining} van ${quota.cap} gratis vragen vandaag',
              style: AppTheme.caption.copyWith(color: AppTheme.ai),
            ),
          ),
        Expanded(
          child: _turns.isEmpty
              ? _EmptyPrompt(
                  onPick: _send,
                  suggestions: _suggestions,
                  enabled: blocked == null,
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: _turns.length + (_sending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _turns.length) return const _TypingBubble();
                    return _TurnBubble(turn: _turns[index]);
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
                    style: AppTheme.caption.copyWith(color: AppTheme.destructive),
                  ),
                ),
                if (showProCta)
                  TextButton(
                    onPressed: () {
                      ref
                          .read(analyticsProvider)
                          .track(AnalyticsEvents.paywallCtaClicked, {
                            'surface': 'ai_limit',
                          });
                      context.push('/premium?source=app_ai');
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 30),
                    ),
                    child: const Text('Pro'),
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
                  onPressed: _sending || blocked != null
                      ? null
                      : () => _send(_controller.text),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.ai,
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
              color: AppTheme.ai.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: const Icon(Icons.auto_awesome, size: 20, color: AppTheme.ai),
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
  const _TurnBubble({required this.turn});

  final AiTurn turn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = turn.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
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
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.ai),
        ),
      ),
    );
  }
}
