import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../profile/present/profile_provider.dart';
import '../data/onboarding_storage.dart';
import '../data/preferences_repository.dart';

/// One stop of the guided walkthrough. Mirrors `guided-tour.tsx`'s `STEPS`,
/// but a real DOM-anchored spotlight has no Flutter equivalent without a new
/// dependency, so this walks through the app's five bottom-nav destinations
/// as full-screen explainer pages instead of highlighting live widgets.
class _TourStepData {
  const _TourStepData({
    required this.icon,
    required this.title,
    required this.description,
    this.hideForPro = false,
  });

  final IconData icon;
  final String title;
  final String description;

  /// Matches the website filtering `pro-cta` out of `GuidedTourLauncher` for
  /// an already-subscribed user.
  final bool hideForPro;
}

const List<_TourStepData> _allSteps = [
  _TourStepData(
    icon: Icons.home_rounded,
    title: 'Je dashboard',
    description:
        'Hier zie je in één oogopslag waar je gebleven was. Tik op de kaart '
        'bovenaan om direct verder te lezen in je laatste hoofdstuk.',
  ),
  _TourStepData(
    icon: Icons.auto_stories,
    title: 'Bijbelstudie',
    description:
        'Dit is het hart van de app. Lees de bijbeltekst, wissel eenvoudig '
        'van vertaling, boek en hoofdstuk, en bekijk ernaast het commentaar '
        'of de grondtekst met Strong-nummers.',
  ),
  _TourStepData(
    icon: Icons.school,
    title: 'Begeleide studies',
    description:
        'Klaargestoomde studies leiden je stap voor stap door een persoon, '
        'thema of bijbelgedeelte - met gerichte vragen per les.',
  ),
  _TourStepData(
    icon: Icons.sticky_note_2,
    title: 'Je notities',
    description:
        'Alle notities, markeringen en bladwijzers die je tijdens het lezen '
        'maakt, vind je hier overzichtelijk terug.',
  ),
  _TourStepData(
    icon: Icons.person,
    title: 'Je profiel',
    description:
        'Hier vind je Bijbelgroepen, Hulpbronnen, je lees- en '
        'meldingsinstellingen, en de knop om feedback te geven of een bug te '
        'melden.',
  ),
  _TourStepData(
    icon: Icons.workspace_premium,
    title: 'Upgrade naar Pro',
    description:
        'Pro ontgrendelt alle commentaren en de grondtekst bij elk '
        'hoofdstuk. Het gratis plan blijft altijd beschikbaar.',
    hideForPro: true,
  ),
];

/// The in-app walkthrough. Reachable once automatically, right after the
/// setup wizard (see [resolvePostAuthRoute]), and any time after that from
/// Profiel - "Rondleiding opnieuw bekijken" - a tour nobody can ever replay
/// is a common complaint, so it stays reachable rather than burning its one
/// local flag forever.
class TourScreen extends ConsumerStatefulWidget {
  const TourScreen({super.key});

  @override
  ConsumerState<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends ConsumerState<TourScreen> {
  final PageController _controller = PageController();
  int _index = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);

    await ref.read(onboardingStorageProvider).markTourSeen();
    try {
      await ref
          .read(preferencesRepositoryProvider)
          .syncPreferences({'tourCompleted': true});
    } catch (_) {
      // Best-effort, same reasoning as the setup wizard's sync.
    }

    if (!mounted) return;
    // Reached by push (from Profiel, a replay) or by go (fresh after setup,
    // no back stack) - each needs its own way back.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read-once: the profile fetch is very likely still in
    // flight the moment the tour opens (nothing upstream warms it), so a
    // one-shot read at initState would almost always miss a Pro account and
    // show the paywall step anyway. Watching lets the list correct itself
    // the moment the fetch lands, at the cost of a step possibly disappearing
    // under the user if they are still sitting on it when that happens — an
    // acceptable trade against permanently pitching Pro to a subscriber.
    final isPro = ref.watch(profileProvider).value?.isPro ?? false;
    final steps = isPro
        ? _allSteps.where((s) => !s.hideForPro).toList()
        : _allSteps;
    final index = _index.clamp(0, steps.length - 1).toInt();
    final isLast = index == steps.length - 1;

    void goNext() {
      if (isLast) {
        _finish();
        return;
      }
      _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.rule)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              height: 60,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.explore_outlined, size: 18, color: AppTheme.teal),
                      SizedBox(width: 8),
                      Text('Rondleiding', style: AppTheme.bodyStrong),
                    ],
                  ),
                  TextButton(
                    // Never a gate, same as the setup wizard.
                    onPressed: _finishing ? null : _finish,
                    child: Text(
                      'Overslaan',
                      style: AppTheme.bodyStrong.copyWith(color: AppTheme.inkMuted),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: steps.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _TourPage(
                  step: steps[i],
                  index: i,
                  total: steps.length,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: List.generate(steps.length, (i) {
                  final active = i == index;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i == steps.length - 1 ? 0 : 6),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 2,
                        color: active ? AppTheme.teal : AppTheme.rule,
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  if (index > 0) ...[
                    Expanded(
                      child: SiteOutlineButton(
                        label: 'Vorige',
                        onPressed: _finishing
                            ? null
                            : () => _controller.previousPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOutCubic,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: SiteButton(
                      label: isLast ? 'Klaar' : 'Volgende',
                      trailingIcon: isLast ? Icons.check : Icons.arrow_forward,
                      loading: _finishing,
                      onPressed: _finishing ? null : goNext,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TourPage extends StatelessWidget {
  const _TourPage({required this.step, required this.index, required this.total});

  final _TourStepData step;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconChip(icon: step.icon, size: 44, iconSize: 20),
              const SizedBox(width: 12),
              Text('Stap ${index + 1} van $total', style: AppTheme.overline),
            ],
          ),
          const SizedBox(height: 28),
          Text(step.title, style: AppTheme.displayLarge),
          const SizedBox(height: 16),
          Text(step.description, style: AppTheme.bodyLead),
        ],
      ),
    );
  }
}
