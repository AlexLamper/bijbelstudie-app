/// The four milestones on the "Je Bijbel" card's bar: a quarter, half,
/// three quarters and all of the Bible's chapters.
///
/// A milestone counts as reached once the chapters read are at least its share
/// of the total, rounded up, so "a quarter" of 1189 chapters is 298 and the
/// card never celebrates at 24,98%.
enum BibleMilestone {
  quarter(25, 'een kwart', 'Een kwart van de Bijbel gelezen!'),
  half(50, 'de helft', 'De helft van de Bijbel gelezen!'),
  threeQuarters(75, 'driekwart', 'Driekwart van de Bijbel gelezen!'),
  whole(100, 'de hele Bijbel', 'Je hebt de hele Bijbel gelezen!');

  const BibleMilestone(this.percent, this.target, this.celebration);

  /// 25, 50, 75 or 100.
  final int percent;

  /// What the footer counts down to: "Nog 12 hoofdstukken tot [target]".
  final String target;

  /// The footer line on the day this milestone is crossed.
  final String celebration;

  double get fraction => percent / 100;

  /// Chapters needed to reach this milestone out of [total].
  int chaptersNeeded(int total) => (percent * total + 99) ~/ 100;
}

/// The first milestone not yet reached with [read] of [total] chapters, or null
/// once the whole Bible is read.
BibleMilestone? nextBibleMilestone(int read, int total) {
  for (final m in BibleMilestone.values) {
    if (read < m.chaptersNeeded(total)) return m;
  }
  return null;
}

/// Chapters still to read before [nextBibleMilestone]; 0 when all are read.
int chaptersToNextMilestone(int read, int total) {
  final next = nextBibleMilestone(read, total);
  if (next == null) return 0;
  return next.chaptersNeeded(total) - read;
}

/// The footer line when nothing was just crossed.
String bibleMilestoneFooter(int read, int total) {
  final next = nextBibleMilestone(read, total);
  if (next == null) return 'Je hebt de hele Bijbel gelezen';
  final left = next.chaptersNeeded(total) - read;
  return 'Nog $left ${left == 1 ? 'hoofdstuk' : 'hoofdstukken'} tot ${next.target}';
}

/// The highest milestone passed between [lastSeen] and [now] (both 0-100), or
/// null when none was. A reader seen for the first time ([lastSeen] null) has
/// crossed nothing: their progress is not news to them.
BibleMilestone? crossedBibleMilestone({required double? lastSeen, required double now}) {
  if (lastSeen == null) return null;
  BibleMilestone? crossed;
  for (final m in BibleMilestone.values) {
    if (lastSeen < m.percent && now >= m.percent) crossed = m;
  }
  return crossed;
}

/// The card's big number: whole percents from 10 up, one decimal below that so
/// the first chapters visibly move it, and "<0,1%" for a single chapter.
String formatBiblePercent(double pct) {
  if (pct <= 0) return '0%';
  if (pct < 0.1) return '<0,1%';
  if (pct >= 10) return '${pct.floor()}%';
  final tenths = (pct * 10).floor();
  if (tenths % 10 == 0) return '${tenths ~/ 10}%';
  return '${tenths ~/ 10},${tenths % 10}%';
}
