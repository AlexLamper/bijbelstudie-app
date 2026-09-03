import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../auth/present/auth_controller.dart';
import '../../auth/present/splash_screen.dart' show BijbelStudieWordmark;
import '../data/onboarding_storage.dart';

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.index,
    required this.badge,
    required this.title,
    required this.accent,
    required this.body,
    required this.highlights,
  });

  final String index;
  final String badge;

  /// Leading part of the headline, rendered in ink.
  final String title;

  /// Trailing part of the headline, rendered in lapis — the site always
  /// colours one phrase of a heading with `text-lapis`.
  final String accent;
  final String body;
  final List<String> highlights;
}

const List<_OnboardingPageData> _pages = [
  _OnboardingPageData(
    index: '01',
    badge: 'Welkom',
    title: 'Lees de ',
    accent: 'Bijbel',
    body:
        'De Statenvertaling en de King James Version, hoofdstuk voor '
        'hoofdstuk. Stel de letter in zoals jij prettig leest en pak de draad '
        'op waar je gebleven was.',
    highlights: [
      'Statenvertaling en King James Version',
      'Bewaar hoofdstukken om offline te lezen',
    ],
  ),
  _OnboardingPageData(
    index: '02',
    badge: 'Verdieping',
    title: 'Begrijp wat er ',
    accent: 'staat',
    body:
        'Lees bij elk hoofdstuk het commentaar van Matthew Henry, of ga naar '
        'de grondtekst met transliteratie en Strong-nummers.',
    highlights: [
      'Commentaren bij elk hoofdstuk',
      'Hebreeuws en Grieks met Strong-nummers',
    ],
  ),
  _OnboardingPageData(
    index: '03',
    badge: 'Vasthouden',
    title: 'Bewaar wat je ',
    accent: 'ontdekt',
    body:
        'Markeer verzen, schrijf je notities op en sla bladwijzers op. Alles '
        'staat ook klaar op www.bijbelstudie.io.',
    highlights: [
      'Notities, markeringen en bladwijzers',
      'Gesynchroniseerd met de website',
    ],
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    // Persist the seen-flag so the intro never reappears on later launches.
    await ref.read(onboardingStorageProvider).markSeen();

    final token = await ref.read(authStorageProvider).getToken();
    final hasSession = token != null && token.isNotEmpty;
    if (mounted) context.go(hasSession ? '/dashboard' : '/login');
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: Column(
          children: [
            // Header rail — `sticky top-0 border-b border-rule bg-paper/90`.
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.rule)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              height: 60,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const BijbelStudieWordmark(fontSize: 20),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _isLast ? 0 : 1,
                    child: TextButton(
                      onPressed: _isLast ? null : _finish,
                      child: Text(
                        'Overslaan',
                        style: AppTheme.bodyStrong.copyWith(
                          color: AppTheme.inkMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _OnboardingPage(data: _pages[i]),
              ),
            ),
            // Hairline step indicator — active segment is solid ink.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: List.generate(_pages.length, (i) {
                  final active = i == _index;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: i == _pages.length - 1 ? 0 : 6,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
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
              child: SiteButton(
                label: _isLast ? 'Aan de slag' : 'Volgende',
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

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.data});

  final _OnboardingPageData data;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Serif step number, like the site's `01`/`02` list markers.
              Text(
                data.index,
                style: TextStyle(
                  fontFamily: AppTheme.displayFontName,
                  fontSize: 14,
                  color: AppTheme.lapis,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: Eyebrow(data.badge)),
            ],
          ),
          const SizedBox(height: 28),
          // `font-display text-[34px] font-semibold leading-[1.06]
          //  tracking-[-0.03em]`
          Text.rich(
            TextSpan(
              style: TextStyle(
                fontFamily: AppTheme.displayFontName,
                fontSize: 34,
                fontWeight: FontWeight.w600,
                height: 1.06,
                letterSpacing: -1.02,
                color: AppTheme.ink,
              ),
              children: [
                TextSpan(text: data.title),
                TextSpan(
                  text: data.accent,
                  style: TextStyle(color: AppTheme.lapis),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(data.body, style: AppTheme.bodyLead),
          const SizedBox(height: 28),
          const RuleLine(),
          const SizedBox(height: 20),
          // `space-y-2.5 border-t border-rule pt-5` with positive check icons.
          ...data.highlights.map(
            (text) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(
                      Icons.check,
                      color: AppTheme.positive,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: AppTheme.bodyMuted.copyWith(
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
