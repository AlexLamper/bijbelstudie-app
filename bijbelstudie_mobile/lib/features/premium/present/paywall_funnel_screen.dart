import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/paywall_goal.dart';

/// The three screens before the price.
///
/// The order is deliberate - goal, then problem and proof, then what that
/// means for this particular reader - so that by the time the price appears it
/// is answering a need the reader has already stated in their own words rather
/// than introducing one.
///
/// Three rather than the five it could be. Every extra screen between someone
/// deciding they are interested and being able to pay is somewhere to lose
/// them, so the problem and the demonstration share a screen, and the closing
/// value list and the objection-handling live on the paywall itself, next to
/// the price they are objections to.
///
/// The X is always there. A paywall with no way out converts worse and is a
/// review rejection besides.
class PaywallFunnelScreen extends ConsumerStatefulWidget {
  const PaywallFunnelScreen({super.key, this.source});

  /// Where the reader came from, passed through to the paywall for analytics.
  final String? source;

  @override
  ConsumerState<PaywallFunnelScreen> createState() => _PaywallFunnelScreenState();
}

class _PaywallFunnelScreenState extends ConsumerState<PaywallFunnelScreen> {
  static const _steps = 3;
  int _step = 0;

  void _next() {
    if (_step < _steps - 1) {
      setState(() => _step += 1);
      return;
    }
    _toPaywall();
  }

  /// `replace`, not `push`: backing out of the price should leave the app, not
  /// walk the reader back through the pitch.
  void _toPaywall() {
    final source = widget.source ?? 'app_funnel';
    context.replace('/premium?source=$source');
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = ref.watch(studyGoalProvider);

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(step: _step, steps: _steps, onClose: _close),
            Expanded(
              child: switch (_step) {
                0 => _GoalStep(
                  selected: goal,
                  onSelect: (value) {
                    ref.read(studyGoalProvider.notifier).select(value);
                    // Advance on tap. Choosing is the answer; making the reader
                    // then press "verder" is a second tap for nothing.
                    Future.delayed(const Duration(milliseconds: 180), () {
                      if (mounted) _next();
                    });
                  },
                ),
                1 => const _DemoStep(),
                _ => _BenefitsStep(goal: goal),
              },
            ),
            // The goal step advances on selection, so it needs no button of
            // its own - one would just sit there disabled.
            if (_step > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SiteButton(
                  label: _step == _steps - 1 ? 'Bekijk BijbelStudie Pro' : 'Verder',
                  trailingIcon: Icons.arrow_forward,
                  onPressed: _next,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.step, required this.steps, required this.onClose});

  final int step;
  final int steps;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < steps; i++) ...[
                  Expanded(
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: i <= step ? AppTheme.teal : AppTheme.rule,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (i < steps - 1) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close),
            tooltip: 'Sluiten',
            color: AppTheme.inkMuted,
          ),
        ],
      ),
    );
  }
}

/// Step 1 - what the reader is here for.
class _GoalStep extends StatelessWidget {
  const _GoalStep({required this.selected, required this.onSelect});

  final StudyGoal? selected;
  final ValueChanged<StudyGoal> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      children: [
        const Eyebrow('Even kort'),
        const SizedBox(height: 10),
        Text('Wat wil je uit bijbelstudie halen?', style: AppTheme.displayMedium),
        const SizedBox(height: 8),
        Text(
          'Zo stemmen we de rest hierop af.',
          style: AppTheme.bodyLead,
        ),
        const SizedBox(height: 22),
        for (final goal in StudyGoal.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _GoalTile(
              goal: goal,
              selected: goal == selected,
              onTap: () => onSelect(goal),
            ),
          ),
      ],
    );
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({required this.goal, required this.selected, required this.onTap});

  final StudyGoal goal;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.tealTint : AppTheme.paperRaised,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: selected ? AppTheme.teal : AppTheme.rule),
          ),
          child: Row(
            children: [
              Icon(goal.icon, size: 18, color: AppTheme.teal),
              const SizedBox(width: 14),
              Expanded(child: Text(goal.label, style: AppTheme.bodyStrong)),
              Icon(
                selected ? Icons.check_circle : Icons.chevron_right,
                size: 18,
                color: selected ? AppTheme.teal : AppTheme.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Step 2 - the problem, answered by showing the thing rather than listing
/// features. The mock is a real passage with the real panel names, so what is
/// promised here is what opens on the next screen.
class _DemoStep extends StatelessWidget {
  const _DemoStep();

  static const _questions = [
    'Wat betekent dit gedeelte?',
    'Wat is de context?',
    'Wat zeggen vertrouwde uitleggers?',
  ];

  static const _layers = [
    ('Commentaar', Icons.chat_bubble_outline),
    ('Context', Icons.history_edu_outlined),
    ('Verwante teksten', Icons.link),
    ('Studievragen', Icons.help_outline),
    ('Uitleg', Icons.lightbulb_outline),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      children: [
        const Eyebrow('Je hoeft het niet alleen uit te zoeken'),
        const SizedBox(height: 10),
        Text('Bijbelstudie kan lastig zijn', style: AppTheme.displayMedium),
        const SizedBox(height: 12),
        Text(
          'De Schrift begrijpen betekent meestal vragen stellen:',
          style: AppTheme.bodyLead,
        ),
        const SizedBox(height: 12),
        for (final question in _questions)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Icon(Icons.circle, size: 5, color: AppTheme.teal),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(question, style: AppTheme.bodyMuted)),
              ],
            ),
          ),
        const SizedBox(height: 20),

        // The demonstration: one verse, and everything that opens around it.
        AppCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: AppTheme.tealTint,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Romeinen 8:28',
                      style: AppTheme.metaLabel.copyWith(color: AppTheme.tealStrong),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'En wij weten, dat dengenen, die God liefhebben, alle '
                      'dingen medewerken ten goede.',
                      style: TextStyle(
                        fontFamily: AppTheme.serifFontName,
                        fontSize: 16,
                        height: 1.5,
                        color: AppTheme.ink,
                      ),
                    ),
                  ],
                ),
              ),
              for (final layer in _layers)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppTheme.rule)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.subdirectory_arrow_right, size: 14, color: AppTheme.inkFaint),
                      const SizedBox(width: 10),
                      Icon(layer.$2, size: 15, color: AppTheme.teal),
                      const SizedBox(width: 10),
                      Expanded(child: Text(layer.$1, style: AppTheme.bodyStrong)),
                    ],
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        Text(
          'Ga verder dan alleen de Bijbel lezen. Begrijp hem.',
          style: AppTheme.displaySmall,
        ),
      ],
    );
  }
}

/// Step 3 - the reader's own goal, said back to them, with what the app does
/// about it.
class _BenefitsStep extends StatelessWidget {
  const _BenefitsStep({required this.goal});

  final StudyGoal? goal;

  @override
  Widget build(BuildContext context) {
    // A reader who skipped the question still gets a coherent screen.
    final resolved = goal ?? StudyGoal.understandBible;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      children: [
        const Eyebrow('Afgestemd op jou'),
        const SizedBox(height: 10),
        Text(resolved.restated, style: AppTheme.displayMedium),
        const SizedBox(height: 16),
        Text('BijbelStudie helpt je:', style: AppTheme.bodyLead),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            children: [
              for (final benefit in resolved.benefits)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check, size: 16, color: AppTheme.positive),
                      const SizedBox(width: 12),
                      Expanded(child: Text(benefit, style: AppTheme.bodyStrong)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Reassurance rather than social proof. This app has no review count
        // or rating it can honestly quote yet, and an invented one is both a
        // lie to the customer and a store-listing problem - so this says what
        // is verifiably true instead.
        AppCard(
          color: AppTheme.paperSunken,
          child: Column(
            children: [
              _Assurance(
                icon: Icons.lock_open_outlined,
                text: 'De gratis versie blijft gewoon beschikbaar',
              ),
              const SizedBox(height: 10),
              _Assurance(
                icon: Icons.cancel_outlined,
                text: 'Opzeggen wanneer je wilt, in je App Store-account',
              ),
              const SizedBox(height: 10),
              _Assurance(
                icon: Icons.bookmark_border,
                text: 'Je notities en voortgang blijven van jou',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Assurance extends StatelessWidget {
  const _Assurance({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppTheme.inkMuted),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: AppTheme.caption)),
      ],
    );
  }
}
