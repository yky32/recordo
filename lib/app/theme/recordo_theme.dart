import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:recordo/app/theme/uber_colors.dart';

/// Uber-class dark density — feel only, original product.
abstract final class RecordoTheme {
  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: UberColors.black,
      colorScheme: const ColorScheme.dark(
        surface: UberColors.elevated,
        primary: UberColors.white,
        onPrimary: UberColors.black,
        secondary: UberColors.accent,
        onSurface: UberColors.white,
      ),
    );
    return base.copyWith(
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
        bodyColor: UberColors.white,
        displayColor: UberColors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: UberColors.white,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: UberColors.sheet,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: UberColors.elevated,
        contentTextStyle: GoogleFonts.plusJakartaSans(color: UberColors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

abstract final class RType {
  static TextStyle display() => GoogleFonts.syne(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: UberColors.white,
      );

  static TextStyle title() => GoogleFonts.syne(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: UberColors.white,
      );

  static TextStyle titleSm() => GoogleFonts.plusJakartaSans(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: UberColors.white,
      );

  static TextStyle body() => GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: UberColors.white,
        height: 1.35,
      );

  static TextStyle muted() => GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: UberColors.muted,
      );

  static TextStyle label() => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: UberColors.muted,
      );
}
