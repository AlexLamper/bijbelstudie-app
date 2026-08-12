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
  // Raw palette — light (the site's default theme)
  // ---------------------------------------------------------------------

  /// `--background` — the page behind everything.
  static const Color paper = Color(0xFFF3F4F6);

  /// `--card` — every card, header bar and sheet.
  static const Color paperRaised = Color(0xFFFFFFFF);

  /// `--secondary` / `bg-gray-100` — hover fills, skeletons, inactive chips.
  static const Color paperSunken = Color(0xFFF3F4F6);

  /// `bg-gray-200` — the stronger sunken fill (progress tracks, dividers).
  static const Color paperSunkenStrong = Color(0xFFE5E7EB);

  /// `--foreground` / `text-gray-900`.
  static const Color ink = Color(0xFF111827);

  /// `text-gray-700` — secondary body copy.
  static const Color inkSoft = Color(0xFF374151);

  /// `--muted-foreground` / `text-gray-500`.
  static const Color inkMuted = Color(0xFF6B7280);

  /// `text-gray-400` — the faintest label tier the site uses.
  static const Color inkFaint = Color(0xFF9CA3AF);

  /// Text on a solid ink/teal surface.
  static const Color inkInverted = Color(0xFFFFFFFF);

  /// `--border` / `border-gray-200`.
  static const Color rule = Color(0xFFE5E7EB);

  /// `border-gray-300`.
  static const Color ruleStrong = Color(0xFFD1D5DB);

  // --- Brand teal --------------------------------------------------------

  /// `#0D9488` — teal-600. The brand colour, hardcoded all over the site.
  static const Color teal = Color(0xFF0D9488);

  /// `#0F766E` — teal-700. The dark stop of the dashboard hero gradient.
  static const Color tealStrong = Color(0xFF0F766E);

  /// `rgba(13,148,136,0.08)` flattened on white — icon chips, active tabs.
  static const Color tealTint = Color(0xFFF0FDFA);

  /// `bg-teal-100` — the study-mode strip.
  static const Color tealSoft = Color(0xFFCCFBF1);

  /// Legacy alias kept so older call sites keep compiling.
  static const Color lapis = teal;
  static const Color lapisStrong = tealStrong;
  static const Color lapisTint = tealTint;

  // --- Accents -----------------------------------------------------------

  /// `#EA580C` — orange-600, the streak flame.
  static const Color flame = Color(0xFFEA580C);

  /// `rgba(234,88,12,0.08)` flattened — the streak pill background.
  static const Color flameTint = Color(0xFFFFF7ED);

  /// Legacy aliases.
  static const Color vermilion = flame;
  static const Color vermilionStrong = Color(0xFFC2410C);
  static const Color vermilionTint = flameTint;

  /// `#059669` — emerald-600, used for completed / positive states.
  static const Color positive = Color(0xFF059669);
  static const Color positiveTint = Color(0xFFECFDF5);

  /// `--destructive` — `hsl(0 72% 51%)`.
  static const Color destructive = Color(0xFFDC2626);
  static const Color destructiveTint = Color(0xFFFEF2F2);

  /// `#7C3AED` — violet-600, the AI-assistent accent.
  static const Color ai = Color(0xFF7C3AED);
  static const Color aiTint = Color(0xFFF5F3FF);

  // ---------------------------------------------------------------------
  // Raw palette — dark (`.dark`)
  // ---------------------------------------------------------------------

  static const Color darkPaper = Color(0xFF171717);
  static const Color darkPaperRaised = Color(0xFF212121);
  static const Color darkPaperSunken = Color(0xFF2E2E2E);
  static const Color darkPaperSunkenStrong = Color(0xFF333333);
  static const Color darkInk = Color(0xFFE5E5E5);
  static const Color darkInkSoft = Color(0xFFCCCCCC);
  static const Color darkInkMuted = Color(0xFF808080);
  static const Color darkInkFaint = Color(0xFF6B6B6B);
  static const Color darkInkInverted = Color(0xFF171717);
  static const Color darkRule = Color(0xFF383838);
  static const Color darkRuleStrong = Color(0xFF4A4A4A);

  /// `hsl(174 60% 44%)` — the dark-mode brand/ring value.
  static const Color darkTeal = Color(0xFF2DB4A6);
  static const Color darkTealStrong = Color(0xFF14B8A6);
  static const Color darkTealTint = Color(0xFF11312E);

  static const Color darkLapis = darkTeal;
  static const Color darkLapisStrong = darkTealStrong;
  static const Color darkLapisTint = darkTealTint;

  static const Color darkFlame = Color(0xFFFB923C);
  static const Color darkVermilion = darkFlame;
  static const Color darkPositive = Color(0xFF34D399);

  /// `--destructive` in `.dark` — `hsl(0 62% 35%)`.
  static const Color darkDestructive = Color(0xFF901F1F);

  static const Color darkAi = Color(0xFFA78BFA);

  // ---------------------------------------------------------------------
  // Semantic aliases
  // ---------------------------------------------------------------------

  /// Page background — `bg-background`.
  static const Color canvas = paper;

  /// Card background — `bg-card` / `bg-white`.
  static const Color surface = paperRaised;

  /// Muted text — `text-muted-foreground`.
  static const Color muted = inkMuted;

  /// Hairline — `border-border`.
  static const Color border = rule;

  /// Brand accent — teal.
  static const Color accent = teal;

  /// Accent wash.
  static const Color accentSoft = tealTint;

  /// Active filter chip on the site is the brand teal, not ink.
  static const Color filterActive = teal;

  static const Color success = positive;
  static const Color warning = flame;
  static const Color error = destructive;

  /// The brand surface is teal.
  static const Color brand = teal;
  static const Color brandDeep = tealStrong;
  static const Color brandLight = Color(0xFF14B8A6);

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
  static const LinearGradient brandGradient = LinearGradient(
    colors: [teal, tealStrong],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = brandGradient;

  /// Status bar / nav bar styling matching the page background.
  static const SystemUiOverlayStyle overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: paper,
    systemNavigationBarIconBrightness: Brightness.dark,
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
  static const TextStyle displayLarge = TextStyle(
    fontFamily: displayFontName,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.6,
    color: ink,
  );

  /// `text-2xl font-bold` — hero card title.
  static const TextStyle displayMedium = TextStyle(
    fontFamily: displayFontName,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.4,
    color: ink,
  );

  /// `text-xl font-bold` — page heading (`Goedemorgen, …`) and stat values.
  static const TextStyle displaySmall = TextStyle(
    fontFamily: displayFontName,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.25,
    color: ink,
  );

  /// `text-base font-bold` — card titles.
  static const TextStyle displayTitle = TextStyle(
    fontFamily: displayFontName,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.35,
    color: ink,
  );

  /// `text-sm font-bold` — dense card titles.
  static const TextStyle displayBase = TextStyle(
    fontFamily: displayFontName,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.4,
    color: ink,
  );

  /// `text-xl font-bold tabular-nums` — the stat numbers.
  static const TextStyle statNumber = TextStyle(
    fontFamily: displayFontName,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.25,
    color: ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// `text-xs font-semibold uppercase tracking-widest text-gray-400`
  static const TextStyle eyebrow = TextStyle(
    fontFamily: sansFontName,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    color: inkFaint,
  );

  /// `text-[10px] font-semibold uppercase tracking-wider`
  static const TextStyle overline = TextStyle(
    fontFamily: sansFontName,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: inkFaint,
  );

  /// `text-xs font-semibold uppercase tracking-wider text-gray-400`
  static const TextStyle metaLabel = TextStyle(
    fontFamily: sansFontName,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.9,
    color: inkFaint,
  );

  /// `text-[15px] text-muted-foreground`
  static const TextStyle bodyLead = TextStyle(
    fontFamily: sansFontName,
    fontSize: 15,
    height: 1.6,
    color: inkMuted,
  );

  /// `text-sm text-muted-foreground`
  static const TextStyle bodyMuted = TextStyle(
    fontFamily: sansFontName,
    fontSize: 14,
    height: 1.55,
    color: inkMuted,
  );

  /// `text-sm font-semibold text-foreground`
  static const TextStyle bodyStrong = TextStyle(
    fontFamily: sansFontName,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.45,
    color: ink,
  );

  /// `text-xs text-muted-foreground`
  static const TextStyle caption = TextStyle(
    fontFamily: sansFontName,
    fontSize: 12,
    height: 1.45,
    color: inkMuted,
  );

  /// Button label — `text-sm font-semibold`.
  static const TextStyle buttonLabel = TextStyle(
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
    bg: paper,
    card: paperRaised,
    sunken: paperSunkenStrong,
    fg: ink,
    fgSoft: inkSoft,
    fgMuted: inkMuted,
    fgInverted: inkInverted,
    line: rule,
    lineStrong: ruleStrong,
    ring: teal,
    danger: destructive,
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
