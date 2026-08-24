import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:recordo/app/theme/uber_colors.dart';

/// Uber-class density — dark default, light optional.
abstract final class RecordoTheme {
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    // Snapshot palette as if this brightness is active for ThemeData construction.
    // Runtime widgets still read UberColors getters (ThemeController).
    final bg = isDark ? const Color(0xFF000000) : const Color(0xFFF3F3F3);
    final surface = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
    final onSurface = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    final muted = isDark ? const Color(0xFF8E8E93) : const Color(0xFF6B6B6B);
    final sheet = isDark ? const Color(0xFF121212) : const Color(0xFFFFFFFF);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: onSurface,
        onPrimary: bg,
        secondary: UberColors.accent,
        onSecondary: Colors.white,
        error: UberColors.danger,
        onError: Colors.white,
        surface: surface,
        onSurface: onSurface,
      ),
    );

    return base.copyWith(
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
        bodyColor: onSurface,
        displayColor: onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: sheet,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dividerColor: muted.withValues(alpha: 0.25),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: GoogleFonts.plusJakartaSans(color: onSurface),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return UberColors.accent;
          return muted;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return UberColors.accent.withValues(alpha: 0.45);
          }
          return muted.withValues(alpha: 0.35);
        }),
      ),
    );
  }
}

abstract final class RType {
  static TextStyle display() => GoogleFonts.syne(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.25,
        color: UberColors.white,
      );

  static TextStyle title() => GoogleFonts.syne(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.3,
        color: UberColors.white,
      );

  static TextStyle titleSm() => GoogleFonts.plusJakartaSans(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: UberColors.white,
      );

  static TextStyle body() => GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: UberColors.white,
        height: 1.4,
      );

  static TextStyle muted() => GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.35,
        color: UberColors.muted,
      );

  static TextStyle label() => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        height: 1.3,
        color: UberColors.muted,
      );
}
