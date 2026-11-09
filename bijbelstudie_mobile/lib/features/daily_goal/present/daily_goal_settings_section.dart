import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../auth/present/auth_controller.dart';
import '../../settings/present/settings_controls.dart';
import 'daily_goal_providers.dart';
import 'daily_goal_sheet.dart';

/// Instellingen: the daily goal, and the one engagement mail switch. Both are
/// stored on the account (`/api/v1/daily-goal`, `/api/v1/email-prefs`), so
/// the website's Instellingen shows the same values.
class DailyGoalSettingsSection extends ConsumerWidget {
  const DailyGoalSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final p = ref.watch(dailyGoalProvider).progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 28),
        const Padding(
          padding: EdgeInsets.fromLTRB(32, 0, 32, 8),
          child: Eyebrow('Dagdoel'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SettingsCard(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                p.reached
                    ? 'Vandaag gehaald: ${p.minutes} minuten.'
                    : 'Vandaag ${p.minutesRead} van ${p.minutes} minuten gelezen.',
                style: AppTheme.bodyMuted,
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: DailyGoalChoices(source: 'settings'),
            ),
            const _WinbackMailRow(),
          ]),
        ),
      ],
    );
  }
}

/// `GET/PATCH /api/v1/email-prefs` -> `{ winback, all }`.
final winbackMailPrefProvider = FutureProvider.autoDispose<bool>((ref) async {
  final ApiClient client = ref.watch(apiClientProvider);
  final res = await client.dio.get<dynamic>('/email-prefs');
  final data = (res.data as Map?) ?? const {};
  return data['winback'] != false && data['all'] != false;
});

class _WinbackMailRow extends ConsumerStatefulWidget implements SettingsRowLike {
  const _WinbackMailRow();

  @override
  ConsumerState<_WinbackMailRow> createState() => _WinbackMailRowState();
}

class _WinbackMailRowState extends ConsumerState<_WinbackMailRow> {
  bool? _value;

  Future<void> _set(bool next) async {
    final before = _value;
    setState(() => _value = next);
    try {
      await ref.read(apiClientProvider).dio.patch<dynamic>('/email-prefs', data: {'winback': next});
    } catch (_) {
      if (!mounted) return;
      setState(() => _value = before);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Opslaan is niet gelukt. Probeer het later opnieuw.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final loaded = ref.watch(winbackMailPrefProvider);
    final value = _value ?? loaded.value;
    return SettingsRow(
      label: 'Mail als ik een tijdje weg ben',
      subtitle: 'Na 3, 7 en 14 dagen zonder lezen, hooguit drie keer.',
      switchValue: value ?? true,
      onSwitchChanged: value == null ? null : _set,
    );
  }
}
