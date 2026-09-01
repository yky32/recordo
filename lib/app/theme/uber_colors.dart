import 'package:flutter/material.dart';
import 'package:recordo/core/config/recordo_config.dart';
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

  /// Dark: Mapbox Dark v11 when `MAPBOX_PK` is set; else Esri z16.
  /// Light: OSM. Never CARTO.
  static String get mapTileUrl {
    if (!_dark) return mapTileFallback;
    if (RecordoConfig.mapboxEnabled) {
      final pk = Uri.encodeQueryComponent(RecordoConfig.mapboxPk);
      return 'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/256/{z}/{x}/{y}@2x?access_token=$pk';
    }
    return 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}';
  }

  static int get mapMaxNativeZoom {
    if (!_dark) return 19;
    return RecordoConfig.mapboxEnabled ? 18 : 16;
  }

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
