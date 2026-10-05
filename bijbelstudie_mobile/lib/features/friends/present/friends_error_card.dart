import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/friends_failure.dart';

/// What a vriendenkring surface shows when the server did not answer.
///
/// It exists so that "je hebt nog geen vrienden" and "we konden het niet
/// ophalen" are never the same card. [InviteFriendsCard] is an invitation and
/// implies the reader has no kring; showing it on a failed request tells the
/// reader something untrue about their own account.
///
/// Nothing here can fail: a title, a line, and a retry only when retrying
/// could actually help ([FriendsException.retryable]).
class FriendsErrorCard extends StatelessWidget {
  const FriendsErrorCard({super.key, required this.failure, this.onRetry, this.compact = false});

  /// Any error an `AsyncValue` carried. A non-[FriendsException] is mapped
  /// here rather than rendered raw, so a stray `TypeError` still reads as a
  /// Dutch sentence instead of a stack trace.
  final Object failure;

  final Future<void> Function()? onRetry;

  /// The Start tab's version: the same words, less air.
  final bool compact;

  /// True when this failure is the server saying the feature is off, which is
  /// not something to report. Callers check it before building a card at all.
  static bool isQuiet(Object? failure) =>
      failure is FriendsException && failure.kind == FriendsFailure.unavailable;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final error = failure is FriendsException
        ? failure as FriendsException
        : friendsFailureFrom(failure);

    return AppCard(
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconChip(
                icon: error.kind == FriendsFailure.offline
                    ? Icons.wifi_off_outlined
                    : Icons.cloud_off_outlined,
                size: 40,
                iconSize: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      error.title,
                      style: AppTheme.bodyStrong.copyWith(
                        fontSize: 15,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(error.message, style: AppTheme.caption.copyWith(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          if (error.retryable && onRetry != null) ...[
            SizedBox(height: compact ? 12 : 14),
            _RetryButton(onRetry: onRetry!),
          ],
        ],
      ),
    );
  }
}

/// "Opnieuw proberen", with its own spinner so a slow retry does not look like
/// a dead button.
class _RetryButton extends StatefulWidget {
  const _RetryButton({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton> {
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SiteOutlineButton(
      label: _busy ? 'Opnieuw proberen...' : 'Opnieuw proberen',
      icon: Icons.refresh,
      height: 44,
      onPressed: _busy ? null : _retry,
    );
  }
}
