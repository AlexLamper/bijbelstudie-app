import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../auth/present/auth_controller.dart';

/// `/feedback` on the website, as a sheet.
///
/// Reports land in the same collection the admin console reads, so an in-app
/// report is indistinguishable from a web one apart from its `page` field.
Future<void> showFeedbackSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: const _FeedbackForm(),
    ),
  );
}

class _FeedbackForm extends ConsumerStatefulWidget {
  const _FeedbackForm();

  @override
  ConsumerState<_FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends ConsumerState<_FeedbackForm> {
  static const _categories = {
    'bug': 'Er gaat iets mis',
    'feature': 'Idee of verzoek',
    'praise': 'Compliment',
    'other': 'Iets anders',
  };

  final _controller = TextEditingController();
  String _category = 'other';
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (message.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await ref
          .read(apiClientProvider)
          .dio
          .post(
            '/feedback',
            data: {'message': message, 'category': _category, 'page': 'app'},
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bedankt voor je feedback.')),
      );
    } on DioException {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Versturen mislukt. Probeer het opnieuw.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Feedback',
              style: AppTheme.displayTitle.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Wat werkt goed, en wat niet? We lezen alles.',
              style: AppTheme.bodyMuted,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in _categories.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _category == entry.key,
                    labelStyle: AppTheme.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _category == entry.key
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                    onSelected: (_) => setState(() => _category = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 8,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Je bericht…'),
            ),
            const SizedBox(height: 16),
            SiteButton(
              label: 'Versturen',
              loading: _sending,
              onPressed: _sending ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}
