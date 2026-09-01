import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design tokens copied 1:1 from www.bijbel-studie.com (`app/globals.css`).
///
/// The site is a shadcn/Tailwind "Slate & Teal" system: a light grey page,
/// white cards with a 1px grey border and generous corner radii, Inter for
/// everything, bold weights for hierarchy, and teal `#0D9488` as the single
/// brand accent.
///
/// CSS reference (`:root`):
///   --background 220 9% 96%   #F3F4F6      --foreground 222 47% 11%  #111827
///   --card #FFFFFF                          --muted-foreground 220 9% 46% #6B7280
///   --secondary 220 13% 91%   #E5E7EB       --border 220 13% 91%      #E5E7EB
///   --brand / --ring 174 77% 31%            (used in markup as #0D9488)
///   --destructive 0 72% 51%   #DC2626       --radius .5rem
///
/// `.dark`:
///   --background #171717  --card #212121  --secondary #2E2E2E
///   --foreground #E5E5E5  --muted-foreground #808080  --border #383838
///   --brand / --ring 174 60% 44%  #2DB4A6
class AppTheme {
  // ---------------------------------------------------------------------
  // Typefaces — the site loads Inter (sans), Lora (serif), Merriweather.
  // Headings are Inter bold, not a serif display face.
  // ---------------------------------------------------------------------

  /// Body / UI / heading face — `--font-inter`, `font-sans`.
  static const String sansFontName = 'Inter';

  /// Headings on the site are Inter too; kept as its own name so screens can
  /// express intent.
  static const String displayFontName = 'Inter';

  /// Reader "serif" preference — `--font-lora`, `font-serif`.
  static const String serifFontName = 'Lora';

  /// Reader "mono" preference — `font-mono`.
  static const String monoFontName = 'Geist Mono';

  // ---------------------------------------------------------------------
  // Brightness resolution
  //
  // The semantic names below (`AppTheme.ink`, `AppTheme.paper`,
  // `AppTheme.bodyMuted`, ...) are used directly by some four hundred call
  // sites, and a `const` cannot depend on brightness. App review 1.0 (7) was
  // rejected under guideline 4 for exactly that: every one of those names
  // baked a light colour and painted near-black on the dark scaffold.
  //
  // So they are getters resolved against one app-wide flag, set from the root
  // widget in main.dart before MaterialApp builds and on every theme change.
  // The raw `lightX` / `darkX` values stay `const`; they are what the two
  // ThemeData objects - and the contrast tests - are built from.
  // ---------------------------------------------------------------------

  static Brightness _brightness = Brightness.light;

  /// The brightness every semantic token below resolves against.
  static Brightness get brightness => _brightness;

  static bool get isDark => _brightness == Brightness.dark;

  /// Points the semantic tokens at [value].
  ///
  /// Returns true when the value actually changed, so a caller that has to
  /// force a repaint can tell whether it needs to.
  static bool applyBrightness(Brightness value) {
    if (_brightness == value) return false;
    _brightness = value;
    return true;
  }

  static Color _c(Color light, Color dark) =>
      _brightness == Brightness.dark ? dark : light;

  // ---------------------------------------------------------------------
  // Raw palette - light (the site's default theme)
  // ---------------------------------------------------------------------

  /// `--background` - the page behind everything.
  static const Color lightPaper = Color(0xFFF3F4F6);

  /// `--card` - every card, header bar and sheet.
  static const Color lightPaperRaised = Color(0xFFFFFFFF);

  /// `--secondary` / `bg-gray-100` - hover fills, skeletons, inactive chips.
  static const Color lightPaperSunken = Color(0xFFF3F4F6);

  /// `bg-gray-200` - the stronger sunken fill (progress tracks, dividers).
  static const Color lightPaperSunkenStrong = Color(0xFFE5E7EB);

  /// `--foreground` / `text-gray-900`.
  static const Color lightInk = Color(0xFF111827);

  /// `text-gray-700` - secondary body copy.
  static const Color lightInkSoft = Color(0xFF374151);

  /// `--muted-foreground` / `text-gray-500`.
  static const Color lightInkMuted = Color(0xFF6B7280);

  /// `text-gray-400` - the faintest label tier the site uses.
  static const Color lightInkFaint = Color(0xFF9CA3AF);

  /// Text on a solid ink/teal surface.
  static const Color lightInkInverted = Color(0xFFFFFFFF);

  /// `--border` / `border-gray-200`.
  static const Color lightRule = Color(0xFFE5E7EB);

  /// `border-gray-300`.
  static const Color lightRuleStrong = Color(0xFFD1D5DB);

  /// `#0D9488` - teal-600. The brand colour, hardcoded all over the site.
  static const Color lightTeal = Color(0xFF0D9488);

  /// `#0F766E` - teal-700. The dark stop of the dashboard hero gradient.
  static const Color lightTealStrong = Color(0xFF0F766E);

  /// `rgba(13,148,136,0.08)` flattened on white - icon chips, active tabs.
  static const Color lightTealTint = Color(0xFFF0FDFA);

  /// `bg-teal-100` - the study-mode strip.
  static const Color lightTealSoft = Color(0xFFCCFBF1);

  /// `#EA580C` - orange-600, the streak flame.
  static const Color lightFlame = Color(0xFFEA580C);

  /// `rgba(234,88,12,0.08)` flattened - the streak pill background.
  static const Color lightFlameTint = Color(0xFFFFF7ED);

  static const Color lightVermilionStrong = Color(0xFFC2410C);

  /// `#059669` - emerald-600, used for completed / positive states.
  static const Color lightPositive = Color(0xFF059669);
  static const Color lightPositiveTint = Color(0xFFECFDF5);

  /// `--destructive` - `hsl(0 72% 51%)`.
  static const Color lightDestructive = Color(0xFFDC2626);
  static const Color lightDestructiveTint = Color(0xFFFEF2F2);

  /// `#7C3AED` - violet-600, the AI-assistent accent.
  static const Color lightAi = Color(0xFF7C3AED);
  static const Color lightAiTint = Color(0xFFF5F3FF);

  static const Color lightBrandLight = Color(0xFF14B8A6);

  // ---------------------------------------------------------------------
  // Raw palette - dark (`.dark`)
  //
  // The foreground tiers are lighter than the site's `.dark` values on
  // purpose: `--muted-foreground` there is `#808080`, which clears 3:1 but
  // not the 4.5:1 body text needs on `#333333`.
  // test/dark_mode_contrast_test.dart holds the line.
  // ---------------------------------------------------------------------

  static const Color darkPaper = Color(0xFF171717);
  static const Color darkPaperRaised = Color(0xFF212121);
  static const Color darkPaperSunken = Color(0xFF2E2E2E);
  static const Color darkPaperSunkenStrong = Color(0xFF333333);
  static const Color darkInk = Color(0xFFE5E5E5);
  static const Color darkInkSoft = Color(0xFFCCCCCC);

  /// AA body text (4.5:1) on every dark surface, `#333333` included.
  static const Color darkInkMuted = Color(0xFFABABAB);

  /// The faintest dark tier that still clears 4.5:1 on `#333333`. The label
  /// styles (eyebrow, overline, metaLabel) resolve to it and all sit below
  /// the large-text size, so they need the full body ratio.
  static const Color darkInkFaint = Color(0xFF9C9C9C);

  static const Color darkInkInverted = Color(0xFF171717);
  static const Color darkRule = Color(0xFF383838);
  static const Color darkRuleStrong = Color(0xFF4A4A4A);

  /// `hsl(174 60% 44%)` - the dark-mode brand/ring value.
  static const Color darkTeal = Color(0xFF2DB4A6);
  static const Color darkTealStrong = Color(0xFF14B8A6);
  static const Color darkTealTint = Color(0xFF11312E);
  static const Color darkTealSoft = Color(0xFF14453F);

  static const Color darkLapis = darkTeal;
  static const Color darkLapisStrong = darkTealStrong;
  static const Color darkLapisTint = darkTealTint;

  static const Color darkFlame = Color(0xFFFB923C);
  static const Color darkFlameTint = Color(0xFF3A2413);
  static const Color darkVermilion = darkFlame;
  static const Color darkVermilionStrong = Color(0xFFFDBA74);
  static const Color darkPositive = Color(0xFF34D399);
  static const Color darkPositiveTint = Color(0xFF10312A);

  /// `--destructive` in `.dark` - `hsl(0 62% 35%)`.
  static const Color darkDestructive = Color(0xFF901F1F);
  static const Color darkDestructiveTint = Color(0xFF3A1A1A);

  static const Color darkAi = Color(0xFFA78BFA);
  static const Color darkAiTint = Color(0xFF2A2140);

  static const Color darkBrandLight = Color(0xFF2DD4BF);

  // ---------------------------------------------------------------------
  // Palette - resolved against the current brightness
  //
  // These are the names every screen uses. Do not turn them back into
  // consts: that is the guideline 4 rejection.
  // ---------------------------------------------------------------------

  static Color get paper => _c(lightPaper, darkPaper);
  static Color get paperRaised => _c(lightPaperRaised, darkPaperRaised);
  static Color get paperSunken => _c(lightPaperSunken, darkPaperSunken);
  static Color get paperSunkenStrong =>
      _c(lightPaperSunkenStrong, darkPaperSunkenStrong);

  static Color get ink => _c(lightInk, darkInk);
  static Color get inkSoft => _c(lightInkSoft, darkInkSoft);
  static Color get inkMuted => _c(lightInkMuted, darkInkMuted);
  static Color get inkFaint => _c(lightInkFaint, darkInkFaint);
  static Color get inkInverted => _c(lightInkInverted, darkInkInverted);

  static Color get rule => _c(lightRule, darkRule);
  static Color get ruleStrong => _c(lightRuleStrong, darkRuleStrong);

  static Color get teal => _c(lightTeal, darkTeal);
  static Color get tealStrong => _c(lightTealStrong, darkTealStrong);
  static Color get tealTint => _c(lightTealTint, darkTealTint);
  static Color get tealSoft => _c(lightTealSoft, darkTealSoft);

  /// Legacy aliases kept so older call sites keep compiling.
  static Color get lapis => teal;
  static Color get lapisStrong => tealStrong;
  static Color get lapisTint => tealTint;

  static Color get flame => _c(lightFlame, darkFlame);
  static Color get flameTint => _c(lightFlameTint, darkFlameTint);
  static Color get vermilion => flame;
  static Color get vermilionStrong =>
      _c(lightVermilionStrong, darkVermilionStrong);
  static Color get vermilionTint => flameTint;

  static Color get positive => _c(lightPositive, darkPositive);
  static Color get positiveTint => _c(lightPositiveTint, darkPositiveTint);

  static Color get destructive => _c(lightDestructive, darkDestructive);
  static Color get destructiveTint =>
      _c(lightDestructiveTint, darkDestructiveTint);

  static Color get ai => _c(lightAi, darkAi);
  static Color get aiTint => _c(lightAiTint, darkAiTint);

  // ---------------------------------------------------------------------
  // Semantic aliases
  // ---------------------------------------------------------------------

  /// Page background - `bg-background`.
  static Color get canvas => paper;

  /// Card background - `bg-card` / `bg-white`.
  static Color get surface => paperRaised;

  /// Muted text - `text-muted-foreground`.
  static Color get muted => inkMuted;

  /// Hairline - `border-border`.
  static Color get border => rule;

  /// Brand accent - teal.
  static Color get accent => teal;

  /// Accent wash.
  static Color get accentSoft => tealTint;

  /// Active filter chip on the site is the brand teal, not ink.
  static Color get filterActive => teal;

  static Color get success => positive;
  static Color get warning => flame;
  static Color get error => destructive;

  /// The brand surface is teal.
  static Color get brand => teal;
  static Color get brandDeep => tealStrong;
  static Color get brandLight => _c(lightBrandLight, darkBrandLight);

  // ---------------------------------------------------------------------
  // Radii — Tailwind's scale, as used in the markup
  // ---------------------------------------------------------------------

  /// `rounded-2xl` — cards, hero panels, sheets.
  static const double radiusLg = 16;

  /// `rounded-xl` — buttons, inputs, small cards.
  static const double radiusMd = 12;

  /// `rounded-lg` — icon chips, badges.
  static const double radiusSm = 8;

  /// `rounded-md` — the tightest corner the site uses.
  static const double radiusXs = 6;

  /// `rounded-full` pills.
  static const double radiusPill = 999;

  // ---------------------------------------------------------------------
  // Gradients
  // ---------------------------------------------------------------------

  /// `linear-gradient(135deg, #0D9488 0%, #0F766E 100%)` — the dashboard hero
  /// and every "continue reading" call to action.
  static LinearGradient get brandGradient => LinearGradient(
    colors: [teal, tealStrong],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get accentGradient => brandGradient;

  /// Status bar / nav bar styling matching the page background.
  static SystemUiOverlayStyle get overlayStyle => SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    // The icon brightness is the brightness of the *icons*, so it is the
    // opposite of the surface they sit on.
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: paper,
    systemNavigationBarIconBrightness: isDark
        ? Brightness.light
        : Brightness.dark,
  );

  static TextStyle monoTextStyle([TextStyle? baseStyle]) {
    return (baseStyle ?? const TextStyle()).copyWith(
      fontFamily: sansFontName,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  // ---------------------------------------------------------------------
  // Type scale — mirrors the utility classes used on the site
  // ---------------------------------------------------------------------

  /// `text-3xl font-bold` — marketing / empty-state hero.
  static TextStyle get displayLarge => TextStyle(
    fontFamily: displayFontName,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.6,
    color: ink,
  );

  /// `text-2xl font-bold` — hero card title.
  static TextStyle get displayMedium => TextStyle(
    fontFamily: displayFontName,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.4,
    color: ink,
  );

  /// `text-xl font-bold` — page heading (`Goedemorgen, …`) and stat values.
  static TextStyle get displaySmall => TextStyle(
    fontFamily: displayFontName,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.25,
    color: ink,
  );

  /// `text-base font-bold` — card titles.
  static TextStyle get displayTitle => TextStyle(
    fontFamily: displayFontName,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.35,
    color: ink,
  );

  /// `text-sm font-bold` — dense card titles.
  static TextStyle get displayBase => TextStyle(
    fontFamily: displayFontName,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.4,
    color: ink,
  );

  /// `text-xl font-bold tabular-nums` — the stat numbers.
  static TextStyle get statNumber => TextStyle(
    fontFamily: displayFontName,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.25,
    color: ink,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// `text-xs font-semibold uppercase tracking-widest text-gray-400`
  static TextStyle get eyebrow => TextStyle(
    fontFamily: sansFontName,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    color: inkFaint,
  );

  /// `text-[10px] font-semibold uppercase tracking-wider`
  static TextStyle get overline => TextStyle(
    fontFamily: sansFontName,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: inkFaint,
  );

  /// `text-xs font-semibold uppercase tracking-wider text-gray-400`
  static TextStyle get metaLabel => TextStyle(
    fontFamily: sansFontName,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.9,
    color: inkFaint,
  );

  /// `text-[15px] text-muted-foreground`
  static TextStyle get bodyLead => TextStyle(
    fontFamily: sansFontName,
    fontSize: 15,
    height: 1.6,
    color: inkMuted,
  );

  /// `text-sm text-muted-foreground`
  static TextStyle get bodyMuted => TextStyle(
    fontFamily: sansFontName,
    fontSize: 14,
    height: 1.55,
    color: inkMuted,
  );

  /// `text-sm font-semibold text-foreground`
  static TextStyle get bodyStrong => TextStyle(
    fontFamily: sansFontName,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.45,
    color: ink,
  );

  /// `text-xs text-muted-foreground`
  static TextStyle get caption => TextStyle(
    fontFamily: sansFontName,
    fontSize: 12,
    height: 1.45,
    color: inkMuted,
  );

  /// Button label — `text-sm font-semibold`.
  static TextStyle get buttonLabel => TextStyle(
    fontFamily: sansFontName,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  // ---------------------------------------------------------------------
  // ThemeData
  // ---------------------------------------------------------------------

  static ThemeData get lightTheme => _build(
    brightness: Brightness.light,
    bg: lightPaper,
    card: lightPaperRaised,
    sunken: lightPaperSunkenStrong,
    fg: lightInk,
    fgSoft: lightInkSoft,
    fgMuted: lightInkMuted,
    fgInverted: lightInkInverted,
    line: lightRule,
    lineStrong: lightRuleStrong,
    ring: lightTeal,
    danger: lightDestructive,
  );

  static ThemeData get darkTheme => _build(
    brightness: Brightness.dark,
    bg: darkPaper,
    card: darkPaperRaised,
    sunken: darkPaperSunken,
    fg: darkInk,
    fgSoft: darkInkSoft,
    fgMuted: darkInkMuted,
    fgInverted: darkInkInverted,
    line: darkRule,
    lineStrong: darkRuleStrong,
    ring: darkTeal,
    danger: darkDestructive,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color card,
    required Color sunken,
    required Color fg,
    required Color fgSoft,
    required Color fgMuted,
    required Color fgInverted,
    required Color line,
    required Color lineStrong,
    required Color ring,
    required Color danger,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      // `--primary` on the site is near-black in light mode, near-white in
      // dark mode; the *brand* is teal and lives in `secondary`.
      primary: fg,
      onPrimary: fgInverted,
      secondary: ring,
      onSecondary: Colors.white,
      surface: card,
      onSurface: fg,
      surfaceContainerHighest: sunken,
      surfaceContainerHigh: sunken,
      surfaceContainer: card,
      surfaceContainerLow: bg,
      surfaceContainerLowest: bg,
      onSurfaceVariant: fgMuted,
      error: danger,
      onError: Colors.white,
      outline: line,
      outlineVariant: lineStrong,
      shadow: const Color(0x1A000000),
      scrim: const Color(0x80000000),
      inverseSurface: fg,
      onInverseSurface: fgInverted,
      inversePrimary: fgInverted,
    );

    final textTheme = _textTheme(fg, fgMuted);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      fontFamily: sansFontName,
      colorScheme: colorScheme,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      // `h-14 border-b border-border bg-white sticky top-0` — the site header.
      appBarTheme: AppBarTheme(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        foregroundColor: fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 56,
        shape: Border(bottom: BorderSide(color: line)),
        titleTextStyle: TextStyle(
          fontFamily: sansFontName,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
        iconTheme: IconThemeData(color: fgMuted, size: 20),
        systemOverlayStyle: brightness == Brightness.light
            ? overlayStyle.copyWith(systemNavigationBarColor: bg)
            : overlayStyle.copyWith(
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
                systemNavigationBarColor: bg,
                systemNavigationBarIconBrightness: Brightness.light,
              ),
      ),
      // `bg-white border border-gray-200 rounded-2xl` — no shadow.
      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: line),
        ),
      ),
      // `rounded-xl py-3 text-sm font-semibold text-white` on the brand teal.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ring,
          foregroundColor: Colors.white,
          disabledBackgroundColor: ring.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: buttonLabel,
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ring,
          foregroundColor: Colors.white,
          disabledBackgroundColor: ring.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: buttonLabel,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      // `border border-gray-200 bg-white text-foreground hover:bg-secondary`
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: card,
          foregroundColor: fg,
          side: BorderSide(color: line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: buttonLabel,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ring,
          textStyle: buttonLabel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: fgMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),
      // `rounded-xl border border-gray-200 bg-white px-4 h-11
      //  focus:ring-2 focus:ring-teal-600`
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        hintStyle: TextStyle(
          fontFamily: sansFontName,
          fontSize: 14,
          color: fgMuted,
        ),
        labelStyle: TextStyle(
          fontFamily: sansFontName,
          fontSize: 14,
          color: fgMuted,
        ),
        floatingLabelStyle: TextStyle(
          fontFamily: sansFontName,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: ring,
        ),
        prefixIconColor: fgMuted,
        suffixIconColor: fgMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: ring, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: danger, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: ring,
        side: BorderSide(color: line),
        labelStyle: TextStyle(
          fontFamily: sansFontName,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPill),
        ),
        showCheckmark: false,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: ring,
        unselectedItemColor: fgMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(
          fontFamily: sansFontName,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: sansFontName,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: sunken,
        elevation: 0,
        height: 64,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: line),
        ),
        titleTextStyle: TextStyle(
          fontFamily: sansFontName,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: fg,
        ),
        contentTextStyle: TextStyle(
          fontFamily: sansFontName,
          fontSize: 14,
          height: 1.55,
          color: fgMuted,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: fg,
        contentTextStyle: TextStyle(
          fontFamily: sansFontName,
          fontSize: 14,
          color: fgInverted,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: ring,
        linearTrackColor: sunken,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 4,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : card,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? ring : sunken,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? ring : line,
        ),
      ),
      // The site underlines the active tab with a teal 2px rounded bar.
      tabBarTheme: TabBarThemeData(
        labelColor: ring,
        unselectedLabelColor: fgMuted,
        indicatorColor: ring,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: line,
        labelStyle: const TextStyle(
          fontFamily: sansFontName,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: sansFontName,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: fgMuted,
        textColor: fg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: fg,
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        textStyle: TextStyle(
          fontFamily: sansFontName,
          fontSize: 12,
          color: fgInverted,
        ),
      ),
    );
  }

  static TextTheme _textTheme(Color fg, Color fgMuted) {
    TextStyle bold(double size, double lh, double ls) => TextStyle(
      fontFamily: sansFontName,
      fontSize: size,
      height: lh,
      letterSpacing: ls,
      fontWeight: FontWeight.w700,
      color: fg,
    );

    TextStyle sans(
      double size,
      double lh,
      FontWeight w, [
      Color? c,
      double ls = 0,
    ]) => TextStyle(
      fontFamily: sansFontName,
      fontSize: size,
      height: lh,
      fontWeight: w,
      letterSpacing: ls,
      color: c ?? fg,
    );

    return TextTheme(
      displayLarge: bold(36, 1.15, -0.9),
      displayMedium: bold(30, 1.2, -0.6),
      displaySmall: bold(24, 1.25, -0.4),
      headlineLarge: bold(22, 1.3, -0.3),
      headlineMedium: bold(20, 1.3, -0.25),
      headlineSmall: bold(18, 1.35, -0.2),
      titleLarge: bold(16, 1.35, 0),
      titleMedium: sans(15, 1.45, FontWeight.w600),
      titleSmall: sans(14, 1.45, FontWeight.w600),
      bodyLarge: sans(15, 1.6, FontWeight.w400),
      bodyMedium: sans(14, 1.55, FontWeight.w400, fgMuted),
      bodySmall: sans(12, 1.45, FontWeight.w400, fgMuted),
      labelLarge: sans(14, 1.2, FontWeight.w600),
      labelMedium: sans(12, 1.2, FontWeight.w600, fgMuted),
      labelSmall: sans(10, 1.2, FontWeight.w600, fgMuted, 0.8),
    );
  }
}
