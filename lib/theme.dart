import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The app's whole visual language, so no screen invents its own colours.
///
/// The two brightnesses are built from one set of rules rather than tuned
/// separately: each defines a stack of surface tiers, and every foreground
/// tone is chosen against the tier it sits on. That is what keeps text
/// readable in both, instead of a dark theme that was checked and a light
/// theme that was assumed.
class AppTheme {
  AppTheme._();

  /// Indigo. Confident and quiet -- workplace software, not a consumer app.
  static const seed = Color(0xFF4F6BF0);
  static const seedDeep = Color(0xFF3B4FD8);
  static const accent = Color(0xFF00C2A8);

  static const positive = Color(0xFF16A34A);
  static const caution = Color(0xFFD97706);
  static const negative = Color(0xFFDC2626);

  /// Lifted variants for dark surfaces. The light-theme status colours are
  /// tuned for white backgrounds and go muddy on near-black, so each has a
  /// brighter twin rather than being reused with opacity.
  static const positiveDark = Color(0xFF4ADE80);
  static const cautionDark = Color(0xFFFBBF24);
  static const negativeDark = Color(0xFFF87171);

  static const _radius = 18.0;

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: seedDeep,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFE0E5FE),
      onPrimaryContainer: Color(0xFF1B2A8A),
      secondary: Color(0xFF00897B),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFD3F3EE),
      onSecondaryContainer: Color(0xFF00443C),
      error: negative,
      onError: Colors.white,
      errorContainer: Color(0xFFFEE2E2),
      onErrorContainer: Color(0xFF7F1D1D),
      surface: Colors.white,
      onSurface: Color(0xFF11151F),
      onSurfaceVariant: Color(0xFF5A6376),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFFBFCFE),
      surfaceContainer: Color(0xFFF4F6FA),
      surfaceContainerHigh: Color(0xFFEDF0F6),
      surfaceContainerHighest: Color(0xFFE6EAF2),
      outline: Color(0xFF8A93A6),
      outlineVariant: Color(0xFFD7DCE7),
      shadow: Color(0xFF0B1020),
      inverseSurface: Color(0xFF1B2030),
      onInverseSurface: Color(0xFFF1F3F8),
    );

    return _build(
      scheme: scheme,
      scaffold: const Color(0xFFF2F5FA),
      card: Colors.white,
      border: const Color(0xFFE3E8F1),
      shadowOpacity: 0.07,
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF9FB0FF),
      onPrimary: Color(0xFF14205E),
      primaryContainer: Color(0xFF2C3A9E),
      onPrimaryContainer: Color(0xFFDDE3FF),
      secondary: Color(0xFF5EE0CD),
      onSecondary: Color(0xFF00352E),
      secondaryContainer: Color(0xFF00544A),
      onSecondaryContainer: Color(0xFFB4F2E8),
      error: negativeDark,
      onError: Color(0xFF5F1414),
      errorContainer: Color(0xFF7F1D1D),
      onErrorContainer: Color(0xFFFEE2E2),
      surface: Color(0xFF14161C),
      // Not pure white: at these sizes it vibrates against a near-black
      // background, and a hair of warmth reads as calmer over long sessions.
      onSurface: Color(0xFFECEFF6),
      onSurfaceVariant: Color(0xFF9BA4B8),
      surfaceContainerLowest: Color(0xFF0C0E13),
      surfaceContainerLow: Color(0xFF12141A),
      surfaceContainer: Color(0xFF191C24),
      surfaceContainerHigh: Color(0xFF21252F),
      surfaceContainerHighest: Color(0xFF2A2F3B),
      outline: Color(0xFF6B7488),
      outlineVariant: Color(0xFF333947),
      shadow: Colors.black,
      inverseSurface: Color(0xFFECEFF6),
      onInverseSurface: Color(0xFF1B2030),
    );

    return _build(
      scheme: scheme,
      scaffold: const Color(0xFF0B0D12),
      card: const Color(0xFF161920),
      border: const Color(0xFF262B36),
      shadowOpacity: 0.5,
    );
  }

  static ThemeData _build({
    required ColorScheme scheme,
    required Color scaffold,
    required Color card,
    required Color border,
    required double shadowOpacity,
  }) {
    final isDark = scheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      fontFamily: 'Inter',
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(scheme),
      extensions: [
        AppSurfaces(
          card: card,
          border: border,
          shadow: BoxShadow(
            color: scheme.shadow.withValues(alpha: shadowOpacity),
            blurRadius: isDark ? 24 : 18,
            offset: const Offset(0, 6),
            spreadRadius: isDark ? -6 : -4,
          ),
          positive: isDark ? positiveDark : positive,
          caution: isDark ? cautionDark : caution,
          negative: isDark ? negativeDark : negative,
          heroGradient: isDark
              ? const [Color(0xFF3A48B8), Color(0xFF23306F)]
              : const [Color(0xFF5A72F5), Color(0xFF3B4FD8)],
        ),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: BorderSide(color: border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF12141A) : Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.14),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            letterSpacing: 0.1,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primary.withValues(alpha: isDark ? 0.26 : 0.14),
        checkmarkColor: scheme.primary,
        side: BorderSide(color: border),
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1A1E27) : const Color(0xFFF4F6FA),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          fontWeight: FontWeight.w400,
        ),
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
        highlightElevation: 6,
        extendedTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: scheme.onSurfaceVariant,
        ),
      ),
      dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: scheme.primary, width: 2.5),
          insets: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
      ),
    );
  }

  /// A tightened type scale. Flutter's defaults are set for Roboto and run
  /// loose for Inter, whose larger x-height needs less tracking and slightly
  /// tighter line heights before it reads as "designed" rather than "default".
  static TextTheme _textTheme(ColorScheme scheme) {
    final base = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;

    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
        color: base,
      ),
      headlineMedium: TextStyle(
        fontSize: 27,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
        color: base,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: base,
      ),
      titleLarge: TextStyle(
        fontSize: 19,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: base,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: base,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        height: 1.35,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: base,
      ),
      bodyLarge: TextStyle(
        fontSize: 15.5,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: base,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: base,
      ),
      bodySmall: TextStyle(
        fontSize: 12.5,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: muted,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: base,
      ),
      labelMedium: TextStyle(
        fontSize: 12.5,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: muted,
      ),

      /// Section eyebrows: small, heavy, wide-tracked. Tracking is what keeps
      /// uppercase legible once it is this small.
      labelSmall: TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
        color: muted,
      ),
    );
  }
}

/// Tokens Material's [ColorScheme] has no slot for, carried on the theme so
/// widgets read them from context instead of importing constants and picking
/// the wrong brightness.
@immutable
class AppSurfaces extends ThemeExtension<AppSurfaces> {
  const AppSurfaces({
    required this.card,
    required this.border,
    required this.shadow,
    required this.positive,
    required this.caution,
    required this.negative,
    required this.heroGradient,
  });

  final Color card;
  final Color border;
  final BoxShadow shadow;
  final Color positive;
  final Color caution;
  final Color negative;
  final List<Color> heroGradient;

  static AppSurfaces of(BuildContext context) =>
      Theme.of(context).extension<AppSurfaces>()!;

  @override
  AppSurfaces copyWith({
    Color? card,
    Color? border,
    BoxShadow? shadow,
    Color? positive,
    Color? caution,
    Color? negative,
    List<Color>? heroGradient,
  }) => AppSurfaces(
    card: card ?? this.card,
    border: border ?? this.border,
    shadow: shadow ?? this.shadow,
    positive: positive ?? this.positive,
    caution: caution ?? this.caution,
    negative: negative ?? this.negative,
    heroGradient: heroGradient ?? this.heroGradient,
  );

  @override
  AppSurfaces lerp(ThemeExtension<AppSurfaces>? other, double t) {
    if (other is! AppSurfaces) return this;
    return AppSurfaces(
      card: Color.lerp(card, other.card, t)!,
      border: Color.lerp(border, other.border, t)!,
      shadow: BoxShadow.lerp(shadow, other.shadow, t)!,
      positive: Color.lerp(positive, other.positive, t)!,
      caution: Color.lerp(caution, other.caution, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
      heroGradient: [
        Color.lerp(heroGradient.first, other.heroGradient.first, t)!,
        Color.lerp(heroGradient.last, other.heroGradient.last, t)!,
      ],
    );
  }
}
