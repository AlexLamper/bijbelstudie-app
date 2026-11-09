/// The daily goal: a few minutes of reading a day, Duolingo-style.
///
/// The server keeps it (`dailyGoal` on the account, the website's
/// `lib/dailyGoal.ts`), so the app and the website show the same goal and the
/// same minutes. This is the client's view of that, plus the seconds this
/// device has counted but not sent yet.
library;

/// The four goals a reader can pick, in minutes.
const List<int> kDailyGoalOptions = [5, 10, 15, 20];

/// What a reader who never picked a goal is measured against (the server's
/// `DEFAULT_DAILY_GOAL`).
const int kDefaultDailyGoal = 10;

bool isDailyGoalMinutes(Object? value) =>
    value is int && kDailyGoalOptions.contains(value);

/// The reader's own calendar day, `yyyy-MM-dd`.
String goalDayKey([DateTime? now]) {
  final d = now ?? DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// One day's goal and progress, as the server last reported it.
class DailyGoal {
  const DailyGoal({
    required this.minutes,
    required this.chosen,
    required this.day,
    required this.seconds,
  });

  /// Nothing known yet: the default goal, nothing read.
  factory DailyGoal.empty(String day) =>
      DailyGoal(minutes: kDefaultDailyGoal, chosen: false, day: day, seconds: 0);

  final int minutes;

  /// False until the reader picked a goal themselves.
  final bool chosen;

  /// The local day these seconds belong to.
  final String day;
  final int seconds;

  int get goalSeconds => minutes * 60;

  /// Parses the `goal` object of `GET/PATCH/POST /api/v1/daily-goal`.
  static DailyGoal? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final minutes = (raw['minutes'] as num?)?.toInt();
    final day = raw['day'];
    if (minutes == null || day is! String) return null;
    return DailyGoal(
      minutes: minutes,
      chosen: raw['chosen'] == true,
      day: day,
      seconds: ((raw['seconds'] as num?)?.toInt() ?? 0).clamp(0, 24 * 3600),
    );
  }

  Map<String, Object?> toJson() =>
      {'minutes': minutes, 'chosen': chosen, 'day': day, 'seconds': seconds};

  DailyGoal copyWith({int? minutes, bool? chosen, String? day, int? seconds}) => DailyGoal(
        minutes: minutes ?? this.minutes,
        chosen: chosen ?? this.chosen,
        day: day ?? this.day,
        seconds: seconds ?? this.seconds,
      );

  /// The same goal on [today]: the counter of another day reads as nothing.
  DailyGoal forDay(String today) =>
      day == today ? this : copyWith(day: today, seconds: 0);
}

/// What Start and the reader draw: the server's goal plus what this device
/// counted since the last report.
class DailyGoalProgress {
  const DailyGoalProgress({required this.goal, this.pendingSeconds = 0});

  final DailyGoal goal;
  final int pendingSeconds;

  int get seconds => goal.seconds + pendingSeconds;
  int get minutes => goal.minutes;
  int get minutesRead => seconds ~/ 60;
  double get progress =>
      goal.goalSeconds <= 0 ? 0 : (seconds / goal.goalSeconds).clamp(0.0, 1.0);
  bool get reached => seconds >= goal.goalSeconds;

  /// Whole minutes still to go, at least one while the goal is not in.
  int get minutesLeft {
    if (reached) return 0;
    final left = goal.goalSeconds - seconds;
    return (left / 60).ceil().clamp(1, goal.minutes);
  }
}
