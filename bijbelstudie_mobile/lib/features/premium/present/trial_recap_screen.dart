import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/reverse_trial_repository.dart';
import '../domain/personal_plan.dart';
import 'pro_access_provider.dart';

/// "Je Pro-dagen zitten erop": shown once, on the first open after a new
/// account's reverse trial ended (`/pro-recap`, pushed by `ProPromoTrigger`).
///
/// What the reader did with Pro (their own numbers), what changes now (the
/// personal limit, in the server's words), a button to keep Pro and a way on
/// for free. The server marks it seen as soon as it is on screen, so the
/// website does not show it a second time - and neither does this app.
class TrialRecapScreen extends ConsumerStatefulWidget {
  const TrialRecapScreen({super.key, this.trial, this.limits, this.streak});

  /// For previews and tests; the live screen reads the profile.
  final ReverseTrial? trial;
  final AccountLimits? limits;
  final int? streak;

  @override
  ConsumerState<TrialRecapScreen> createState() => _TrialRecapScreenState();
}

class _TrialRecapScreenState extends ConsumerState<TrialRecapScreen> {
  int? _streak;

  @override
  void initState() {
    super.initState();
    _streak = widget.streak;
    if (widget.trial != null) return;
    final repo = ref.read(reverseTrialRepositoryProvider);
    unawaited(repo.markRecapSeen(Analytics.platform));
    unawaited(repo.recapData().then((data) {
      if (mounted && data != null) setState(() => _streak = data.streak);
    }));
  }

  void _report(String action, ProFeature? feature) {
    ref.read(analyticsProvider).track(AnalyticsEvents.trialRecapAction, {
      'action': action,
      'feature': feature?.id ?? 'none',
    });
  }

  void _continueFree(ProFeature? feature) {
    _report('continue_free', feature);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/dashboard');
    }
  }

  void _upgrade(ProFeature? feature) {
    _report('upgrade', feature);
    // The paywall takes the recap's place: closing it lands where the reader
    // was, never back on the recap.
    context.pushReplacement('/premium?source=app_trial_recap');
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final trial = widget.trial ?? ref.watch(reverseTrialProvider);
    final AccountLimits limits = widget.limits ?? ref.watch(accountLimitsProvider);
    if (trial == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final feature = trial.topFeature;
    final headline = feature == null ? null : PersonalPlanCopy.headline(feature, trial.usage, trial.daysUsed);
    final streak = _streak ?? 0;

    final stats = [
      (Icons.menu_book_outlined, trial.usage.chapters, trial.usage.chapters == 1 ? 'hoofdstuk gelezen' : 'hoofdstukken gelezen'),
      // Lessons take the notes tile when they were the reader's thing.
      feature == ProFeature.studies
          ? (Icons.school_outlined, trial.usage.lessons, trial.usage.lessons == 1 ? 'les gedaan' : 'lessen gedaan')
          : (Icons.edit_note_outlined, trial.usage.notes, trial.usage.notes == 1 ? 'notitie' : 'notities'),
      (Icons.auto_awesome_outlined, trial.usage.ai, trial.usage.ai == 1 ? 'AI-vraag' : 'AI-vragen'),
      (Icons.local_fire_department_outlined, streak, streak == 1 ? 'dag op rij' : 'dagen op rij'),
    ];

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.tealTint, AppTheme.paper],
            stops: const [0, 0.45],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SiteBadge.teal('BijbelStudie Pro', icon: Icons.workspace_premium_outlined),
                          const SizedBox(height: 14),
                          Semantics(
                            header: true,
                            child: Text(
                              'Je Pro-dagen zitten erop',
                              style: AppTheme.displaySmall.copyWith(fontSize: 28, height: 1.15, letterSpacing: -0.4),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Dit deed je in ${trial.daysUsed == 1 ? 'je ene dag' : 'je ${trial.daysUsed} dagen'} met Pro:',
                            style: AppTheme.bodyMuted.copyWith(color: AppTheme.inkSoft),
                          ),
                          const SizedBox(height: 18),
                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1.75,
                            children: [
                              for (final (icon, value, label) in stats) _StatTile(icon: icon, value: value, label: label),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'WAT ER NU VERANDERT',
                            style: AppTheme.caption.copyWith(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              color: AppTheme.inkMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (feature != null)
                            Text.rich(
                              TextSpan(
                                style: AppTheme.bodyMuted.copyWith(color: AppTheme.ink, height: 1.45),
                                children: [
                                  if (headline != null) TextSpan(text: '$headline. '),
                                  TextSpan(text: 'Omdat je ${feature.name} het meest gebruikte, houd je daarvan gratis '),
                                  TextSpan(
                                    text: PersonalPlanCopy.limitLine(feature),
                                    style: AppTheme.bodyStrong.copyWith(height: 1.45),
                                  ),
                                  const TextSpan(text: '.'),
                                ],
                              ),
                            )
                          else
                            Text('Je gaat verder met de gratis versie.', style: AppTheme.bodyMuted.copyWith(color: AppTheme.ink, height: 1.45)),
                          const SizedBox(height: 8),
                          Text(
                            'Gratis blijft: ${PersonalPlanCopy.list(PersonalPlanCopy.freeIncludes(feature, limits))}.',
                            style: AppTheme.caption.copyWith(fontSize: 13, height: 1.45, color: AppTheme.inkSoft),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    children: [
                      SiteButton(label: 'Houd Pro', onPressed: () => _upgrade(feature)),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: () => _continueFree(feature),
                        child: Text(
                          'Gratis verder',
                          style: AppTheme.buttonLabel.copyWith(color: AppTheme.inkSoft),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.value, required this.label});

  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.paperRaised,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: AppTheme.teal),
          const SizedBox(height: 6),
          Text('$value', style: AppTheme.displayTitle.copyWith(fontSize: 22, height: 1)),
          const SizedBox(height: 3),
          Text(label, style: AppTheme.caption.copyWith(fontSize: 12, color: AppTheme.inkSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
