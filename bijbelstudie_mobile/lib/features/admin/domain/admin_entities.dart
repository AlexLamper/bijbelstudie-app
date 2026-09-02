/// Entities behind the admin screen.
///
/// Every field mirrors a key of the website's admin API one for one, so the
/// phone reports the same numbers as `/admin` in the browser. See
/// `lib/adminStats.ts`, `lib/adminInsights.ts` and `lib/adminUsers.ts` in the
/// backend repo.
///
/// Counts are nullable on purpose: `/api/v1/admin/stats` degrades per query and
/// sends `null` for a figure it could not read, naming it in
/// [AdminStats.degraded]. Null means "unknown" and must render as a dash —
/// never as 0, which reads as a real measurement.
library;

int? _int(dynamic value) => (value as num?)?.toInt();

double? _double(dynamic value) => (value as num?)?.toDouble();

DateTime? _date(dynamic value) {
  final raw = value as String?;
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

/// The `users` block of `/api/v1/admin/stats`.
class AdminUserStats {
  const AdminUserStats({
    this.total,
    this.premium,
    this.paying,
    this.stripeSubscribers,
    this.storeSubscribers,
    this.comped,
    this.admins,
    this.newLast24h,
    this.newLast7d,
    this.newLast30d,
    this.activeStreak,
    this.premiumPercent,
  });

  final int? total;

  /// Everyone with access, however they got it.
  final int? premium;

  /// Everyone somebody actually pays for — the subscriber number.
  final int? paying;

  final int? stripeSubscribers;
  final int? storeSubscribers;

  /// Access granted without payment: the App Store review account, admin
  /// grants. Never folded into revenue.
  final int? comped;

  final int? admins;
  final int? newLast24h;
  final int? newLast7d;
  final int? newLast30d;
  final int? activeStreak;
  final double? premiumPercent;

  factory AdminUserStats.fromJson(Map<String, dynamic> json) {
    return AdminUserStats(
      total: _int(json['total']),
      premium: _int(json['premium']),
      paying: _int(json['paying']),
      stripeSubscribers: _int(json['stripeSubscribers']),
      storeSubscribers: _int(json['storeSubscribers']),
      comped: _int(json['comped']),
      admins: _int(json['admins']),
      newLast24h: _int(json['newLast24h']),
      newLast7d: _int(json['newLast7d']),
      newLast30d: _int(json['newLast30d']),
      activeStreak: _int(json['activeStreak']),
      premiumPercent: _double(json['premiumPercent']),
    );
  }
}

/// The `billing` block — the card that has to make a billing problem loud.
class AdminBillingStats {
  const AdminBillingStats({
    this.byStatus,
    this.withBillingIssue,
    this.cancelAtPeriodEnd,
    this.paused,
    this.possiblyMissedWebhooks,
    this.monthlySubscribers,
    this.annualSubscribers,
    this.unknownInterval,
  });

  /// Stripe subscription status to count. Null when the aggregation itself
  /// failed; an all-zero table would be indistinguishable from a quiet product.
  final Map<String, int>? byStatus;

  final int? withBillingIssue;
  final int? cancelAtPeriodEnd;
  final int? paused;

  /// Accounts with a Stripe customer but no subscription state: a checkout
  /// whose result was never written back. Every one is worth investigating.
  final int? possiblyMissedWebhooks;

  final int? monthlySubscribers;
  final int? annualSubscribers;
  final int? unknownInterval;

  factory AdminBillingStats.fromJson(Map<String, dynamic> json) {
    final raw = json['byStatus'] as Map<String, dynamic>?;
    return AdminBillingStats(
      byStatus: raw == null
          ? null
          : {
              for (final entry in raw.entries)
                entry.key: (entry.value as num?)?.toInt() ?? 0,
            },
      withBillingIssue: _int(json['withBillingIssue']),
      cancelAtPeriodEnd: _int(json['cancelAtPeriodEnd']),
      paused: _int(json['paused']),
      possiblyMissedWebhooks: _int(json['possiblyMissedWebhooks']),
      monthlySubscribers: _int(json['monthlySubscribers']),
      annualSubscribers: _int(json['annualSubscribers']),
      unknownInterval: _int(json['unknownInterval']),
    );
  }
}

/// The `revenue` block. Euro amounts, already divided by 100 server-side.
class AdminRevenueStats {
  const AdminRevenueStats({
    this.mrrEur,
    this.arrEur,
    this.priceEur,
    this.annualPriceEur,
  });

  final double? mrrEur;
  final double? arrEur;
  final double? priceEur;
  final double? annualPriceEur;

  factory AdminRevenueStats.fromJson(Map<String, dynamic> json) {
    return AdminRevenueStats(
      mrrEur: _double(json['mrrEur']),
      arrEur: _double(json['arrEur']),
      priceEur: _double(json['priceEur']),
      annualPriceEur: _double(json['annualPriceEur']),
    );
  }
}

/// The `content` block — notes, sessions, groups, plans.
class AdminContentStats {
  const AdminContentStats({
    this.notes,
    this.notesLast7d,
    this.readingSessions,
    this.sessionsLast7d,
    this.groups,
    this.plans,
  });

  final int? notes;
  final int? notesLast7d;
  final int? readingSessions;
  final int? sessionsLast7d;
  final int? groups;
  final int? plans;

  factory AdminContentStats.fromJson(Map<String, dynamic> json) {
    return AdminContentStats(
      notes: _int(json['notes']),
      notesLast7d: _int(json['notesLast7d']),
      readingSessions: _int(json['readingSessions']),
      sessionsLast7d: _int(json['sessionsLast7d']),
      groups: _int(json['groups']),
      plans: _int(json['plans']),
    );
  }
}

/// `GET /api/v1/admin/stats`.
class AdminStats {
  const AdminStats({
    required this.users,
    required this.billing,
    required this.revenue,
    required this.content,
    this.degraded = const [],
  });

  final AdminUserStats users;
  final AdminBillingStats billing;
  final AdminRevenueStats revenue;
  final AdminContentStats content;

  /// Dutch labels of the figures that could not be read. Empty when healthy.
  final List<String> degraded;

  factory AdminStats.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> block(String key) =>
        (json[key] as Map<String, dynamic>?) ?? const {};
    return AdminStats(
      users: AdminUserStats.fromJson(block('users')),
      billing: AdminBillingStats.fromJson(block('billing')),
      revenue: AdminRevenueStats.fromJson(block('revenue')),
      content: AdminContentStats.fromJson(block('content')),
      degraded: ((json['degraded'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
    );
  }
}

/// One day of a daily series. [date] is the server's `YYYY-MM-DD` bucket.
class AdminSeriesPoint {
  const AdminSeriesPoint({required this.date, required this.count});

  final String date;
  final int count;

  factory AdminSeriesPoint.fromJson(Map<String, dynamic> json) {
    return AdminSeriesPoint(
      date: json['date'] as String? ?? '',
      count: _int(json['count']) ?? 0,
    );
  }
}

/// A page in the "most viewed" table. [visitors] is people, [views] is hits.
class AdminTopPage {
  const AdminTopPage({
    required this.key,
    required this.label,
    required this.views,
    required this.visitors,
  });

  final String key;
  final String label;
  final int views;
  final int visitors;

  factory AdminTopPage.fromJson(Map<String, dynamic> json) {
    return AdminTopPage(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? 'Onbekend',
      views: _int(json['views']) ?? 0,
      visitors: _int(json['visitors']) ?? 0,
    );
  }
}

/// A registered click target and how often it was pressed.
class AdminTopClick {
  const AdminTopClick({required this.target, required this.count});

  final String target;
  final int count;

  factory AdminTopClick.fromJson(Map<String, dynamic> json) {
    return AdminTopClick(
      target: json['target'] as String? ?? 'onbekend',
      count: _int(json['count']) ?? 0,
    );
  }
}

/// Page views split by who was looking.
class AdminTraffic {
  const AdminTraffic({
    required this.uniqueVisitors,
    required this.loggedInViews,
    required this.loggedOutViews,
  });

  final int uniqueVisitors;
  final int loggedInViews;
  final int loggedOutViews;

  int get totalViews => loggedInViews + loggedOutViews;

  factory AdminTraffic.fromJson(Map<String, dynamic> json) {
    return AdminTraffic(
      uniqueVisitors: _int(json['uniqueVisitors']) ?? 0,
      loggedInViews: _int(json['loggedInViews']) ?? 0,
      loggedOutViews: _int(json['loggedOutViews']) ?? 0,
    );
  }
}

/// One study's row in the engagement funnel.
class AdminStudyRow {
  const AdminStudyRow({
    required this.studyId,
    required this.title,
    required this.enrollments,
    required this.completed,
    required this.lessonsCompleted,
  });

  final String studyId;
  final String title;
  final int enrollments;
  final int completed;
  final int lessonsCompleted;

  factory AdminStudyRow.fromJson(Map<String, dynamic> json) {
    return AdminStudyRow(
      studyId: json['studyId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      enrollments: _int(json['enrollments']) ?? 0,
      completed: _int(json['completed']) ?? 0,
      lessonsCompleted: _int(json['lessonsCompleted']) ?? 0,
    );
  }
}

/// The `study` block — how many people actually study.
class AdminStudyStats {
  const AdminStudyStats({
    required this.enrollmentsActive,
    required this.enrollmentsCompleted,
    required this.enrollmentsTotal,
    required this.activeStudents,
    required this.reflectionsWritten,
    required this.quizAttempts,
    required this.quizzesGraded,
    this.quizAccuracy,
    this.perStudy = const [],
  });

  final int enrollmentsActive;
  final int enrollmentsCompleted;
  final int enrollmentsTotal;
  final int activeStudents;
  final int reflectionsWritten;
  final int quizAttempts;
  final int quizzesGraded;

  /// Percentage, or null when nothing has been graded yet.
  final int? quizAccuracy;

  final List<AdminStudyRow> perStudy;

  factory AdminStudyStats.fromJson(Map<String, dynamic> json) {
    return AdminStudyStats(
      enrollmentsActive: _int(json['enrollmentsActive']) ?? 0,
      enrollmentsCompleted: _int(json['enrollmentsCompleted']) ?? 0,
      enrollmentsTotal: _int(json['enrollmentsTotal']) ?? 0,
      activeStudents: _int(json['activeStudents']) ?? 0,
      reflectionsWritten: _int(json['reflectionsWritten']) ?? 0,
      quizAttempts: _int(json['quizAttempts']) ?? 0,
      quizzesGraded: _int(json['quizzesGraded']) ?? 0,
      quizAccuracy: _int(json['quizAccuracy']),
      perStudy: ((json['perStudy'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AdminStudyRow.fromJson)
          .toList(growable: false),
    );
  }
}

/// `GET /api/v1/admin/insights?days=`.
class AdminInsights {
  const AdminInsights({
    required this.range,
    required this.signups,
    required this.notes,
    required this.readingSessions,
    required this.newSubscribers,
    required this.cancellations,
    required this.pageViews,
    required this.lessonsCompleted,
    required this.traffic,
    required this.topPages,
    required this.topClicks,
    required this.study,
  });

  /// Days covered — the server clamps to 7...365.
  final int range;

  final List<AdminSeriesPoint> signups;
  final List<AdminSeriesPoint> notes;
  final List<AdminSeriesPoint> readingSessions;
  final List<AdminSeriesPoint> newSubscribers;
  final List<AdminSeriesPoint> cancellations;
  final List<AdminSeriesPoint> pageViews;
  final List<AdminSeriesPoint> lessonsCompleted;
  final AdminTraffic traffic;
  final List<AdminTopPage> topPages;
  final List<AdminTopClick> topClicks;
  final AdminStudyStats study;

  factory AdminInsights.fromJson(Map<String, dynamic> json) {
    List<AdminSeriesPoint> series(String key) {
      return ((json[key] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AdminSeriesPoint.fromJson)
          .toList(growable: false);
    }

    return AdminInsights(
      range: _int(json['range']) ?? 30,
      signups: series('signups'),
      notes: series('notes'),
      readingSessions: series('readingSessions'),
      newSubscribers: series('newSubscribers'),
      cancellations: series('cancellations'),
      pageViews: series('pageViews'),
      lessonsCompleted: series('lessonsCompleted'),
      traffic: AdminTraffic.fromJson(
        (json['traffic'] as Map<String, dynamic>?) ?? const {},
      ),
      topPages: ((json['topPages'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AdminTopPage.fromJson)
          .toList(growable: false),
      topClicks: ((json['topClicks'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AdminTopClick.fromJson)
          .toList(growable: false),
      study: AdminStudyStats.fromJson(
        (json['study'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}

/// One row of `GET /api/v1/admin/users`.
class AdminAccount {
  const AdminAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.isAdmin,
    required this.subscribed,
    required this.isPro,
    required this.isComped,
    required this.storePremium,
    required this.cancelAtPeriodEnd,
    required this.hasBillingIssue,
    required this.needsReconcile,
    required this.hasStripe,
    required this.onboardingCompleted,
    required this.streak,
    required this.noteCount,
    this.image,
    this.storePremiumPlatform,
    this.subscriptionStatus,
    this.subscriptionInterval,
    this.currentPeriodEnd,
    this.createdAt,
    this.lastStreakDate,
  });

  final String id;
  final String name;
  final String email;
  final String? image;

  final bool isAdmin;

  /// The Stripe flag alone. [isPro] is the effective entitlement.
  final bool subscribed;

  final bool isPro;

  /// Pro without payment — a review account or an admin grant.
  final bool isComped;

  final bool storePremium;

  /// `apple`, `google`, or null.
  final String? storePremiumPlatform;

  final String? subscriptionStatus;

  /// `monthly`, `annual`, or null.
  final String? subscriptionInterval;

  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final bool hasBillingIssue;

  /// Stripe customer exists but no subscription state was ever written back.
  final bool needsReconcile;

  final bool hasStripe;
  final bool onboardingCompleted;
  final int streak;
  final int noteCount;
  final DateTime? createdAt;
  final DateTime? lastStreakDate;

  String get displayName => name.trim().isEmpty ? 'Naamloos' : name.trim();

  /// First letter, for the avatar circle.
  String get initial {
    final source = name.trim().isEmpty ? email : name.trim();
    return source.isEmpty ? '?' : source.substring(0, 1).toUpperCase();
  }

  factory AdminAccount.fromJson(Map<String, dynamic> json) {
    return AdminAccount(
      id: json['_id'] as String? ?? json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      image: json['image'] as String?,
      isAdmin: json['isAdmin'] as bool? ?? false,
      subscribed: json['subscribed'] as bool? ?? false,
      isPro: json['isPro'] as bool? ?? false,
      isComped: json['isComped'] as bool? ?? false,
      storePremium: json['storePremium'] as bool? ?? false,
      storePremiumPlatform: json['storePremiumPlatform'] as String?,
      subscriptionStatus: json['subscriptionStatus'] as String?,
      subscriptionInterval: json['subscriptionInterval'] as String?,
      currentPeriodEnd: _date(json['currentPeriodEnd']),
      cancelAtPeriodEnd: json['cancelAtPeriodEnd'] as bool? ?? false,
      hasBillingIssue: json['hasBillingIssue'] as bool? ?? false,
      needsReconcile: json['needsReconcile'] as bool? ?? false,
      hasStripe: json['hasStripe'] as bool? ?? false,
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
      streak: _int(json['streak']) ?? 0,
      noteCount: _int(json['noteCount']) ?? 0,
      createdAt: _date(json['createdAt']),
      lastStreakDate: _date(json['lastStreakDate']),
    );
  }

  AdminAccount copyWith({bool? isAdmin, bool? subscribed}) {
    final nextAdmin = isAdmin ?? this.isAdmin;
    final nextSubscribed = subscribed ?? this.subscribed;
    return AdminAccount(
      id: id,
      name: name,
      email: email,
      image: image,
      isAdmin: nextAdmin,
      subscribed: nextSubscribed,
      // Effective Pro follows the same OR the server applies, so a toggled row
      // does not have to be re-fetched to look right.
      isPro: nextSubscribed || storePremium || nextAdmin,
      isComped: isComped,
      storePremium: storePremium,
      storePremiumPlatform: storePremiumPlatform,
      subscriptionStatus: subscriptionStatus,
      subscriptionInterval: subscriptionInterval,
      currentPeriodEnd: currentPeriodEnd,
      cancelAtPeriodEnd: cancelAtPeriodEnd,
      hasBillingIssue: hasBillingIssue,
      needsReconcile: needsReconcile,
      hasStripe: hasStripe,
      onboardingCompleted: onboardingCompleted,
      streak: streak,
      noteCount: noteCount,
      createdAt: createdAt,
      lastStreakDate: lastStreakDate,
    );
  }
}
