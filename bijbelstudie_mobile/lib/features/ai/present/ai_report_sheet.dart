import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/ai_report_repository.dart';

/// "AI-antwoord melden": flag one assistant answer as wrong, offensive or
/// harmful without leaving the app (Google Play's AI-Generated Content policy).
///
/// Reports land in the website's feedback read-out (`/beheer/feedback`,
/// touchpoint "AI-antwoord gemeld") with the question and answer attached.
/// On success the sheet closes and a SnackBar thanks the reader; on failure it
/// stays open with the error inline, so nothing they wrote is lost.
Future<void> showAiReportSheet(
  BuildContext context, {
  required String answer,
  String question = '',
  String surface = 'study_ai',
  String? model,
}) async {
  // Captured up front: the sheet's own context is gone by the time it closes.
  final messenger = ScaffoldMessenger.maybeOf(context);
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: AiReportForm(
        answer: answer,
        question: question,
        surface: surface,
        model: model,
      ),
    ),
  );
  if (sent == true) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Bedankt, we bekijken dit.')),
    );
  }
}

class AiReportForm extends ConsumerStatefulWidget {
  const AiReportForm({
    super.key,
    required this.answer,
    this.question = '',
    this.surface = 'study_ai',
    this.model,
  });

  final String answer;
  final String question;
  final String surface;
  final String? model;

  @override
  ConsumerState<AiReportForm> createState() => _AiReportFormState();
}

class _AiReportFormState extends ConsumerState<AiReportForm> {
  final _controller = TextEditingController();
  String? _reason;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _sending) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(aiReportRepositoryProvider)
          .submit(
            AiReport(
              reason: reason,
              answer: widget.answer,
              question: widget.question,
              comment: _controller.text,
              surface: widget.surface,
              model: widget.model,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e is AiReportFailed
            ? e.message
            : 'Melden mislukt. Probeer het opnieuw.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI-antwoord melden',
              style: AppTheme.displayTitle.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Wat is er mis met dit antwoord? '
              'We gebruiken meldingen om de assistent te verbeteren.',
              style: AppTheme.bodyMuted,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in aiReportReasons.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _reason == entry.key,
                    labelStyle: AppTheme.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _reason == entry.key
                          ? Colors.white
                          : scheme.onSurface,
                    ),
                    onSelected: _sending
                        ? null
                        : (_) => setState(() {
                            _reason = entry.key;
                            _error = null;
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              enabled: !_sending,
              minLines: 2,
              maxLines: 5,
              maxLength: AiReport.maxComment,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Toelichting (optioneel)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                style: AppTheme.caption.copyWith(color: AppTheme.destructive),
              ),
            ],
            const SizedBox(height: 12),
            SiteButton(
              label: 'Versturen',
              loading: _sending,
              onPressed: _sending || _reason == null ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}
