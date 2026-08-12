/// Reading preferences, mirroring `User.preferences` on the backend.
///
/// Field names and the value scales (`base`, `relaxed`, ...) match
/// `lib/preferenceClasses.ts` on the website, so a setting changed on the
/// phone reads back correctly in the browser.
class ReadingPreferences {
  final String translation;
  final String commentary;
  final String fontSize;
  final String fontFamily;
  final String lineHeight;
  final String letterSpacing;
  final bool highContrast;
  final bool showVerseNumbers;

  const ReadingPreferences({
    this.translation = 'statenvertaling',
    this.commentary = 'matthew_henry_nl',
    this.fontSize = 'base',
    this.fontFamily = 'serif',
    this.lineHeight = 'relaxed',
    this.letterSpacing = 'normal',
    this.highContrast = false,
    this.showVerseNumbers = true,
  });

  factory ReadingPreferences.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    return ReadingPreferences(
      translation: data['translation'] as String? ?? 'statenvertaling',
      commentary: data['commentary'] as String? ?? 'matthew_henry_nl',
      fontSize: data['fontSize'] as String? ?? 'base',
      fontFamily: data['fontFamily'] as String? ?? 'serif',
      lineHeight: data['lineHeight'] as String? ?? 'relaxed',
      letterSpacing: data['letterSpacing'] as String? ?? 'normal',
      highContrast: data['highContrast'] as bool? ?? false,
      showVerseNumbers: data['showVerseNumbers'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'translation': translation,
    'commentary': commentary,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'lineHeight': lineHeight,
    'letterSpacing': letterSpacing,
    'highContrast': highContrast,
    'showVerseNumbers': showVerseNumbers,
  };

  ReadingPreferences copyWith({
    String? translation,
    String? commentary,
    String? fontSize,
    String? fontFamily,
    String? lineHeight,
    String? letterSpacing,
    bool? highContrast,
    bool? showVerseNumbers,
  }) {
    return ReadingPreferences(
      translation: translation ?? this.translation,
      commentary: commentary ?? this.commentary,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      lineHeight: lineHeight ?? this.lineHeight,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      highContrast: highContrast ?? this.highContrast,
      showVerseNumbers: showVerseNumbers ?? this.showVerseNumbers,
    );
  }
}

/// `GET /api/v1/me`. Verified against the running backend, not inferred from
/// the route name.
class ProfileModel {
  final String id;
  final String name;
  final String email;
  final String? image;
  final bool isPro;
  final String? proSource;
  final DateTime? proExpiresAt;
  final ReadingPreferences preferences;

  const ProfileModel({
    required this.id,
    required this.name,
    required this.email,
    this.image,
    required this.isPro,
    this.proSource,
    this.proExpiresAt,
    this.preferences = const ReadingPreferences(),
  });

  /// Pro bought outside the App Store. Apple's multiplatform exception lets
  /// these users keep access; the app must not try to sell to them.
  bool get isProFromWeb => isPro && (proSource == 'stripe' || proSource == 'admin');

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    final expires = json['proExpiresAt'] as String?;
    return ProfileModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      image: json['image'] as String?,
      isPro: json['isPro'] as bool? ?? false,
      proSource: json['proSource'] as String?,
      proExpiresAt: expires == null ? null : DateTime.tryParse(expires),
      preferences: ReadingPreferences.fromJson(
        json['preferences'] as Map<String, dynamic>?,
      ),
    );
  }
}
