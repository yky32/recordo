import 'package:flutter/material.dart';
import 'package:recordo/core/theme/theme_controller.dart';

/// Uber-adjacent palette. Values follow [ThemeController] (dark default).
abstract final class UberColors {
  static bool get _dark => ThemeController.instance.isDark;

  /// Scaffold / deepest bg
  static Color get black =>
      _dark ? const Color(0xFF000000) : const Color(0xFFF3F3F3);

  /// Bottom sheet
  static Color get sheet =>
      _dark ? const Color(0xFF121212) : const Color(0xFFFFFFFF);

  static Color get elevated =>
      _dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);

  static Color get elevated2 =>
      _dark ? const Color(0xFF2C2C2E) : const Color(0xFFE8E8E8);

  /// Primary text / icons on dark surfaces (inverted in light)
  static Color get white =>
      _dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);

  static Color get muted =>
      _dark ? const Color(0xFF8E8E93) : const Color(0xFF6B6B6B);

  static Color get hairline =>
      _dark ? const Color(0xFF3A3A3C) : const Color(0xFFD6D6D6);

  /// Soft green status — not Uber trademark lockup.
  static const accent = Color(0xFF06C167);

  /// Confirm / success chip. Dark forest in night, mint in light so body
  /// text (`white` token) stays readable without a special on-color.
  static Color get accentSurface =>
      _dark ? const Color(0xFF1A2E1A) : const Color(0xFFDFF6E8);

  /// Always-white glyph on solid [accent] (P badge, selected pin).
  static const onAccent = Color(0xFFFFFFFF);

  static const danger = Color(0xFFFF3B30);

  static Color get pin =>
      _dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);

  static Color get mapRoad =>
      _dark ? const Color(0xFF1A1A1A) : const Color(0xFFE5E5E5);

  static Color get mapBlock =>
      _dark ? const Color(0xFF0D0D0D) : const Color(0xFFE8E8E8);

  static Color get mapGrid =>
      _dark ? const Color(0xFF242424) : const Color(0xFFD0D0D0);

  /// Floating chrome (search bar) — glass-ish
  static Color get chrome =>
      _dark ? const Color(0xF0121212) : const Color(0xF0FFFFFF);

  /// Inverse fill button (white on dark / black on light)
  static Color get ctaFill =>
      _dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);

  static Color get ctaOnFill =>
      _dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

  /// Raster basemap — no vendor API key (CARTO watermarks "API KEY REQUIRED").
  /// Dark: Esri World Dark Gray (native max **16** — z17+ is a JPEG that says
  /// "Map data not yet available"). Light: OSM.
  static String get mapTileUrl => _dark
      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}'
      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static int get mapMaxNativeZoom => _dark ? 16 : 19;

  static const mapTileFallback =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static OutlineInputBorder fieldOutline({bool focused = false}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: focused
            ? (_dark ? const Color(0x66FFFFFF) : const Color(0xFF111111))
            : hairline,
        width: focused ? 1.4 : 1,
      ),
    );
  }
}
