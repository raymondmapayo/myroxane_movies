import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  static const midnight = Color(0xFF08090C);
  static const surface = Color(0xFF14161B);
  static const raised = Color(0xFF20232A);
  static const border = Color(0xFF30343D);
  static const ink = Color(0xFFF7F7F3);
  static const muted = Color(0xFFA7A9B0);
  static const brand = Color(0xFFEBEBE4);
  static const focus = Color(0xFFFFFFFF);

  // Compatibility aliases used by feature views.
  static const projector = brand;
  static const orange = brand;
  static const amber = brand;
  static const blue = focus;
}

abstract final class AppShapes {
  static const card = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(6)),
  );

  static const control = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(6)),
  );
}

abstract final class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final body = GoogleFonts.manropeTextTheme(base.textTheme)
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.midnight,
      canvasColor: AppColors.surface,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.projector,
        onPrimary: AppColors.midnight,
        secondary: AppColors.ink,
        onSecondary: AppColors.midnight,
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        error: Color(0xFFFF8D8D),
        outline: AppColors.border,
        outlineVariant: Color(0xFF252830),
      ),
      textTheme: body,
      iconTheme: const IconThemeData(color: AppColors.ink, size: 21),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.midnight.withValues(alpha: .94),
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        toolbarHeight: 66,
        titleTextStyle: GoogleFonts.archivo(
          color: AppColors.ink,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -.2,
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: AppShapes.card,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: AppColors.midnight,
          disabledBackgroundColor: AppColors.raised,
          disabledForegroundColor: AppColors.muted,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: AppShapes.control,
          textStyle: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: .1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          side: const BorderSide(color: AppColors.border),
          shape: AppShapes.control,
          textStyle: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: .1,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          textStyle: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: TextStyle(color: AppColors.muted),
        hintStyle: TextStyle(color: AppColors.muted),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: AppColors.ink, width: 1.5),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.projector,
        linearTrackColor: AppColors.raised,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: AppColors.midnight),
        behavior: SnackBarBehavior.floating,
        shape: AppShapes.control,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextStyle display(double size, {Color color = AppColors.ink}) =>
      GoogleFonts.archivo(
        fontSize: size,
        height: 1.03,
        letterSpacing: size >= 32 ? -1.2 : -.35,
        fontWeight: FontWeight.w800,
        color: color,
      );

  static TextStyle utility({
    double size = 10,
    Color color = AppColors.muted,
    FontWeight weight = FontWeight.w600,
  }) => GoogleFonts.manrope(
    fontSize: size,
    height: 1.2,
    letterSpacing: .35,
    fontWeight: weight,
    color: color,
  );
}
