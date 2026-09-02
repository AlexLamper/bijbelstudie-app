class User {
  final String id;
  final String name;
  final String email;
  final String? image;
  final bool isPro;

  /// Where Pro came from: `stripe` (web subscriber), `apple`, `google`,
  /// `admin`, or null. The paywall reads this — a web subscriber must be shown
  /// "Actief via web" and no purchase button (App Store guideline 3.1.1).
  final String? proSource;
  final DateTime? proExpiresAt;

  /// Server-side admin flag, straight from `/api/v1/me` and the login
  /// response (`serialiseUser` on the backend). It only decides whether the
  /// admin entry point is *shown*: every `/api/v1/admin/*` call re-checks it
  /// on the server, so a stale or forged `true` here buys nothing.
  final bool isAdmin;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.image,
    this.isPro = false,
    this.proSource,
    this.proExpiresAt,
    this.isAdmin = false,
  });

  /// True when Pro was bought outside the App Store, so the app must not offer
  /// to sell it again.
  bool get isProFromWeb => isPro && (proSource == 'stripe' || proSource == 'admin');

  factory User.fromJson(Map<String, dynamic> json) {
    final expires = json['proExpiresAt'] as String?;
    return User(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      image: json['image'] as String?,
      isPro: json['isPro'] as bool? ?? false,
      proSource: json['proSource'] as String?,
      proExpiresAt: expires == null ? null : DateTime.tryParse(expires),
      isAdmin: json['isAdmin'] as bool? ?? false,
    );
  }

  User copyWith({bool? isPro, String? proSource, DateTime? proExpiresAt}) {
    return User(
      id: id,
      name: name,
      email: email,
      image: image,
      isPro: isPro ?? this.isPro,
      proSource: proSource ?? this.proSource,
      proExpiresAt: proExpiresAt ?? this.proExpiresAt,
      isAdmin: isAdmin,
    );
  }
}
