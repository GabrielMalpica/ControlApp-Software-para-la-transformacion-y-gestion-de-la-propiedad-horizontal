import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF0C6B43);
  static const Color primaryDark = Color(0xFF084D31);
  static const Color secondary = Color(0xFF0F8A74);
  static const Color accent = Color(0xFFF2B84B);
  static const Color background = Color(0xFFF4F8F4);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSoft = Color(0xFFE8F1EB);
  static const Color text = Color(0xFF163126);
  static const Color textMuted = Color(0xFF5E7467);
  static const Color yellow = accent;
  static const Color red = Color(0xFFD65B4A);
  static const Color green = Color(0xFF2E7D32);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xFFEFF7F1),
      Color(0xFFDCEEE3),
      Color(0xFFF8EED4),
    ],
  );

  static final ButtonStyle saveButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: primary,
    foregroundColor: Colors.white,
    disabledBackgroundColor: primary.withValues(alpha: 0.45),
    disabledForegroundColor: Colors.white70,
    elevation: 0,
    shadowColor: Colors.transparent,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    minimumSize: const Size(0, 42),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      secondary: secondary,
      surface: surface,
      error: red,
    );

    const baseTextTheme = TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: text,
        letterSpacing: -0.6,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: text,
        letterSpacing: -0.4,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.45,
        color: text,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.45,
        color: text,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.4,
        color: textMuted,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: text,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: baseTextTheme,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: _AppPageTransitionsBuilder(),
          TargetPlatform.iOS: _AppPageTransitionsBuilder(),
          TargetPlatform.macOS: _AppPageTransitionsBuilder(),
          TargetPlatform.windows: _AppPageTransitionsBuilder(),
          TargetPlatform.linux: _AppPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        shadowColor: const Color(0x14084D31),
      ),
      dividerTheme: DividerThemeData(
        color: primary.withValues(alpha: 0.08),
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: primary.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: primary.withValues(alpha: 0.16)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryDark,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: const TextStyle(color: textMuted),
        hintStyle: const TextStyle(color: textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: primary.withValues(alpha: 0.10)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: primary.withValues(alpha: 0.10)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: red),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: red, width: 1.4),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: const TextStyle(color: text, fontWeight: FontWeight.w600),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: primary.withValues(alpha: 0.10)),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: primaryDark,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: text,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 14,
          height: 1.45,
          color: text,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceSoft,
        selectedColor: primary.withValues(alpha: 0.12),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        labelStyle: const TextStyle(color: text, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: surfaceSoft,
      ),
    );
  }
}

class _AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const _AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.settings.name == '/') {
      return child;
    }

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: Tween<double>(begin: 0.82, end: 1).animate(curved),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
