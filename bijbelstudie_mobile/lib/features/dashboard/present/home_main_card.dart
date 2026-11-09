import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dashboard_models.dart';
import '../data/resume_models.dart';
import 'continue_study_card.dart';
import 'resume_providers.dart';

/// The Start tab's one main card, above the tekst van de dag.
///
/// "Waar je gebleven was" while a study or chapter is in progress; otherwise
/// nothing at all, so the verse card moves up.
///
/// Deliberately compact: the tekst van de dag has to be fully in view without
/// scrolling.
class HomeMainCard extends ConsumerWidget {
  const HomeMainCard({super.key, required this.data, this.bottomSpacing = 14});

  final DashboardData data;

  /// The gap below the card, carried here so the slot collapses completely
  /// when there is no main card to show.
  final double bottomSpacing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Nothing to resume: a new account gets no main card at all rather than a
    // "begin" placeholder.
    final resume = watchResume(
      ref,
      server: data.resume,
      lastRead: data.lastRead,
      readChapters: data.readChapters,
    );
    if (resume.primary.kind == ResumeKind.start) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: ContinueStudyCard(
        compact: true,
        resume: data.resume,
        lastRead: data.lastRead,
        readChapters: data.readChapters,
      ),
    );
  }
}
