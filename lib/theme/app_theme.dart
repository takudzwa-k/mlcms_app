import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/cupertino.dart';



class AppColors {
  // Sampled from the Figma screens
  static const teal = Color(0xFF08766D);
  static const ok = Color(0xFF307C68);
  static const danger = Color(0xFFBC5050);
  static const warn = Color(0xFFAC7428);

  // Surfaces
  static const background = Color(0xFFF0EFE8); // light cream
  static const surface = Color(0xFFFFFFFF); // pure white
  static const headerTint = Color(0xFFEBF3F0);
  static const selected = Color(0xFFE6F1EC);

  // Soft fills for pills and callouts
  static const tealLight = Color(0xFFD9ECE7);
  static const okLight = Color(0xFFE8F4F0);
  static const dangerLight = Color(0xFFF8E6E4);
  static const warnLight = Color(0xFFF8F0E8);
  static const purple = Color(0xFF6B5B9A);
  static const purpleLight = Color(0xFFF0ECF8);

  static const ink = Color(0xFF16262B);
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  // Monospace style used for temperatures and other numbers
  static TextStyle mono({
    double size = 16,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF16272B) : AppColors.surface;
    final border = isDark ? Colors.white12 : const Color(0xFFE2E8E4);
    final textColor = isDark ? Colors.white : AppColors.ink;
    final base = ThemeData(brightness: brightness, useMaterial3: true);

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.teal,
        brightness: brightness,
      ),
      textTheme: GoogleFonts.dmSansTextTheme(base.textTheme),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),      
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0E1A1D) : AppColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.dmSans(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
        iconTheme: IconThemeData(color: textColor),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
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
          borderSide: const BorderSide(color: AppColors.teal, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.teal,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
      ),
    );
  }
}