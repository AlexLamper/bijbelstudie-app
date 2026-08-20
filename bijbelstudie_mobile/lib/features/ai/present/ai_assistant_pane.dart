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
  AiQuota? _quota;

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
      if (mounted) setState(() => _quota = quota);
    } catch (_) {
      // The composer still works; only the counter is missing.
    }
  }

  Future<void> _send(String raw) async {
    final message = raw.trim();
    if (message.isEmpty || _sending) return;

    final location = ref.read(readerLocationProvider);
    final history = List<AiTurn>.from(_turns);

    setState(() {
      _turns.add(AiTurn(role: 'user', content: message));
      _sending = true;
      _error = null;
      _errorIsQuota = false;
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
      setState(() {
        _error = e.message;
        _errorIsQuota = true;
        _sending = false;
      });
      // The one moment this surface actually refuses the user, which is what
      // `paywall_hit` means. The generic branch below is a fault, not a gate.
      ref.read(analyticsProvider).track(AnalyticsEvents.paywallHit, {
        'surface': 'ai_limit',
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _errorIsQuota = false;
        _sending = false;
      });
    }
    _loadQuota();
    _scrollToEnd();
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

    return Column(
      children: [
        if (quota != null && !quota.unlimited)
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
              ? _EmptyPrompt(onPick: _send, suggestions: _suggestions)
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
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppTheme.destructive.withValues(alpha: 0.07),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    style: AppTheme.caption.copyWith(color: AppTheme.destructive),
                  ),
                ),
                if (_errorIsQuota)
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
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: const InputDecoration(
                    hintText: 'Stel een vraag over dit hoofdstuk…',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                width: 44,
                child: FilledButton(
                  onPressed: _sending ? null : () => _send(_controller.text),
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
  const _EmptyPrompt({required this.onPick, required this.suggestions});

  final void Function(String prompt) onPick;
  final List<String> suggestions;

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
              onPressed: () => onPick(suggestion),
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
